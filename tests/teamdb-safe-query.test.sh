#!/usr/bin/env bash
# tests/teamdb-safe-query.test.sh — Validación del helper teamdb_safe_query (T-1.1)
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

TEST_DB="$(mktemp -d)/test.db"
mkdir -p "$(dirname "$TEST_DB")"
sqlite3 "$TEST_DB" < "$ROOT/sql/project-schema.sql"

LIB="$ROOT/scripts/lib/lib-teamdb.sh"
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$LIB"

if type teamdb_safe_query >/dev/null 2>&1; then
  assert_pass "teamdb_safe_query definida"
else
  assert_fail "teamdb_safe_query definida"
fi

out="$(teamdb_safe_query "$TEST_DB" exact "SELECT ? WHERE 1=1" $'\x1bmalicious' 2>&1)" || true
if echo "$out" | grep -q "Invalid input"; then
  assert_pass "rechaza control char ESC (0x1b)"
else
  assert_fail "rechaza control char ESC (0x1b)" "output=$out"
fi

out="$(teamdb_safe_query "$TEST_DB" exact "SELECT ? WHERE 1=1" $'\x07bell' 2>&1)" || true
if echo "$out" | grep -q "Invalid input"; then
  assert_pass "rechaza control char BEL (0x07)"
else
  assert_fail "rechaza control char BEL (0x07)" "output=$out"
fi

BIG="$(printf 'x%.0s' $(seq 1 1100))"
out="$(teamdb_safe_query "$TEST_DB" exact "SELECT ?" "$BIG" 2>&1)" || true
if echo "$out" | grep -q "Too long"; then
  assert_pass "rechaza input > 1024 chars"
else
  assert_fail "rechaza input > 1024 chars" "output=$out"
fi

out="$(teamdb_safe_query "$TEST_DB" bogus "SELECT ?" "x" 2>&1)" || true
if echo "$out" | grep -qE "Mode inv"; then
  assert_pass "rechaza mode inválido"
else
  assert_fail "rechaza mode inválido" "output=$out"
fi

result="$(teamdb_safe_query "$TEST_DB" exact "SELECT ? AS r" "42" 2>&1)"
if [ "$result" = "42" ]; then
  assert_pass "caso válido: SELECT ? AS r retorna 42"
else
  assert_fail "caso válido: SELECT ? AS r retorna 42" "result='$result'"
fi

DB_MISSING="$(mktemp -d)/nope.db"
out="$(teamdb_safe_query "$DB_MISSING" exact "SELECT ? AS r" "x" 2>&1)" || true
if echo "$out" | grep -q "DB no existe"; then
  assert_pass "DB inexistente rechazada"
else
  assert_fail "DB inexistente rechazada" "output=$out"
fi

result="$(teamdb_safe_query "$TEST_DB" exact "SELECT length(?)" "abc" 2>&1)"
if [ "$result" = "3" ]; then
  assert_pass "param bind correcto (length('abc')=3)"
else
  assert_fail "param bind correcto (length('abc')=3)" "result='$result'"
fi

result="$(teamdb_safe_query "$TEST_DB" exact "SELECT ? AS r" "value with 'quotes' and dollar" 2>&1)"
if [ "$result" = "value with 'quotes' and dollar" ]; then
  assert_pass "preserva comillas y caracteres especiales (escape SQL)"
else
  assert_fail "preserva comillas y caracteres especiales (escape SQL)" "result='$result'"
fi

# Caso crítico: inyección SQL en valor NO debe ejecutarse
sqlite3 "$TEST_DB" "CREATE TABLE IF NOT EXISTS concepts (id INTEGER PRIMARY KEY, slug TEXT)"
result="$(teamdb_safe_query "$TEST_DB" exact "SELECT ? AS r" "x'); DROP TABLE concepts; --" 2>&1)"
count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM sqlite_master WHERE name='concepts'")
if [ "$count" -ge 1 ]; then
  assert_pass "SQLi en valor NO ejecuta DROP (tabla concepts preservada)"
else
  assert_fail "SQLi en valor NO ejecuta DROP (tabla concepts preservada)" "concepts borrada"
fi

rm -rf "$(dirname "$TEST_DB")" "$(dirname "$DB_MISSING")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
