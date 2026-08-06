#!/usr/bin/env bash
# tests/teamdb-link.test.sh — Auto-enlazado de grafo (teamdb-link.sh)
# Reglas: related por categoría compartida, uses de no-stack -> stack, related por tag compartido.
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

run_capture() {
  local rc=0
  _CAP_OUT="$(eval "$@" 2>&1)" || rc=$?
  _CAP_RC="$rc"
}

link_exists() {
  local db="$1"; local from="$2"; local type="$3"; local to="$4"
  sqlite3 "$db" "
    SELECT COUNT(*) FROM memory_links ml
    JOIN concepts a ON ml.from_table='concepts' AND a.id=ml.from_id
    JOIN concepts b ON ml.to_table='concepts' AND b.id=ml.to_id
    WHERE a.slug='$from' AND ml.link_type='$type' AND b.slug='$to'
  "
}

# ─── Fixture: DB con conceptos por categorías + tag compartido
TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
# ─── C0: fixture con schema actual (última migración aplicada por init)
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
FIX_VER=$(sqlite3 "$DB" "SELECT value FROM schema_meta WHERE key='version'")
LAST_MIG=$(ls "$ROOT/sql/migrations/"*.sql 2>/dev/null | sort | tail -1 | xargs -I{} basename {} .sql)
EXPECTED_VER=$(grep -oE "0\.[0-9]+\.[0-9]+" "$ROOT/sql/migrations/$LAST_MIG.sql" | tail -1)
if [ -f "$ROOT/sql/migrations/006_link_graph.sql" ] && [ "$FIX_VER" = "$EXPECTED_VER" ] && [ "$FIX_VER" != "0.7.6" -o "$FIX_VER" = "0.7.6" ]; then
  assert_pass "última migración aplicada: $FIX_VER ($LAST_MIG)"
else
  assert_fail "última migración aplicada" "ver=$FIX_VER expected=$EXPECTED_VER last_mig=$LAST_MIG"
fi

seed() {
  sqlite3 "$DB" <<'SQL'
INSERT INTO concepts(slug,title,category,body_md,updated_at) VALUES
  ('login','Login','auth','login flow',datetime('now')),
  ('sessions','Sessions','auth','session mgmt',datetime('now')),
  ('logout','Logout','auth','logout flow',datetime('now')),
  ('postgres','Postgres','stack','db',datetime('now')),
  ('modulo-app','App module','modulo','app',datetime('now')),
  ('modulo-docs','Docs module','modulo','docs',datetime('now'));
INSERT INTO tags(name) VALUES ('security');
INSERT INTO memory_tags(memory_table,memory_id,tag_id)
  SELECT 'concepts', id, (SELECT id FROM tags WHERE name='security')
  FROM concepts WHERE slug IN ('login','postgres');
SQL
}
seed

# ─── C1: related entre conceptos de la misma categoría
bash "$ROOT/scripts/teamdb-link.sh" "$TEST_DIR" >/dev/null 2>&1
R=$(link_exists "$DB" "login" "related" "sessions")
M=$(link_exists "$DB" "modulo-app" "related" "modulo-docs")
if [ "$R" = "1" ] && [ "$M" = "1" ]; then
  assert_pass "related por categoría (auth: login-sessions, modulo: modulo-app-docs)"
else
  assert_fail "related por categoría" "login-sessions=$R modulo-app-docs=$M"
fi

# ─── C2: uses de no-stack -> stack
U=$(link_exists "$DB" "modulo-app" "uses" "postgres")
U2=$(link_exists "$DB" "login" "uses" "postgres")
if [ "$U" = "1" ] && [ "$U2" = "1" ]; then
  assert_pass "uses módulo/auth -> stack (postgres)"
else
  assert_fail "uses -> stack" "modulo-app=$U login=$U2"
fi

# ─── C3: related por tag compartido (cross-categoría)
T=$(link_exists "$DB" "login" "related" "postgres")
if [ "$T" = "1" ]; then
  assert_pass "related por tag compartido (login-postgres / security)"
else
  assert_fail "related por tag" "login-postgres=$T"
fi

