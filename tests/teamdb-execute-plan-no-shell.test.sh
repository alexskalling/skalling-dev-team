#!/usr/bin/env bash
# tests/teamdb-execute-plan-no-shell.test.sh — DC-3: no ejecuta shell desde DB
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

# Setup: plan con 2 tasks (la 2 depende de la 1)
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "exec-test" "Exec test" "# I" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "exec-test")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'active','sol',?,?)" \
  "exec-test" "Exec test" "$PID" "# D" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "exec-test")
teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,1,?,?,?)" \
  "$PLAN_ID" "task-1" "T1" "teo" "$NOW" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,2,?,?,?)" \
  "$PLAN_ID" "task-2" "T2" "teo" "$NOW" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO task_dependencies(task_id, depends_on_task_id, type, created_at) SELECT (SELECT id FROM tasks WHERE plan_id=? AND slug='task-2'), (SELECT id FROM tasks WHERE plan_id=? AND slug='task-1'), 'blocks', ?" \
  "$PLAN_ID" "$PLAN_ID" "$NOW" >/dev/null

# 1. execute-plan retorna JSON con next_task
OUT=$(bash "$ROOT/scripts/teamdb-execute-plan.sh" "exec-test" "$TEST_DIR" 2>&1)
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['plan_slug'] == 'exec-test', d
assert d['next_task']['slug'] == 'task-1', d
print('OK')
" 2>&1 >/dev/null
if [ "$?" = "0" ]; then
  assert_pass "execute-plan retorna next_task=task-1"
else
  assert_fail "execute-plan retorna next_task" "out=$OUT"
fi

# 2. DC-3: claim_command NO contiene eval/exec/sh -c con input de DB
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
cmd = d.get('claim_command', '')
# El comando es teamdb-claim.sh con args fijos (no DB-derived exec)
assert 'teamdb-claim.sh' in cmd, cmd
# NO debe contener 'eval', 'sh -c', 'bash -c', 'exec' con user input
forbidden = ['eval', 'sh -c', 'bash -c', '\`']
for f in forbidden:
    assert f not in cmd, '%s in cmd: %s' % (f, cmd)
print('OK')
" 2>&1 >/dev/null
if [ "$?" = "0" ]; then
  assert_pass "DC-3: claim_command no contiene shell desde DB"
else
  assert_fail "DC-3: claim_command no contiene shell desde DB" "out=$OUT"
fi

# 3. Tras aprobar task-1, next task es task-2
teamdb_exec_write "$DB" "UPDATE tasks SET status='approved' WHERE plan_id=? AND slug='task-1'" "$PLAN_ID" >/dev/null
OUT=$(bash "$ROOT/scripts/teamdb-execute-plan.sh" "exec-test" "$TEST_DIR" 2>&1)
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['next_task']['slug'] == 'task-2', d
print('OK')
" 2>&1 >/dev/null
if [ "$?" = "0" ]; then
  assert_pass "post-approved task-1: next=task-2"
else
  assert_fail "post-approved task-1: next=task-2" "out=$OUT"
fi

# 4. Sin runnable tasks
teamdb_exec_write "$DB" "UPDATE tasks SET status='approved' WHERE plan_id=? AND slug='task-2'" "$PLAN_ID" >/dev/null
OUT=$(bash "$ROOT/scripts/teamdb-execute-plan.sh" "exec-test" "$TEST_DIR" 2>&1)
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['next_task'] is None, d
print('OK')
" 2>&1 >/dev/null
if [ "$?" = "0" ]; then
  assert_pass "sin runnable tasks: next_task=null"
else
  assert_fail "sin runnable tasks" "out=$OUT"
fi

# 5. plan inexistente
run_capture() {
  local _CAP_RC=0
  _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
  CAPTURE_RC="$_CAP_RC"
  CAPTURE_OUT="$_CAP_OUT"
}
run_capture "bash '$ROOT/scripts/teamdb-execute-plan.sh' 'no-existe' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "plan inexistente rechazado"
else
  assert_fail "plan inexistente rechazado" "rc=0"
fi

# 6. SIN source DB-derived shell
# Inspecciono el script
if ! grep -E 'eval.*\\\$|sh -c.*\\\$|bash -c.*\\\$' "$ROOT/scripts/teamdb-execute-plan.sh" >/dev/null; then
  assert_pass "teamdb-execute-plan.sh sin eval/sh -c con variables DB"
else
  assert_fail "teamdb-execute-plan.sh sin eval/sh -c con variables DB"
fi

# 7. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-execute-plan.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-execute-plan.sh shellcheck 0 errores"
else
  assert_fail "teamdb-execute-plan.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
