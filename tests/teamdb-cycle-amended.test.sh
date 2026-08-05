#!/usr/bin/env bash
# tests/teamdb-cycle-amended.test.sh — Validación teamdb-plan unificado (T-2.17v2)
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

# ─── Caso 1: tasks.md con dependencias via _depends
cat > /tmp/cycle-tasks.md <<'EOF'
- [ ] Endpoint POST /login
- [ ] Validar JWT _depends: [task-endpoint-post-login]
- [ ] Tests integración _depends: [task-endpoint-post-login, task-validar-jwt]
EOF

bash "$ROOT/scripts/teamdb-plan.sh" "$TEST_DIR" "cycle-test" "Cycle feature" /tmp/cycle-tasks.md >/dev/null 2>&1

# 1. proposal creado
P=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM proposals WHERE slug='cycle-test'")
if [ "$P" = "1" ]; then
  assert_pass "proposal creado"
else
  assert_fail "proposal creado" "count=$P"
fi

# 2. plan creado
PL=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plans WHERE slug='cycle-test'")
if [ "$PL" = "1" ]; then
  assert_pass "plan creado"
else
  assert_fail "plan creado" "count=$PL"
fi

# 3. tasks creados
T=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test')")
if [ "$T" = "3" ]; then
  assert_pass "3 tasks creados"
else
  assert_fail "3 tasks creados" "count=$T"
fi

# 4. DAG edges creados (0 + 1 + 2 = 3)
DEPS=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_dependencies WHERE task_id IN (SELECT id FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test'))")
if [ "$DEPS" = "3" ]; then
  assert_pass "3 edges DAG creados (0+1+2=3)"
else
  assert_fail "3 edges DAG creados" "count=$DEPS"
fi

# 5. plan_history registrado
HIST=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test')")
if [ "$HIST" -ge 1 ]; then
  assert_pass "plan_history tiene row de 'created' (=$HIST)"
else
  assert_fail "plan_history tiene row" "count=$HIST"
fi

# 6. NO toca work_in_progress
WIP=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM work_in_progress WHERE slug='cycle-test'")
if [ "$WIP" = "0" ]; then
  assert_pass "NO escribe en work_in_progress (legacy)"
else
  assert_fail "NO escribe en work_in_progress" "count=$WIP"
fi

# 7. Slug de tasks normalizado
COUNT_NORMALIZED=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE slug='task-endpoint-post-login' AND plan_id=(SELECT id FROM plans WHERE slug='cycle-test')")
if [ "$COUNT_NORMALIZED" = "1" ]; then
  assert_pass "slug normalizado (task-endpoint-post-login)"
else
  assert_fail "slug normalizado" "count=$COUNT_NORMALIZED"
fi

# ─── Caso 2: amend sobre el plan funciona
bash "$ROOT/scripts/teamdb-amend.sh" "cycle-test" --modify-task=task-validar-jwt --new-title="Validar JWT (modificado)" --by teo "$TEST_DIR" >/dev/null 2>&1
TITLE_VJ=$(teamdb_exec_value "$DB" "SELECT title FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test') AND slug='task-validar-jwt'")
if echo "$TITLE_VJ" | grep -q "modificado"; then
  assert_pass "amend sobre plan (task title modificado)"
else
  assert_fail "amend sobre plan" "title=$TITLE_VJ"
fi

# 8. plan_history tiene 2+ rows (created + amended)
HIST=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test')")
if [ "$HIST" -ge 2 ]; then
  assert_pass "plan_history tiene created + amended (=$HIST)"
else
  assert_fail "plan_history >=2" "count=$HIST"
fi

# 9. runnable inicial: solo la task sin deps
RUNNABLE=$(bash "$ROOT/scripts/teamdb-deps.sh" runnable "cycle-test" "$TEST_DIR" 2>&1)
RUNNABLE_TASKS=$(echo "$RUNNABLE" | grep -oE '"slug": "task-[a-z-]+"' | sort -u | wc -l | tr -d ' ')
if [ "$RUNNABLE_TASKS" = "1" ]; then
  assert_pass "inicial: solo task-endpoint-post-login runnable"
else
  assert_fail "inicial: 1 runnable" "count=$RUNNABLE_TASKS runnable=$RUNNABLE"
fi

# 10. tras marcar endpoint approved, validar-jwt runnable
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug='cycle-test'")
teamdb_exec_write "$DB" "UPDATE tasks SET status='approved' WHERE plan_id=? AND slug='task-endpoint-post-login'" "$PLAN_ID" >/dev/null
RUNNABLE=$(bash "$ROOT/scripts/teamdb-deps.sh" runnable "cycle-test" "$TEST_DIR" 2>&1)
RUNNABLE_TASKS=$(echo "$RUNNABLE" | grep -oE '"slug": "task-[a-z-]+"' | sort -u | wc -l | tr -d ' ')
if [ "$RUNNABLE_TASKS" = "1" ] && echo "$RUNNABLE" | grep -q "validar-jwt"; then
  assert_pass "post-approved: validar-jwt runnable"
else
  assert_fail "post-approved: validar-jwt runnable" "runnable=$RUNNABLE"
fi

# 11. Idempotente: re-ejecutar teamdb-plan no duplica
bash "$ROOT/scripts/teamdb-plan.sh" "$TEST_DIR" "cycle-test" "Cycle feature" /tmp/cycle-tasks.md >/dev/null 2>&1
T_AFTER=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test')")
if [ "$T_AFTER" = "3" ]; then
  assert_pass "teamdb-plan idempotente (no duplica tasks)"
else
  assert_fail "teamdb-plan idempotente" "count=$T_AFTER"
fi

# 12. Tasks sin _depends no tienen edges
T_NO_DEPS=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_dependencies WHERE task_id=(SELECT id FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='cycle-test') AND slug='task-endpoint-post-login')")
if [ "$T_NO_DEPS" = "0" ]; then
  assert_pass "task sin _depends no tiene edges"
