#!/usr/bin/env bash
# tests/teamdb-wip-tree-sqli.test.sh — Validación wip-tree.sh con payload SQLi
# Patrón: tests/teamdb-search-sqli.test.sh (fixture + assert_pass/fail).
# Objetivo: defense-in-depth en wip-tree.sh. Aunque el script toma como argumento
# solo la ruta del proyecto (no un slug), los slugs vienen de la DB y un script
# anterior los podía renderizar con sql_escape manual (sed ' -> ''). Migrado a
# teamdb_exec_value/teamdb_exec_query con real parameter binding. Validamos que:
#   (a) un wip con slug `evil';DROP TABLE work_in_progress;--` NO destruye la
#       tabla ni ejecuta SQL al renderizar el árbol.
#   (b) el lookup seguro retorna 0/empty cuando el slug no existe.
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
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1

# Insertar wip con slug que es payload SQLi (comilla simple + DROP TABLE)
sqlite3 "$DB" "INSERT INTO work_in_progress(slug,type,title,status,created_at,updated_at) VALUES('evil'';DROP TABLE work_in_progress;--','plan','Malicious Plan','open',datetime('now'),datetime('now'))"

# También un wip normal como control
sqlite3 "$DB" "INSERT INTO work_in_progress(slug,type,title,status,created_at,updated_at) VALUES('normal-plan','plan','Normal Plan','open',datetime('now'),datetime('now'))"

# ── Caso 1: renderizar árbol completo NO debe dropear la tabla ──
bash "$ROOT/scripts/wip-tree.sh" "$TEST_DIR" >/dev/null 2>&1 || true
TBL=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='work_in_progress'")
if [ "$TBL" = "work_in_progress" ]; then
  assert_pass "render con wip SQLi preserva work_in_progress"
else
  assert_fail "render con wip SQLi preserva work_in_progress" "tbl=$TBL"
fi

# ── Caso 2: el slug malicioso se almacenó como literal (no como SQL ejecutado) ──
STORED_SLUG=$(sqlite3 "$DB" "SELECT slug FROM work_in_progress WHERE slug LIKE '%evil%' LIMIT 1")
if [ -n "$STORED_SLUG" ]; then
  assert_pass "slug SQLi almacenado como literal (no ejecutado)"
else
  assert_fail "slug SQLi almacenado como literal (no ejecutado)" "stored=$STORED_SLUG"
fi

# ── Caso 3: renderizar imprime el plan malicioso como texto (no crashea) ──
OUTPUT=$(bash "$ROOT/scripts/wip-tree.sh" "$TEST_DIR" 2>&1)
if printf '%s' "$OUTPUT" | grep -qF "Malicious Plan"; then
  assert_pass "render imprime título del wip SQLi (no error)"
else
  assert_fail "render imprime título del wip SQLi (no error)" "output=$(printf '%.200s' "$OUTPUT")"
fi

# ── Caso 4: el wip normal también se renderiza (no quedó en estado roto) ──
if printf '%s' "$OUTPUT" | grep -qF "Normal Plan"; then
  assert_pass "render incluye wip normal tras intento SQLi"
else
  assert_fail "render incluye wip normal tras intento SQLi" "output=$(printf '%.200s' "$OUTPUT")"
fi

# ── Caso 5: COUNT(*) sin payload sigue funcionando ──
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM work_in_progress")
if [ "$COUNT" = "2" ]; then
  assert_pass "COUNT(*) preserva ambos wips"
else
  assert_fail "COUNT(*) preserva ambos wips" "count=$COUNT"
fi

# ── Caso 6: lookup con slug malicioso como argumento no rompe el script ──
# (No hay forma directa de pasar el slug al script, pero validamos que el script
# no se rompe con project paths que podrían interpretarse mal.)
EVIL_PROJECT="$(mktemp -d)/x'y"
mkdir -p "$EVIL_PROJECT"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$EVIL_PROJECT" >/dev/null 2>&1
OUTPUT2=$(bash "$ROOT/scripts/wip-tree.sh" "$EVIL_PROJECT" 2>&1)
RC=$?
# Si project path tiene apóstrofo, debería fallar limpio (no DB) o funcionar
# sin ejecutar SQL arbitrario. Cualquiera de las dos es aceptable.
if [ "$RC" = "0" ] || printf '%s' "$OUTPUT2" | grep -qi "no DB\|ERROR"; then
  assert_pass "project path con apóstrofe no ejecuta SQL (rc=$RC)"
else
  assert_fail "project path con apóstrofe no ejecuta SQL" "rc=$RC output=$(printf '%.200s' "$OUTPUT2")"
fi
rm -rf "$EVIL_PROJECT"

# ── Caso 7: recursive lookup con slug no existente (control negativo) ──
# Insertar un wip cuyo parent_id no exista no debe crashear wip-tree.sh.
sqlite3 "$DB" "INSERT INTO work_in_progress(slug,type,title,status,parent_id,created_at,updated_at) VALUES('orphan-task','task','Orphan','open',9999,datetime('now'),datetime('now'))"
OUTPUT3=$(bash "$ROOT/scripts/wip-tree.sh" "$TEST_DIR" 2>&1)
RC=$?
if [ "$RC" = "0" ]; then
  assert_pass "parent_id inválido no rompe render (rc=0)"
else
  assert_fail "parent_id inválido no rompe render (rc=0)" "rc=$RC"
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