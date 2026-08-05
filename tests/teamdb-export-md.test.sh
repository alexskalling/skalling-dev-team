#!/usr/bin/env bash
# tests/teamdb-export-md.test.sh — Validación export Markdown GENERATED (T-2.15)
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

# Setup: plan + proposal + 2 tasks + ADR
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "auth-jwt" "Auth feature" "# Auth intent" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "auth-jwt")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'active','sol',?,?)" \
  "auth-jwt" "Auth feature" "$PID" "# Design" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "auth-jwt")
for i in 1 2; do
  teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,?,?,?,?)" \
    "$PLAN_ID" "task-$i" "Task $i title" "$i" "teo" "$NOW" "$NOW" >/dev/null
done
teamdb_exec_write "$DB" "INSERT INTO design_notes(plan_id,slug,title,context_md,decision_md,status,created_at,updated_at,decided_at) VALUES(?,?,?,?,?,'accepted',?,?,?)" \
  "$PLAN_ID" "use-jwt" "Use JWT" "Need auth" "Use JWT" "$NOW" "$NOW" "$NOW" >/dev/null

# 1. Export genera los 3 archivos
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  for f in proposal.md design.md tasks.md; do
    if [ -f "$TEST_DIR/.opencode/changes/auth-jwt/$f" ]; then
      assert_pass "genera $f"
    else
      assert_fail "genera $f" "no existe"
    fi
  done
else
  assert_fail "export retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 2. Cada archivo tiene header GENERATED
for f in proposal.md design.md tasks.md; do
  if head -3 "$TEST_DIR/.opencode/changes/auth-jwt/$f" | grep -q "GENERATED"; then
    assert_pass "$f tiene header GENERATED"
  else
    assert_fail "$f tiene header GENERATED"
  fi
done

# 3. Footer con instruccion de regenerar
for f in proposal.md design.md tasks.md; do
  if tail -3 "$TEST_DIR/.opencode/changes/auth-jwt/$f" | grep -qiE "regenerar|regenerate|footer"; then
    assert_pass "$f tiene footer de regenerar"
  else
    assert_fail "$f tiene footer de regenerar" "tail: $(tail -3 "$TEST_DIR/.opencode/changes/auth-jwt/$f")"
  fi
done

# 4. tasks.md tiene tabla con tasks
if grep -qE "task-1|task-2" "$TEST_DIR/.opencode/changes/auth-jwt/tasks.md"; then
  assert_pass "tasks.md contiene tasks"
else
  assert_fail "tasks.md contiene tasks" "no match"
fi

# 5. design.md contiene ADRs
if grep -qE "Use JWT|use-jwt" "$TEST_DIR/.opencode/changes/auth-jwt/design.md"; then
  assert_pass "design.md contiene design_notes (ADRs)"
else
  assert_fail "design.md contiene design_notes (ADRs)"
fi

# 6. proposal.md contiene proposal info
if grep -q "Auth feature" "$TEST_DIR/.opencode/changes/auth-jwt/proposal.md"; then
  assert_pass "proposal.md contiene proposal info"
else
  assert_fail "proposal.md contiene proposal info"
fi

# 7. --from-md rechazado
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' --from-md '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "no soportado|prohibido"; then
  assert_pass "--from-md rechazado"
else
  assert_fail "--from-md rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 8. --plan=slug filtra
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' --plan=auth-jwt '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ] && [ -f "$TEST_DIR/.opencode/changes/auth-jwt/tasks.md" ]; then
  assert_pass "--plan=slug filtra export"
else
  assert_fail "--plan=slug filtra export" "rc=$CAPTURE_RC"
fi

# 9. plan inexistente
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' --plan=no-existe '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "plan inexistente rechazado"
else
  assert_fail "plan inexistente rechazado" "rc=0"
fi

# 10. DB inexistente
TEST_DIR2="$(mktemp -d)"
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' '$TEST_DIR2'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "DB inexistente rechazado"
else
  assert_fail "DB inexistente rechazado" "rc=0"
fi
rm -rf "$TEST_DIR2"

# 11. Export es IDEMPOTENTE: 2 corridas no rompen
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' '$TEST_DIR'"
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' '$TEST_DIR'"
if [ -f "$TEST_DIR/.opencode/changes/auth-jwt/tasks.md" ]; then
  assert_pass "export idempotente"
else
  assert_fail "export idempotente" "no se regeneró"
fi

# 12. SINCRONIA: el archivo exportado refleja el estado actual de la DB
# Cambio una task title y re-exporto
teamdb_exec_write "$DB" "UPDATE tasks SET title='MODIFIED task 1' WHERE plan_id=? AND slug='task-1'" "$PLAN_ID" >/dev/null
run_capture "bash '$ROOT/scripts/teamdb-export-md.sh' '$TEST_DIR'"
if grep -q "MODIFIED task 1" "$TEST_DIR/.opencode/changes/auth-jwt/tasks.md"; then
  assert_pass "export refleja estado actual de DB (sincronia)"
else
  assert_fail "export refleja estado actual de DB (sincronia)"
fi

# 13. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-export-md.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-export-md.sh shellcheck 0 errores"
else
  assert_fail "teamdb-export-md.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
