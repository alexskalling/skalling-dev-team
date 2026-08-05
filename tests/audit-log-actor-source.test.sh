#!/usr/bin/env bash
# tests/audit-log-actor-source.test.sh — actor_source: helper vs trigger (T-3.4)
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

if ! SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1; then
  assert_fail "teamdb-init.sh funciona" "init falló"
  echo "PASS=$PASS FAIL=$FAIL"
  exit 1
fi
assert_pass "teamdb-init.sh funciona"

# Mutación via helper con actor='sol' → fila audit con agent='sol' AND actor_source='helper'
HELPER_OUT="$(TEAMDB_ACTOR=sol bash -c "
  source '$ROOT/scripts/lib/lib-teamdb.sh'
  teamdb_write_project '$DB' \"INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('helper-test','HT','x',datetime('now'))\"
" 2>&1)"
COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE agent='sol' AND actor_source='helper'" 2>/dev/null)"
if [ "$COUNT" -ge 1 ] 2>/dev/null; then
  assert_pass "helper escribe audit con actor='sol' y actor_source='helper'"
else
  assert_fail "helper escribe audit con actor='sol' y actor_source='helper'" "count=$COUNT helper_out=$HELPER_OUT"
fi

# Mutación raw sqlite3 → trigger dispara con actor_source='trigger'
sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('raw-test','RT','x',datetime('now'))"
COUNT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE agent='system' AND actor_source='trigger'" 2>/dev/null)"
if [ "$COUNT" -ge 1 ] 2>/dev/null; then
  assert_pass "trigger escribe audit con actor_source='trigger'"
else
  assert_fail "trigger escribe audit con actor_source='trigger'" "count=$COUNT"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
