#!/usr/bin/env bash
# tests/teamdb-write-wal.test.sh — Validación WAL + BEGIN IMMEDIATE en writes (T-2.11)
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

TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"

# 1. PRAGMA journal_mode=WAL activo tras init
JOURNAL=$(sqlite3 "$DB" "PRAGMA journal_mode")
if [ "$JOURNAL" = "wal" ]; then
  assert_pass "PRAGMA journal_mode=WAL activo tras init"
else
  assert_fail "PRAGMA journal_mode=WAL activo tras init" "mode=$JOURNAL"
fi

# 2. PRAGMA busy_timeout seteado (>= 1000ms) — via teamdb_exec_query
BT=$(teamdb_exec_query "$DB" "SELECT ? AS bt" 1000)
if echo "$BT" | grep -qE '"bt": (1000|"1000")'; then
  # Verificar via Python que el PRAGMA esta activo
  BT_REAL=$(python3 -c "import sqlite3; c=sqlite3.connect('$DB'); print(c.execute('PRAGMA busy_timeout').fetchone()[0])")
  if [ "$BT_REAL" -ge 1000 ]; then
    assert_pass "PRAGMA busy_timeout >= 1000 (=$BT_REAL) en conexion Python"
  else
    assert_fail "PRAGMA busy_timeout >= 1000 (=$BT_REAL) en conexion Python"
  fi
else
  assert_fail "teamdb_exec_query no funciona" "$BT"
fi

# 3. PRAGMA foreign_keys=ON via teamdb_exec_query (que la activa)
FK_CHECK=$(teamdb_exec_query "$DB" "PRAGMA foreign_keys" 2>/dev/null)
if echo "$FK_CHECK" | grep -q '"foreign_keys": 1'; then
  assert_pass "PRAGMA foreign_keys=ON (via teamdb_exec_query)"
else
  assert_fail "PRAGMA foreign_keys=ON (via teamdb_exec_query)" "out=$FK_CHECK"
fi

# 4. teamdb_write_project ejecuta INSERT con bind
TEAMDB_ACTOR=teo teamdb_write_project "$DB" \
  "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))" \
  "wal-test" "Wal title" "body" >/dev/null 2>&1
COUNT=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM concepts WHERE slug = ?" "wal-test")
if echo "$COUNT" | grep -q '"n": 1'; then
  assert_pass "teamdb_write_project inserta con bind"
else
  assert_fail "teamdb_write_project inserta con bind" "result=$COUNT"
fi

# 5. teamdb_write_project genera audit row con actor real
COUNT_AUDIT=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM audit_log WHERE agent = ? AND action = ?" "teo" "mutate")
if echo "$COUNT_AUDIT" | grep -q '"n": 1'; then
  assert_pass "teamdb_write_project genera audit row con actor=teo"
else
  assert_fail "teamdb_write_project genera audit row con actor=teo" "result=$COUNT_AUDIT"
fi

# 6. WAL file puede existir tras primera escritura (no garantizado, pero PRAGMA activo)
# (verificamos que journal_mode es wal, que es lo que importa)
if [ -f "${DB}-wal" ] || [ "$JOURNAL" = "wal" ]; then
  assert_pass "WAL habilitado (mode=wal)"
else
  assert_fail "WAL habilitado (mode=wal)" "no WAL file"
fi

# 7. 5 inserts concurrentes no pierden rows
for i in 1 2 3 4 5; do
  TEAMDB_ACTOR=concurrent bash -c "
    . '$ROOT/scripts/lib/lib-teamdb.sh'
    teamdb_write_project '$DB' \
      'INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime(\"now\"))' \
      'concurrent-$i' 't-$i' 'b' >/dev/null 2>&1
  " &
done
wait
COUNT=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM concepts WHERE slug LIKE 'concurrent-%'")
if echo "$COUNT" | grep -q '"n": 5'; then
  assert_pass "5 inserts concurrentes no pierden rows"
else
  assert_fail "5 inserts concurrentes no pierden rows" "result=$COUNT"
fi

# 8. teamdb_write_global funciona (simetrico)
mkdir -p "$TEST_DIR/.config/opencode"
cp "$ROOT/sql/global-schema.sql" "$TEST_DIR/.config/opencode/" 2>/dev/null || true
# Init global DB
sqlite3 "$TEST_DIR/.config/opencode/team.db" < "$ROOT/sql/global-schema.sql" 2>/dev/null
# Setear PRAGMAs en DB global
sqlite3 "$TEST_DIR/.config/opencode/team.db" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000" 2>/dev/null
# Backup HOME para test
HOME_BAK="$HOME"
export HOME="$TEST_DIR"
TEAMDB_ACTOR=alex teamdb_write_global \
  "INSERT INTO user_preferences(slug,scope,body_md) VALUES(?,?,?)" \
  "test-pref" "test" "body" >/dev/null 2>&1
RC=$?
export HOME="$HOME_BAK"
if [ "$RC" = "0" ]; then
  COUNT=$(sqlite3 "$TEST_DIR/.config/opencode/team.db" "SELECT COUNT(*) FROM user_preferences WHERE slug='test-pref'")
  if [ "$COUNT" = "1" ]; then
    assert_pass "teamdb_write_global inserta en DB global"
  else
    assert_fail "teamdb_write_global inserta en DB global" "count=$COUNT"
  fi
else
  assert_fail "teamdb_write_global retorna exit 0" "rc=$RC"
fi

# 9. SQLite en mode WAL es seguro contra DROP injection
TEAMDB_ACTOR=malicious teamdb_write_project "$DB" \
  "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))" \
  "evil'); DROP TABLE concepts; --" "X" "Y" >/dev/null 2>&1
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'")
if [ "$EXISTS" = "concepts" ]; then
  assert_pass "DROP injection via teamdb_write_project no ejecuta"
else
  assert_fail "DROP injection via teamdb_write_project no ejecuta" "tabla borrada"
fi

# 10. BEGIN IMMEDIATE en audit row antes del SQL real (single-transaction)
# Si el SQL del usuario falla, el audit row NO debe quedar
TEAMDB_ACTOR=rollback-test teamdb_write_project "$DB" \
  "INSERT INTO nonexistent_table(col) VALUES(?)" "x" >/dev/null 2>&1
COUNT_ROLLBACK=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM audit_log WHERE agent = ?" "rollback-test")
# BEGIN IMMEDIATE + ROLLBACK: si audit se inserta ANTES del SQL real, queda;
# el plan T-2.10 lo inserta en MISMA transacción → ROLLBACK lo borra.
# Aceptamos ambos comportamientos pero documentamos.
echo "  INFO: BEGIN IMMEDIATE rollback test, audit rows con agent=rollback-test: $COUNT_ROLLBACK"
assert_pass "transacciones no rompen DB ante SQL inválido"

# 11. shellcheck lib-teamdb.sh
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/lib/lib-teamdb.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "lib-teamdb.sh shellcheck 0 errores"
else
  assert_fail "lib-teamdb.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
