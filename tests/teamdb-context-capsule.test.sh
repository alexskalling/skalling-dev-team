#!/usr/bin/env bash
# tests/teamdb-context-capsule.test.sh — Validación context capsule (T-2.16)
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

# Setup: plan + task + memories
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "ctx-test" "Ctx" "# I" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "ctx-test")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'active','sol',?,?)" \
  "ctx-test" "Ctx" "$PID" "# D" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "ctx-test")
teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,1,?,?,?)" \
  "$PLAN_ID" "task-1" "Task 1" "teo" "$NOW" "$NOW" >/dev/null

# Memorias
teamdb_exec_write "$DB" "INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES(?,?,?,'concept',?)" \
  "auth-jwt" "JWT Auth" "JWT body" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO decisions(slug,title,body_md,status,decided_at,decided_by) VALUES(?,?,?,'accepted',?,?)" \
  "use-jwt" "Use JWT" "decision body" "$NOW" "pol" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO preferences(slug,scope,body_md) VALUES(?,?,?)" \
  "conv-commits" "repo" "use conventional commits" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO known_problems(slug,title,symptom_md,workaround_md,status,discovered_at) VALUES(?,?,?,?,'open',?)" \
  "conn-timeout" "Conn timeout" "slow" "retry" "$NOW" >/dev/null

# 1. link crea task_context_capsules
bash "$ROOT/scripts/teamdb-context.sh" link "ctx-test" "task-1" \
  --concepts=auth-jwt --decisions=use-jwt --preferences=conv-commits --problems=conn-timeout \
  "$TEST_DIR" >/dev/null 2>&1
COUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_context_capsules WHERE task_id=(SELECT id FROM tasks WHERE plan_id=? AND slug='task-1')" "$PLAN_ID")
if [ "$COUNT" = "4" ]; then
  assert_pass "link crea 4 task_context_capsules"
else
  assert_fail "link crea 4 task_context_capsules" "count=$COUNT"
fi

# 2. for-task retorna JSON con shape correcto
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "ctx-test" "task-1" "$TEST_DIR" 2>&1)
echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['task']['slug'] == 'task-1', d
assert d['plan']['slug'] == 'ctx-test', d
assert any(c['slug']=='auth-jwt' for c in d['concepts'])
assert any(x['slug']=='use-jwt' for x in d['decisions'])
assert any(p['slug']=='conv-commits' for p in d['preferences'])
assert any(k['slug']=='conn-timeout' for k in d['known_problems'])
print('OK')
" 2>&1 >/dev/null
if [ "$?" = "0" ]; then
  assert_pass "capsula shape correcto (task/plan/concepts/decisions/preferences/problems)"
else
  assert_fail "capsula shape correcto" "capsule=$CAPSULE"
fi

# 3. Filtra decisions rejected
teamdb_exec_write "$DB" "INSERT INTO decisions(slug,title,body_md,status,decided_at,decided_by) VALUES(?,?,?,'rejected',?,?)" \
  "rej-bcrypt" "Use bcrypt" "deferred" "$NOW" "pol" >/dev/null
bash "$ROOT/scripts/teamdb-context.sh" link "ctx-test" "task-1" --decisions=rej-bcrypt "$TEST_DIR" >/dev/null 2>&1
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "ctx-test" "task-1" "$TEST_DIR" 2>&1)
DECS_REJECTED=$(echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
rejected = [x for x in d['decisions'] if x.get('status') == 'rejected']
print(len(rejected))
")
if [ "$DECS_REJECTED" = "0" ]; then
  assert_pass "decisions rejected filtradas de la cápsula"
else
  assert_fail "decisions rejected filtradas" "rejected=$DECS_REJECTED"
fi

# 4. Filtra problems wontfix
teamdb_exec_write "$DB" "INSERT INTO known_problems(slug,title,symptom_md,workaround_md,status,discovered_at) VALUES(?,?,?,?,'wontfix',?)" \
  "wontfix-1" "Old problem" "x" "y" "$NOW" >/dev/null
bash "$ROOT/scripts/teamdb-context.sh" link "ctx-test" "task-1" --problems=wontfix-1 "$TEST_DIR" >/dev/null 2>&1
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "ctx-test" "task-1" "$TEST_DIR" 2>&1)
WF=$(echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
wf = [k for k in d['known_problems'] if k.get('status') == 'wontfix']
print(len(wf))
")
if [ "$WF" = "0" ]; then
  assert_pass "problems wontfix filtrados de la cápsula"
else
  assert_fail "problems wontfix filtrados" "wf=$WF"
fi

# 5. capsule es JSON valido
if echo "$CAPSULE" | python3 -c "import json, sys; json.loads(sys.stdin.read())"; then
  assert_pass "cápsula es JSON válido"
else
  assert_fail "cápsula es JSON válido"
fi

# 6. task inexistente → capsule vacia (no falla)
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "ctx-test" "no-task" "$TEST_DIR" 2>&1)
if [ "$CAPSULE" = "{}" ]; then
  assert_pass "task inexistente → cápsula vacía"
else
  assert_fail "task inexistente → cápsula vacía" "capsule=$CAPSULE"
fi

# 7. plan inexistente → capsule vacia
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "no-plan" "task-1" "$TEST_DIR" 2>&1)
if [ "$CAPSULE" = "{}" ]; then
  assert_pass "plan inexistente → cápsula vacía"
else
  assert_fail "plan inexistente → cápsula vacía" "capsule=$CAPSULE"
fi

# 8. link con memoria inexistente (no falla, solo warning)
run_capture() {
  local _CAP_RC=0
  _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
  CAPTURE_RC="$_CAP_RC"
  CAPTURE_OUT="$_CAP_OUT"
}
run_capture "bash '$ROOT/scripts/teamdb-context.sh' link 'ctx-test' 'task-1' --concepts=no-existe '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ] && echo "$CAPTURE_OUT" | grep -q "WARN"; then
  assert_pass "link con memoria inexistente no falla (warning)"
else
  assert_fail "link con memoria inexistente" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 9. link es idempotente (re-link no duplica)
COUNT_BEFORE=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_context_capsules")
bash "$ROOT/scripts/teamdb-context.sh" link "ctx-test" "task-1" --concepts=auth-jwt "$TEST_DIR" >/dev/null 2>&1
COUNT_AFTER=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_context_capsules")
if [ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; then
  assert_pass "link idempotente (no duplica)"
else
  assert_fail "link idempotente" "before=$COUNT_BEFORE after=$COUNT_AFTER"
fi

# 10. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-context.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-context.sh shellcheck 0 errores"
else
  assert_fail "teamdb-context.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
