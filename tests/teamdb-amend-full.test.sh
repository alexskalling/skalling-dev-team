#!/usr/bin/env bash
# tests/teamdb-amend-full.test.sh — Validación completa de teamdb-amend (T-2.12)
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

# Helper bash con captura correcta de exit code
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

# Sourcear lib-teamdb.sh para teamdb_exec_query en el test
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"

# Setup: crear plan+proposal+tasks directo via teamdb_exec_write (sin teamdb-plan.sh, T-2.17v2)
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" \
  "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "auth-jwt" "Auth feature" "# Intent" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_query "$DB" "SELECT id AS i FROM proposals WHERE slug = ?" "auth-jwt" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['i'])")
teamdb_exec_write "$DB" \
  "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'active','sol',?,?)" \
  "auth-jwt" "Auth feature" "$PID" "# Design" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_query "$DB" "SELECT id AS i FROM plans WHERE slug = ?" "auth-jwt" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['i'])")
for i in 1 2 3; do
  teamdb_exec_write "$DB" \
    "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,?,'teo',?,?)" \
    "$PLAN_ID" "task-$i" "Task $i inicial" "$i" "$NOW" "$NOW" >/dev/null
done
# Marcar task 1 como approved
teamdb_exec_write "$DB" \
  "UPDATE tasks SET status='approved', updated_at=? WHERE plan_id=? AND slug='task-1'" \
  "$NOW" "$PLAN_ID" >/dev/null

# 1. Marcar task 1 como approved (inmutable)
BEFORE_OK=$(teamdb_exec_query "$DB" "SELECT status AS s FROM tasks WHERE plan_id=? AND slug='task-1'" "$PLAN_ID")
if echo "$BEFORE_OK" | grep -q '"s": "approved"'; then
  assert_pass "setup: task 1 marcada approved"
else
  assert_fail "setup: task 1 marcada approved" "$BEFORE_OK"
fi

# 2. --add-task crea nueva task
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' --add-task='New task added' --by sol '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  COUNT_NEW=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND title='New task added'")
  if echo "$COUNT_NEW" | grep -q '"n": 1'; then
    assert_pass "add-task crea la task"
  else
    assert_fail "add-task crea la task" "result=$COUNT_NEW"
  fi
else
  assert_fail "add-task retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 3. --modify-task cambia el titulo
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' --modify-task=task-2 --new-title='Modified task 2' --by sol '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  TITLE_T2=$(teamdb_exec_query "$DB" "SELECT title AS t FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND slug='task-2'")
  if echo "$TITLE_T2" | grep -q "Modified task 2"; then
    assert_pass "modify-task cambia el título"
  else
    assert_fail "modify-task cambia el título" "$TITLE_T2"
  fi
else
  assert_fail "modify-task retorna exit 0" "rc=$CAPTURE_RC"
fi

# 4. --deprecate-task marca como rejected
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' --deprecate-task=task-3 --by teo '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  STATUS_T3=$(teamdb_exec_query "$DB" "SELECT status AS s FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND slug='task-3'")
  if echo "$STATUS_T3" | grep -q '"s": "rejected"'; then
    assert_pass "deprecate-task marca rejected"
  else
    assert_fail "deprecate-task marca rejected" "$STATUS_T3"
  fi
else
  assert_fail "deprecate-task retorna exit 0" "rc=$CAPTURE_RC"
fi

# 5. plan_history tiene 4+ rows (created + 3 amends)
HIST=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM plan_history WHERE plan_id=? ORDER BY version" "$PLAN_ID")
HIST_N=$(echo "$HIST" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['n'])" 2>/dev/null || echo 0)
if [ "$HIST_N" -ge 3 ]; then
  assert_pass "plan_history tiene >=3 rows (=$HIST_N)"
else
  assert_fail "plan_history tiene >=3 rows" "=$HIST_N"
fi

# 6. TAREAS APROBADAS PRESERVADAS: task-1 sigue 'approved'
AFTER_OK=$(teamdb_exec_query "$DB" "SELECT status AS s FROM tasks WHERE plan_id=? AND slug='task-1'" "$PLAN_ID")
if echo "$AFTER_OK" | grep -q '"s": "approved"'; then
  assert_pass "task aprobada preservada tras amend"
else
  assert_fail "task aprobada preservada tras amend" "$AFTER_OK"
fi

# 7. Version monotonamente creciente
MAX_VER=$(teamdb_exec_query "$DB" "SELECT MAX(version) AS v FROM plan_history WHERE plan_id=?" "$PLAN_ID")
MAX_N=$(echo "$MAX_VER" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['v'])" 2>/dev/null || echo 0)
if [ "$MAX_N" -ge 3 ]; then
  assert_pass "max(version) >= 3 (=$MAX_N)"