else
  assert_fail "task sin _depends" "count=$T_NO_DEPS"
fi

# 13. tasks.md sin tasks
cat > /tmp/empty-tasks.md <<'EOF'
# Sin tasks
Solo descripción.
EOF
run_capture() {
  local _CAP_RC=0
  _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
  CAPTURE_RC="$_CAP_RC"
  CAPTURE_OUT="$_CAP_OUT"
}
run_capture "bash '$ROOT/scripts/teamdb-plan.sh' '$TEST_DIR' 'empty-test' 'Empty' /tmp/empty-tasks.md"
if [ "$CAPTURE_RC" = "0" ]; then
  EMPTY_T=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='empty-test')")
  if [ "$EMPTY_T" = "0" ]; then
    assert_pass "tasks.md sin tasks: 0 tasks creados"
  else
    assert_fail "tasks.md sin tasks" "count=$EMPTY_T"
  fi
else
  assert_fail "tasks.md sin tasks retorna exit 0" "rc=$CAPTURE_RC"
fi

# 14. args incompletos fallan
run_capture "bash '$ROOT/scripts/teamdb-plan.sh' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "args incompletos rechazados"
else
  assert_fail "args incompletos rechazados" "rc=0"
fi

# 15. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-plan.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-plan.sh shellcheck 0 errores"
else
  assert_fail "teamdb-plan.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

# 16. test full cycle (T-2.17v2 cubre end-to-end de plan→amend→deps)
run_capture "bash '$ROOT/scripts/teamdb-plan.sh' '$TEST_DIR' 'e2e' 'E2E test' /tmp/cycle-tasks.md"
if [ "$CAPTURE_RC" = "0" ]; then
  # claim, release, status
  bash "$ROOT/scripts/teamdb-claim.sh" "e2e" "task-endpoint-post-login" --actor=teo --input-hash=h1 --ttl=60 "$TEST_DIR" >/dev/null 2>&1
  CLAIM=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_claims WHERE task_id=(SELECT id FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='e2e') AND slug='task-endpoint-post-login')")
  if [ "$CLAIM" -ge 1 ]; then
    assert_pass "ciclo end-to-end: claim funciona sobre plan creado por teamdb-plan"
  else
    assert_fail "ciclo end-to-end: claim" "count=$CLAIM"
  fi
else
  assert_fail "ciclo end-to-end: plan crea e2e" "rc=$CAPTURE_RC"
fi

rm -rf "$TEST_DIR" /tmp/cycle-tasks.md /tmp/empty-tasks.md
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
