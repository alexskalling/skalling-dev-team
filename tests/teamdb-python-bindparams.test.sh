#!/usr/bin/env bash
# tests/teamdb-python-bindparams.test.sh — Validación de teamdb_exec.py con bind params (T-2.10)
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

# Sourcear lib-teamdb.sh
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"

# 1. teamdb_exec_query existe
if type teamdb_exec_query >/dev/null 2>&1; then
  assert_pass "teamdb_exec_query definida"
else
  assert_fail "teamdb_exec_query definida" "no existe"
fi

# 2. teamdb_exec_write existe
if type teamdb_exec_write >/dev/null 2>&1; then
  assert_pass "teamdb_exec_write definida"
else
  assert_fail "teamdb_exec_write definida" "no existe"
fi

# 3. teamdb_exec_transaction existe
if type teamdb_exec_transaction >/dev/null 2>&1; then
  assert_pass "teamdb_exec_transaction definida"
else
  assert_fail "teamdb_exec_transaction definida" "no existe"
fi

# 4. teamdb_exec.py existe y es ejecutable
if [ -f "$ROOT/scripts/teamdb_exec.py" ] && [ -x "$ROOT/scripts/teamdb_exec.py" ]; then
  assert_pass "scripts/teamdb_exec.py existe y ejecutable"
else
  assert_fail "scripts/teamdb_exec.py existe y ejecutable"
fi

# 5. Insert con bound params (no escape manual)
result="$(teamdb_exec_query "$DB" "SELECT ? AS r" "it works")"
if echo "$result" | grep -q '"r": "it works"'; then
  assert_pass "bind param retorna 'it works'"
else
  assert_fail "bind param retorna 'it works'" "result=$result"
fi

# 6. Query con múltiples params
teamdb_exec_write "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))" \
  "jwt" "JWT Auth" "refresh tokens" >/dev/null
COUNT=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM concepts WHERE slug = ?" "jwt")
if echo "$COUNT" | grep -q '"n": 1'; then
  assert_pass "INSERT con bind + SELECT cuenta correctamente"
else
  assert_fail "INSERT con bind + SELECT cuenta correctamente" "result=$COUNT"
fi

# 7. SQLi REAL: con binding, el valor se trata como dato, no como SQL
result="$(teamdb_exec_query "$DB" "SELECT length(?) AS l" "x'); DROP TABLE concepts; --")"
if echo "$result" | grep -q '"l": 28'; then
  assert_pass "SQLi: valor tratado como string (length=28)"
else
  assert_fail "SQLi: valor tratado como string (length=28)" "result=$result"
fi
# Verificar que la tabla concepts SIGUE EXISTIENDO
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'")
if [ "$EXISTS" = "concepts" ]; then
  assert_pass "SQLi en valor no ejecuta DROP (tabla concepts preservada)"
else
  assert_fail "SQLi en valor no ejecuta DROP (tabla concepts preservada)" "missing"
fi

# 8. CLI directo funciona
CLI_OUT="$(python3 "$ROOT/scripts/teamdb_exec.py" --db "$DB" --mode query \
  --sql "SELECT ? AS r" --params '["foo"]')"
if echo "$CLI_OUT" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d and d[0]['r']=='foo' else 1)"; then
  assert_pass "CLI teamdb_exec.py retorna binded param"
else
  assert_fail "CLI teamdb_exec.py retorna binded param" "out=$CLI_OUT"
fi

# 9. CLI --mode write retorna JSON con changes/lastrowid
CLI_W="$(python3 "$ROOT/scripts/teamdb_exec.py" --db "$DB" --mode write \
  --sql "INSERT INTO decisions(slug,title,body_md,decided_at) VALUES(?,?,?,datetime('now'))" \
  --params '["use-jwt","Use JWT","d"]')"
if echo "$CLI_W" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get('changes')==1 and d.get('lastrowid',0)>=1 else 1)"; then
  assert_pass "CLI --mode write retorna {changes, lastrowid}"
else
  assert_fail "CLI --mode write retorna {changes, lastrowid}" "out=$CLI_W"
fi

# 10. Modo raw rechaza DML
RAW_ERR="$(python3 "$ROOT/scripts/teamdb_exec.py" --db "$DB" --mode raw --sql "DROP TABLE concepts" 2>&1)" || true
if echo "$RAW_ERR" | grep -qE "DML/DDL|destructivo|peligroso"; then
  assert_pass "raw mode rechaza DROP"
else
  assert_fail "raw mode rechaza DROP" "out=$RAW_ERR"
fi

# 11. Modo raw acepta SELECT
RAW_OK="$(python3 "$ROOT/scripts/teamdb_exec.py" --db "$DB" --mode raw --sql "SELECT 42 AS n" 2>&1)"
if echo "$RAW_OK" | grep -q '"n": 42'; then
  assert_pass "raw mode acepta SELECT"
else
  assert_fail "raw mode acepta SELECT" "out=$RAW_OK"
fi

# 12. Modo raw acepta DDL no-drop (CREATE TABLE TEMP)
RAW_DDL="$(python3 "$ROOT/scripts/teamdb_exec.py" --db "$DB" --mode raw --sql "CREATE TEMP TABLE _t (x INT)" 2>&1)"
if echo "$RAW_DDL" | grep -qE "\[\]"; then
  assert_pass "raw mode acepta DDL benigno (CREATE TEMP)"
else
  assert_fail "raw mode acepta DDL benigno (CREATE TEMP)" "out=$RAW_DDL"
fi

# 12b. M5 (Luz): raw rechaza CTE-DML (WITH ... DELETE) aunque empiece con prefijo benigno
RAW_CTE="$(python3 "$ROOT/scripts/teamdb_exec.py" --db "$DB" --mode raw --sql "WITH c AS (SELECT 1) DELETE FROM audit_log" 2>&1)"
if echo "$RAW_CTE" | grep -qE "DML/DDL|destructivo|peligroso"; then
  assert_pass "raw mode rechaza CTE-DML (WITH ... DELETE)"
else
  assert_fail "raw mode rechaza CTE-DML (WITH ... DELETE)" "out=$RAW_CTE"
fi

# 13. transaction: BEGIN IMMEDIATE + commit atómico
teamdb_exec_transaction "$DB" \
  "INSERT INTO audit_log(ts,agent,action,table_name) VALUES(datetime('now'),?,'via_test','concepts')" \
  "transaction-actor" >/dev/null 2>&1
COUNT_AUDIT=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM audit_log WHERE agent = ?" "transaction-actor")
if echo "$COUNT_AUDIT" | grep -q '"n": 1'; then
  assert_pass "transaction inserta audit_log atómicamente"
else
  assert_fail "transaction inserta audit_log atómicamente" "result=$COUNT_AUDIT"
fi

# 14. teamdb_safe_query está deprecada pero sigue exportada (backward-compat Fase 1)
if type teamdb_safe_query >/dev/null 2>&1; then
  assert_pass "teamdb_safe_query sigue exportada (backward-compat)"
else
  assert_fail "teamdb_safe_query sigue exportada (backward-compat)"
fi

# 15. Shellcheck del lib-teamdb.sh
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/lib/lib-teamdb.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "lib-teamdb.sh shellcheck 0 errores"
else
  assert_fail "lib-teamdb.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

# 16. Python ast parse
if python3 -c "import ast; ast.parse(open('$ROOT/scripts/teamdb_exec.py').read())" 2>/dev/null; then
  assert_pass "teamdb_exec.py parsea como AST válido"
else
  assert_fail "teamdb_exec.py parsea como AST válido"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
