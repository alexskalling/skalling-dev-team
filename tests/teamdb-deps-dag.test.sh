#!/usr/bin/env bash
# tests/teamdb-deps-dag.test.sh — Validación DAG + runnable + cycle detection (T-2.13)
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

# Setup plan + 3 tasks
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "dag-test" "DAG test" "# Intent" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug = ?" "dag-test")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'in_progress','sol',?,?)" \
  "dag-test" "DAG test" "$PID" "# Design" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "dag-test")
for i in 1 2 3; do
  teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,?,?,?,?)" \
    "$PLAN_ID" "task-$i" "Task $i" "$i" "teo" "$NOW" "$NOW" >/dev/null
done

# 1. add dependencia task-2 -> task-1
run_capture "bash '$ROOT/scripts/teamdb-deps.sh' add 'dag-test' 'task-2' 'task-1' '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  N=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_dependencies WHERE depends_on_task_id=(SELECT id FROM tasks WHERE plan_id=? AND slug='task-1')" "$PLAN_ID")
  if [ "$N" = "1" ]; then
    assert_pass "add task-2 -> task-1"
  else
    assert_fail "add task-2 -> task-1" "n=$N"
  fi
else
  assert_fail "add retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 2. add dependencia task-3 -> task-1
bash "$ROOT/scripts/teamdb-deps.sh" add "dag-test" "task-3" "task-1" "$TEST_DIR" >/dev/null 2>&1
N=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_dependencies")
if [ "$N" = "2" ]; then
  assert_pass "add task-3 -> task-1 (total 2 edges)"
else
  assert_fail "add task-3 -> task-1" "n=$N"
fi

# 3. add dependencia task-3 -> task-2
bash "$ROOT/scripts/teamdb-deps.sh" add "dag-test" "task-3" "task-2" "$TEST_DIR" >/dev/null 2>&1
N=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_dependencies")
if [ "$N" = "3" ]; then
  assert_pass "add task-3 -> task-2 (total 3 edges)"
else
  assert_fail "add task-3 -> task-2" "n=$N"
fi

# 4. runnable inicial: solo task-1
RUNNABLE=$(bash "$ROOT/scripts/teamdb-deps.sh" runnable "dag-test" "$TEST_DIR" 2>&1)
RUNNABLE_TASKS=$(echo "$RUNNABLE" | grep -oE '"slug": "task-[0-9]+"' | sort -u | wc -l | tr -d ' ')
if [ "$RUNNABLE_TASKS" = "1" ] && echo "$RUNNABLE" | grep -q '"slug": "task-1"'; then
  assert_pass "inicial: solo task-1 runnable"
else
  assert_fail "inicial: solo task-1 runnable" "runnable=$RUNNABLE count=$RUNNABLE_TASKS"
fi

# 5. tras marcar task-1 approved, task-2 runnable
teamdb_exec_write "$DB" "UPDATE tasks SET status='approved' WHERE plan_id=? AND slug='task-1'" "$PLAN_ID" >/dev/null
RUNNABLE=$(bash "$ROOT/scripts/teamdb-deps.sh" runnable "dag-test" "$TEST_DIR" 2>&1)
RUNNABLE_TASKS=$(echo "$RUNNABLE" | grep -oE '"slug": "task-[0-9]+"' | sort -u | wc -l | tr -d ' ')
if [ "$RUNNABLE_TASKS" = "1" ] && echo "$RUNNABLE" | grep -q '"slug": "task-2"'; then
  assert_pass "post-approved task-1: task-2 runnable"
else
  assert_fail "post-approved task-1: task-2 runnable" "runnable=$RUNNABLE"
fi

# 6. tras task-2 approved, task-3 runnable
teamdb_exec_write "$DB" "UPDATE tasks SET status='approved' WHERE plan_id=? AND slug='task-2'" "$PLAN_ID" >/dev/null
RUNNABLE=$(bash "$ROOT/scripts/teamdb-deps.sh" runnable "dag-test" "$TEST_DIR" 2>&1)
RUNNABLE_TASKS=$(echo "$RUNNABLE" | grep -oE '"slug": "task-[0-9]+"' | sort -u | wc -l | tr -d ' ')
if [ "$RUNNABLE_TASKS" = "1" ] && echo "$RUNNABLE" | grep -q '"slug": "task-3"'; then
  assert_pass "post-dual-approved: task-3 runnable"
else
  assert_fail "post-dual-approved: task-3 runnable" "runnable=$RUNNABLE"
fi

# 7. cycle detection: task-1 -> task-3 (cerraria el ciclo)
run_capture "bash '$ROOT/scripts/teamdb-deps.sh' add 'dag-test' 'task-1' 'task-3' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "cycle|ciclo"; then
  assert_pass "cycle detection rechaza edge task-1 -> task-3"
else
  assert_fail "cycle detection rechaza edge task-1 -> task-3" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 8. self-dependency rechazado
run_capture "bash '$ROOT/scripts/teamdb-deps.sh' add 'dag-test' 'task-1' 'task-1' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "self-dependency rechazado"
else
  assert_fail "self-dependency rechazado" "rc=0"
fi

# 9. dependencia inexistente rechazado
run_capture "bash '$ROOT/scripts/teamdb-deps.sh' add 'dag-test' 'task-1' 'no-existe' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "dependencia inexistente rechazada"
else
  assert_fail "dependencia inexistente rechazada" "rc=0"
fi

# 10. show lista dependencias
SHOW=$(bash "$ROOT/scripts/teamdb-deps.sh" show "dag-test" "$TEST_DIR" 2>&1)
EDGES=$(echo "$SHOW" | grep -oE 'task-[0-9]+' | wc -l | tr -d ' ')
if [ "$EDGES" -ge 3 ]; then
  assert_pass "show lista dependencias (=$EDGES matches)"
else
  assert_fail "show lista dependencias" "edges=$EDGES"
fi

# 11. remove elimina arista
run_capture "bash '$ROOT/scripts/teamdb-deps.sh' remove 'dag-test' 'task-2' 'task-1' '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  N=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_dependencies")
  if [ "$N" = "2" ]; then
    assert_pass "remove elimina arista (2 edges restantes)"
  else
    assert_fail "remove elimina arista" "n=$N"
  fi
else
  assert_fail "remove retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 12. Plan inexistente
run_capture "bash '$ROOT/scripts/teamdb-deps.sh' runnable 'no-existe' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "plan inexistente rechazado"
else
  assert_fail "plan inexistente rechazado" "rc=0"
fi

# 13. Opción inválida
run_capture "bash '$ROOT/scripts/teamdb-deps.sh' bogus arg '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "opción inválida rechazada"
else
  assert_fail "opción inválida rechazada" "rc=0"
fi

# 14. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-deps.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-deps.sh shellcheck 0 errores"
else
  assert_fail "teamdb-deps.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
