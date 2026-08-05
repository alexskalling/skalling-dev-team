#!/usr/bin/env bash
# tests/agents-teamdb-integration.test.sh — TeamDB integrado en los 8 agentes (T-3.5)
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

for agent in "$ROOT"/agents-base/*.md; do
  base="$(basename "$agent" .md)"
  if grep -q "teamdb_query_project\|teamdb_query_global" "$agent"; then
    assert_pass "$base usa teamdb_query_*"
  elif grep -q "teamdb-N/A" "$agent"; then
    assert_pass "$base documenta teamdb-N/A explícitamente"
  else
    assert_fail "$base usa teamdb_query_* o documenta teamdb-N/A" "sin referencia"
  fi
done

# Alex y Jes deben tener query explícita
if grep -q "teamdb_query_project" "$ROOT/agents-base/Alex.md"; then
  assert_pass "Alex.md tiene teamdb_query_project"
else
  assert_fail "Alex.md tiene teamdb_query_project" "no aparece"
fi

if grep -q "teamdb_query_project" "$ROOT/agents-base/Jes.md"; then
  assert_pass "Jes.md tiene teamdb_query_project"
else
  assert_fail "Jes.md tiene teamdb_query_project" "no aparece"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
