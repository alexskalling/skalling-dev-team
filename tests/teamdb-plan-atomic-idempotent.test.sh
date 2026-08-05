#!/usr/bin/env bash
# tests/teamdb-plan-atomic-idempotent.test.sh — Issue 7 (atomicidad plan) + Issue 9 (idempotencia history)
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
  local _CAP_RC=0
  _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
  CAPTURE_RC="$_CAP_RC"
  CAPTURE_OUT="$_CAP_OUT"
}

TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"

# ─── Case A: re-ejecución no añade otro history 'created' (Issue 9)
echo "=== Issue 9: teamdb-plan idempotente en history ==="
cat > /tmp/plan-tasks.md <<'EOF'
- [ ] Task uno
- [ ] Task dos _depends: [task-task-uno]
EOF

run_capture "bash '$ROOT/scripts/teamdb-plan.sh' '$TEST_DIR' 'plan-a' 'Plan A' /tmp/plan-tasks.md"
if [ "$CAPTURE_RC" = "0" ]; then
  # Re-ejecutar sin cambios
  run_capture "bash '$ROOT/scripts/teamdb-plan.sh' '$TEST_DIR' 'plan-a' 'Plan A' /tmp/plan-tasks.md"
  CREATED_COUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='plan-a') AND operation='created'")
  if [ "$CREATED_COUNT" = "1" ]; then
    assert_pass "re-run sin cambios no duplica history created (=1)"
  else
    assert_fail "re-run sin cambios no duplica history created" "count=$CREATED_COUNT"
  fi
  # Tasks tampoco se duplican
  T_COUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='plan-a')")
  if [ "$T_COUNT" = "2" ]; then
    assert_pass "re-run no duplica tasks (=2)"
  else
    assert_fail "re-run no duplica tasks" "count=$T_COUNT"
  fi
else
  assert_fail "plan crea plan-a" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# ─── Case B: fallo a mitad no deja proposal/plan/tasks parciales (Issue 7)
echo "=== Issue 7: fallo de dependencia no deja estado parcial ==="
# Trigger que aborta el INSERT de la task 'boom' dentro de la transacción
sqlite3 "$DB" "CREATE TRIGGER tr_boom BEFORE INSERT ON tasks WHEN NEW.title = 'boom' BEGIN SELECT RAISE(ABORT, 'boom'); END;"
cat > /tmp/boom-tasks.md <<'EOF'
- [ ] task ok
- [ ] boom
EOF
run_capture "bash '$ROOT/scripts/teamdb-plan.sh' '$TEST_DIR' 'boom-test' 'Boom' /tmp/boom-tasks.md"
if [ "$CAPTURE_RC" != "0" ]; then
  # Si es atómico: nada quedó (ni proposal, ni plan, ni tasks)
  P_AFTER=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM proposals WHERE slug='boom-test'")
  PL_AFTER=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plans WHERE slug='boom-test'")
  T_AFTER=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='boom-test')")
  if [ "$P_AFTER" = "0" ] && [ "$PL_AFTER" = "0" ] && [ "$T_AFTER" = "0" ]; then
    assert_pass "fallo deja DB limpia (proposal=0 plan=0 tasks=0)"
  else
    assert_fail "fallo deja DB limpia" "proposal=$P_AFTER plan=$PL_AFTER tasks=$T_AFTER"
  fi
else
  assert_fail "plan con task 'boom' falla (rc!=0)" "rc=0 out=$CAPTURE_OUT"
fi

# ─── Limpiar
rm -rf "$TEST_DIR" /tmp/plan-tasks.md /tmp/boom-tasks.md
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