# ─── C4: idempotente (segunda corrida no agrega filas)
BEFORE=$(sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links")
bash "$ROOT/scripts/teamdb-link.sh" "$TEST_DIR" >/dev/null 2>&1
AFTER=$(sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links")
if [ "$BEFORE" = "$AFTER" ] && [ "$BEFORE" != "0" ]; then
  assert_pass "idempotente (links estables: $BEFORE)"
else
  assert_fail "idempotente" "before=$BEFORE after=$AFTER"
fi

# ─── C5: el grafo muestra los links (integración con teamdb-graph.sh)
run_capture 'bash "$ROOT/scripts/teamdb-graph.sh" "$TEST_DIR" text'
if echo "$_CAP_OUT" | grep -q "modulo-app.*uses.*postgres"; then
  assert_pass "teamdb-graph.sh muestra los links"
else
  assert_fail "teamdb-graph.sh muestra los links" "no aparece uses en el grafo"
fi

# ─── C6: categoría maliciosa en DB no se interpola (es dato, nunca SQL)
sqlite3 "$DB" "INSERT INTO concepts(slug,title,category,body_md,updated_at) VALUES('evil','Evil',\"x'); DROP TABLE concepts; --\",'x',datetime('now'))"
bash "$ROOT/scripts/teamdb-link.sh" "$TEST_DIR" >/dev/null 2>&1
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'")
EVIL_RELATED=$(sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links ml JOIN concepts a ON a.id=ml.from_id WHERE a.slug='evil' AND ml.link_type='related'")
RAW=$(sqlite3 "$DB" "SELECT category FROM concepts WHERE slug='evil'")
if [ "$EXISTS" = "concepts" ] && [ "$EVIL_RELATED" = "0" ] && echo "$RAW" | grep -q "DROP TABLE"; then
  assert_pass "categoría maliciosa se guarda como dato literal (sin interpolar, tablas intactas)"
else
  assert_fail "categoría maliciosa se guarda como dato literal" "EXISTS=$EXISTS evil_related=$EVIL_RELATED raw='$RAW'"
fi

# ─── C7: DB sin conceptos → exit 0, 0 links
EMPTY_DIR="$(mktemp -d)"
mkdir -p "$EMPTY_DIR/.opencode/context"
EMPTY_DB="$EMPTY_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$EMPTY_DIR" >/dev/null 2>&1
run_capture 'bash "$ROOT/scripts/teamdb-link.sh" "$EMPTY_DIR"'
EMPTY_LINKS=$(sqlite3 "$EMPTY_DB" "SELECT COUNT(*) FROM memory_links")
if [ "$_CAP_RC" = "0" ] && [ "$EMPTY_LINKS" = "0" ]; then
  assert_pass "DB vacía: exit 0 sin crear links"
else
  assert_fail "DB vacía" "rc=$_CAP_RC links=$EMPTY_LINKS"
fi

# ─── C8: audit_log registra el mutate del helper
AUDIT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE action='mutate' AND actor_source='helper'")
if [ "$AUDIT" != "0" ]; then
  assert_pass "audit_log registra writes del helper"
else
  assert_fail "audit_log registra writes del helper" "audit=$AUDIT"
fi

# ─── C9: --dry-run no escribe nada
DRY_DIR="$(mktemp -d)"
mkdir -p "$DRY_DIR/.opencode/context"
DRY_DB="$DRY_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$DRY_DIR" >/dev/null 2>&1
sqlite3 "$DRY_DB" "INSERT INTO concepts(slug,title,category,body_md,updated_at) VALUES('a','A','mod','x',datetime('now')),('b','B','mod','x',datetime('now'))"
run_capture 'bash "$ROOT/scripts/teamdb-link.sh" "$DRY_DIR" --dry-run'
DRY_LINKS=$(sqlite3 "$DRY_DB" "SELECT COUNT(*) FROM memory_links")
if [ "$_CAP_RC" = "0" ] && [ "$DRY_LINKS" = "0" ]; then
  assert_pass "--dry-run no escribe (links=$DRY_LINKS)"
else
  assert_fail "--dry-run no escribe" "rc=$_CAP_RC links=$DRY_LINKS"
fi

# ─── C10: no-regresión — R4 nunca crea link_type='part_of' entre concepts
PART_OF_DIR="$(mktemp -d)"
mkdir -p "$PART_OF_DIR/.opencode/context"
PART_OF_DB="$PART_OF_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$PART_OF_DIR" >/dev/null 2>&1
sqlite3 "$PART_OF_DB" "INSERT INTO concepts(slug,title,category,body_md,updated_at) VALUES('test-parent','Test Parent','mod','x',datetime('now')),('test-child','Test Child','mod','y',datetime('now'))"
bash "$ROOT/scripts/teamdb-link.sh" "$PART_OF_DIR" >/dev/null 2>&1
TOTAL_PART_OF=$(sqlite3 "$PART_OF_DB" "SELECT COUNT(*) FROM memory_links WHERE link_type='part_of'")
FWD_LINK=$(sqlite3 "$PART_OF_DB" "SELECT COUNT(*) FROM memory_links ml JOIN concepts a ON ml.from_table='concepts' AND a.id=ml.from_id JOIN concepts b ON ml.to_table='concepts' AND b.id=ml.to_id WHERE a.slug='test-parent' AND b.slug='test-child' AND ml.link_type='part_of'")
BWD_LINK=$(sqlite3 "$PART_OF_DB" "SELECT COUNT(*) FROM memory_links ml JOIN concepts a ON ml.from_table='concepts' AND a.id=ml.from_id JOIN concepts b ON ml.to_table='concepts' AND b.id=ml.to_id WHERE a.slug='test-child' AND b.slug='test-parent' AND ml.link_type='part_of'")
if [ "$TOTAL_PART_OF" = "0" ] && [ "$FWD_LINK" = "0" ] && [ "$BWD_LINK" = "0" ]; then
  assert_pass "R4 no crea part_of entre concepts (test-parent<->test-child, total_part_of=$TOTAL_PART_OF)"
else
  assert_fail "R4 no crea part_of entre concepts" "total_part_of=$TOTAL_PART_OF fwd=$FWD_LINK bwd=$BWD_LINK"
fi

rm -rf "$TEST_DIR" "$EMPTY_DIR" "$DRY_DIR" "$PART_OF_DIR"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