else
  assert_fail "max(version) >= 3" "=$MAX_N"
fi

# 8. Intentar modificar task aprobada debe fallar
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' --modify-task=task-1 --new-title='Attempt' --by teo '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  if echo "$CAPTURE_OUT" | grep -qE "approved|immutable"; then
    assert_pass "modify task aprobada rechazado (exit!=0 + mensaje)"
  else
    assert_fail "modify task aprobada rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
  fi
else
  assert_fail "modify task aprobada rechazado" "rc=0 (permitió modificar)"
fi

# 9. --force-advance fue eliminado (Issue 7: amendments atómicos, sin override)
T1_TITLE_BEFORE=$(teamdb_exec_value "$DB" "SELECT title FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND slug='task-1'")
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' --modify-task=task-1 --new-title='Force updated' --by teo --force-advance '$TEST_DIR'"
T1_TITLE_AFTER=$(teamdb_exec_value "$DB" "SELECT title FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-jwt') AND slug='task-1'")
if [ "$CAPTURE_RC" != "0" ] && [ "$T1_TITLE_AFTER" = "$T1_TITLE_BEFORE" ]; then
  assert_pass "--force-advance rechazado y task intacta"
else
  assert_fail "--force-advance rechazado y task intacta" "rc=$CAPTURE_RC out=$CAPTURE_OUT before=$T1_TITLE_BEFORE after=$T1_TITLE_AFTER"
fi

# 10. --show muestra el historial
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' --show '$TEST_DIR'"
if echo "$CAPTURE_OUT" | grep -qE "v[0-9]+.*add|modify|deprecate"; then
  assert_pass "--show muestra el historial"
else
  assert_fail "--show muestra el historial" "out=$CAPTURE_OUT"
fi

# 11. Plan inexistente falla
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'no-existe' --add-task='X' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "plan inexistente rechazado"
else
  assert_fail "plan inexistente rechazado" "rc=0"
fi

# 12. Operacion sin args falla
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "sin operacion falla"
else
  assert_fail "sin operacion falla" "rc=0"
fi

# 13. --by registra el actor correcto en plan_history
ACTOR_HIST=$(teamdb_exec_query "$DB" "SELECT changed_by AS c FROM plan_history WHERE plan_id=? AND changed_by='sol' LIMIT 1" "$PLAN_ID")
if echo "$ACTOR_HIST" | grep -q '"c": "sol"'; then
  assert_pass "plan_history registra changed_by"
else
  assert_fail "plan_history registra changed_by" "$ACTOR_HIST"
fi

# 14. snapshot_before no es NULL
SNAP_OK=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM plan_history WHERE plan_id=? AND snapshot_before IS NOT NULL" "$PLAN_ID")
SNAP_N=$(echo "$SNAP_OK" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['n'])" 2>/dev/null || echo 0)
if [ "$SNAP_N" -ge 3 ]; then
  assert_pass "snapshot_before presente en >=3 amendments (=$SNAP_N)"
else
  assert_fail "snapshot_before presente en >=3 amendments" "=$SNAP_N"
fi

# 15. shellcheck teamdb-amend.sh
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-amend.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-amend.sh shellcheck 0 errores"
else
  assert_fail "teamdb-amend.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

# 16. M1+M2 (Luz): audit amend con actor_source='helper' y agent = actor real
BAD_AMEND=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM audit_log WHERE action='amend' AND (COALESCE(actor_source,'') != 'helper' OR agent NOT IN ('sol','teo'))" 2>/dev/null)
AMEND_N=$(echo "$BAD_AMEND" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['n'])" 2>/dev/null || echo 'ERR')
if [ "$AMEND_N" = "0" ]; then
  assert_pass "audit amend con actor_source='helper' y agent=actor real"
else
  assert_fail "audit amend con actor_source='helper' y agent=actor real" "rows malas: $AMEND_N"
fi

# 17. M3 (Luz): título con pipe no debe romper el parseo de params
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'auth-jwt' --add-task='fix|bug|urgente' --by sol '$TEST_DIR'"
PIPE_SLUG="fix-bug-urgente"
FOUND_PIPE=$(teamdb_exec_query "$DB" "SELECT COUNT(*) AS n FROM tasks WHERE plan_id=? AND slug=?" "$PLAN_ID" "$PIPE_SLUG" 2>/dev/null)
PIPE_N=$(echo "$FOUND_PIPE" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())[0]['n'])" 2>/dev/null || echo 0)
if [ "$PIPE_N" -ge 1 ]; then
  assert_pass "add-task con pipe en título funciona (M3)"
else
  assert_fail "add-task con pipe en título funciona (M3)" "out=$CAPTURE_OUT"
fi

rm -rf "$TEST_DIR" /tmp/amend-tasks.md
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
