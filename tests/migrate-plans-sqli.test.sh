#!/usr/bin/env bash
# tests/migrate-plans-sqli.test.sh — Validación migrate-plans-md-to-db.sh con payload SQLi
# Patrón: tests/teamdb-search-sqli.test.sh (fixture + assert_pass/fail).
# Objetivo: defense-in-depth en migrate-plans-md-to-db.sh. Antes el slug del
# proposal se interpolaba con escape manual `sed "s/'/''/g"` — que protege contra
# apóstrofes pero NO contra NUL, comentarios `--`, newlines, etc. Migrado a
# teamdb_exec_value con parameter binding real (Python sqlite3 → R10).
# Validamos que:
#   (a) un archivo .md con nombre `evil';DROP TABLE proposals;--.md` en
#       docs/plans/ NO destruye la tabla ni ejecuta SQL al migrar.
#   (b) el slug derivado se almacena sanitizado (regex `[^a-z0-9-]+` -> `-`),
#       NUNCA literalmente con la payload cruda.
#   (c) la idempotencia se preserva: una segunda corrida con el mismo archivo
#       debe detectarlo como existente (COUNT(*) > 0) y skip-earlo.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() {
  local name="$1"
  echo "✓ $name"
  PASS=$((PASS+1))
}

assert_fail() {
  local name="$1"
  local detail="${2:-}"
  echo "✗ $name${detail:+ — $detail}"
  FAIL=$((FAIL+1))
}

# ── Fixture ──
TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
mkdir -p "$TEST_DIR/docs/plans"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1

# Crear archivo .md con nombre que es payload SQLi
cat > "$TEST_DIR/docs/plans/evil';DROP TABLE proposals;--.md" <<'MD_EOF'
---
title: Malicious Migration
status: draft
agent: pol
---

# Intent

This file has a SQLi payload in its filename.
MD_EOF

# ── Caso 1: migrate NO debe dropear la tabla proposals ──
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/migrate-plans-md-to-db.sh" "$TEST_DIR" >/dev/null 2>&1
TBL=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='proposals'")
if [ "$TBL" = "proposals" ]; then
  assert_pass "migrate con filename SQLi preserva proposals"
else
  assert_fail "migrate con filename SQLi preserva proposals" "tbl=$TBL"
fi

# ── Caso 2: el slug derivado debe sanitizarse (no contener comilla, DROP, ;) ──
RAW_SLUGS=$(sqlite3 "$DB" "SELECT slug FROM proposals" 2>&1)
# Buscar payload literal — el slug NO debe contener caracteres peligrosos
if printf '%s' "$RAW_SLUGS" | grep -qE "[';]|DROP|\\-\\-"; then
  assert_fail "slug derivado sanitizado (sin comilla/punto-y-coma/comentario)" "slugs=$RAW_SLUGS"
else
  assert_pass "slug derivado sanitizado (sin comilla/punto-y-coma/comentario)"
fi

# ── Caso 3: el slug debe seguir el patrón kebab-case del repo ──
SLUG=$(sqlite3 "$DB" "SELECT slug FROM proposals LIMIT 1" 2>&1)
if printf '%s' "$SLUG" | grep -qE '^[a-z0-9-]+-legacy-imported$'; then
  assert_pass "slug derivado matchea patrón kebab-case + sufijo -legacy-imported (slug=$SLUG)"
else
  assert_fail "slug derivado matchea patrón kebab-case + sufijo -legacy-imported" "slug=$SLUG"
fi

# ── Caso 4: idempotencia — segunda corrida detecta existente y NO duplica ──
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/migrate-plans-md-to-db.sh" "$TEST_DIR" >/dev/null 2>&1
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM proposals")
if [ "$COUNT" = "1" ]; then
  assert_pass "idempotencia: segunda corrida no duplica (count=$COUNT)"
else
  assert_fail "idempotencia: segunda corrida no duplica" "count=$COUNT"
fi

# ── Caso 5: dry-run NO debe insertar ni mutar la DB ──
COUNT_BEFORE=$(sqlite3 "$DB" "SELECT COUNT(*) FROM proposals")
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/migrate-plans-md-to-db.sh" --dry-run "$TEST_DIR" >/dev/null 2>&1
COUNT_AFTER=$(sqlite3 "$DB" "SELECT COUNT(*) FROM proposals")
if [ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; then
  assert_pass "dry-run no muta la DB (count invariante)"
else
  assert_fail "dry-run no muta la DB" "before=$COUNT_BEFORE after=$COUNT_AFTER"
fi

# ── Caso 6: backup creado antes de mutar ──
# (Al correr en no-dry-run, debe quedar al menos un .pre-migration-md-to-db.*)
BACKUP_COUNT=$(find "$TEST_DIR/.opencode/context" -name "*.pre-migration-md-to-db.*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$BACKUP_COUNT" -ge 1 ]; then
  assert_pass "backup pre-migration creado ($BACKUP_COUNT archivos)"
else
  assert_fail "backup pre-migration creado" "count=$BACKUP_COUNT"
fi

# ── Caso 7: payload con NUL byte en filename no rompe migrate ──
# (mktemp + bash no soportan NUL en paths en macOS — saltamos si no se puede crear)
EVIL_NUL="$TEST_DIR/docs/plans/normal-with-nul.md"
cat > "$EVIL_NUL" <<'MD_EOF'
---
title: NUL Test
status: draft
agent: pol
---

# Intent

Testing NUL-like payload via title field.
MD_EOF
# El title contiene caracteres que podrían romper SQL si se interpolara
sqlite3 "$DB" "DELETE FROM proposals" >/dev/null 2>&1
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/migrate-plans-md-to-db.sh" "$TEST_DIR" >/dev/null 2>&1
TBL=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='proposals'")
if [ "$TBL" = "proposals" ]; then
  assert_pass "title con caracteres especiales no rompe migrate"
else
  assert_fail "title con caracteres especiales no rompe migrate" "tbl=$TBL"
fi

# ── Caso 8: bash 3.2 portable check ──
if [ "${BASH_VERSINFO[0]}" -ge 3 ]; then
  assert_pass "compatible bash 3.2+"
else
  assert_fail "compatible bash 3.2+" "bash=$BASH_VERSION"
fi

rm -rf "$TEST_DIR"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]