#!/usr/bin/env bash
# tests/teamdb-claim-lease.test.sh — Validación atomic claim + lease + resume (T-2.14)
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

# Setup plan + 2 tasks
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "claim-test" "Claim test" "# I" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "claim-test")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'active','sol',?,?)" \
  "claim-test" "Claim test" "$PID" "# D" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "claim-test")
for i in 1 2; do
  teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,?,?,?,?)" \
    "$PLAN_ID" "task-$i" "Task $i" "$i" "teo" "$NOW" "$NOW" >/dev/null
done

# 1. claim inicial retorna claim-id
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'claim-test' 'task-1' --actor=teo --input-hash=abc123 --ttl=300 '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ] && echo "$CAPTURE_OUT" | grep -qE '"claim_id": [0-9]+'; then
  CLAIM_ID=$(echo "$CAPTURE_OUT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['claim_id'])" 2>/dev/null)
  if [ -n "$CLAIM_ID" ]; then
    assert_pass "claim inicial retorna claim_id=$CLAIM_ID"
  else
    assert_fail "claim inicial retorna claim_id" "out=$CAPTURE_OUT"
  fi
else
  assert_fail "claim inicial retorna exit 0 + claim_id" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 2. task status=in_progress
STATUS=$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE plan_id=? AND slug='task-1'" "$PLAN_ID")
if [ "$STATUS" = "in_progress" ]; then
  assert_pass "task status=in_progress tras claim"
else
  assert_fail "task status=in_progress" "status=$STATUS"
fi

# 3. Idempotencia: re-claim con mismo (actor, input_hash) retorna MISMO claim_id
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'claim-test' 'task-1' --actor=teo --input-hash=abc123 --ttl=300 '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  CLAIM_ID_2=$(echo "$CAPTURE_OUT" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['claim_id'])" 2>/dev/null)
  if [ "$CLAIM_ID" = "$CLAIM_ID_2" ]; then
    assert_pass "idempotente: re-claim retorna mismo claim_id"
  else
    assert_fail "idempotente: re-claim retorna mismo claim_id" "$CLAIM_ID vs $CLAIM_ID_2"
  fi
else
  assert_fail "idempotente retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 4. Conflicto: distinto actor (mientras lease vigente)
run_capture "TEAMDB_ACTOR=jhon bash '$ROOT/scripts/teamdb-claim.sh' 'claim-test' 'task-1' --actor=jhon --input-hash=abc123 --ttl=300 '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "claimed by|lease until"; then
  assert_pass "conflicto: distinto actor rechazado"
else
  assert_fail "conflicto: distinto actor rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 5. Lease expiry: simular vencido (epoch) y permitir re-claim
EXPIRED_EPOCH=$(( $(date +%s) - 60 ))
teamdb_exec_write "$DB" "UPDATE task_claims SET lease_until=? WHERE id=?" "$EXPIRED_EPOCH" "$CLAIM_ID" >/dev/null
run_capture "TEAMDB_ACTOR=jhon bash '$ROOT/scripts/teamdb-claim.sh' 'claim-test' 'task-1' --actor=jhon --input-hash=def456 --ttl=300 '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ] && echo "$CAPTURE_OUT" | grep -qE '"claim_id": [0-9]+'; then
  assert_pass "lease-expired: re-claim con nuevo actor OK"
else
  assert_fail "lease-expired: re-claim con nuevo actor" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 6. Attempt se incrementa tras lease expiry
ATTEMPT=$(teamdb_exec_value "$DB" "SELECT MAX(attempt) FROM task_claims WHERE task_id=(SELECT id FROM tasks WHERE plan_id=? AND slug='task-1')" "$PLAN_ID")
if [ "$ATTEMPT" -ge 2 ]; then
  assert_pass "attempt se incrementa tras lease expiry (=$ATTEMPT)"
else
  assert_fail "attempt se incrementa tras lease expiry" "=$ATTEMPT"
fi

# 7. Resume encuentra el claim activo
bash "$ROOT/scripts/teamdb-claim.sh" "claim-test" "task-2" --actor=teo --input-hash=zzz --ttl=300 "$TEST_DIR" >/dev/null 2>&1
RESUME_OUT=$(TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" --resume --actor=teo "$TEST_DIR" 2>&1)
if echo "$RESUME_OUT" | grep -q "task-2"; then
  assert_pass "resume encuentra claims activos del actor"
else
  assert_fail "resume encuentra claims activos del actor" "out=$RESUME_OUT"
fi

# 8. Release marca claim como done (solo el owner del claim)
TASK1_ACTIVE=$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE task_id=(SELECT id FROM tasks WHERE plan_id=? AND slug='task-1') AND status='active'" "$PLAN_ID")
run_capture "TEAMDB_ACTOR=jhon bash '$ROOT/scripts/teamdb-claim.sh' --release '$TASK1_ACTIVE' --status=done --by=jhon '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  NEW_STATUS=$(teamdb_exec_value "$DB" "SELECT status FROM task_claims WHERE id=?" "$TASK1_ACTIVE")
  if [ "$NEW_STATUS" = "done" ]; then
    assert_pass "release marca claim como done"
  else
    assert_fail "release marca claim como done" "status=$NEW_STATUS"
  fi
else
  assert_fail "release retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 9. Release done → task in_review (no resolved)
TASK_STATUS=$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE plan_id=? AND slug='task-1'" "$PLAN_ID")
if [ "$TASK_STATUS" = "in_review" ]; then
  assert_pass "release done → task in_review"
else
  assert_fail "release done → task in_review" "status=$TASK_STATUS"
fi

# 9b. Advance: solo Jhon pasa in_review → approved
run_capture "TEAMDB_ACTOR=pau bash '$ROOT/scripts/teamdb-claim.sh' --advance 'claim-test' 'task-1' --to=approved --by=pau '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "advance approved: actor no-Jhon rechazado"
else
  assert_fail "advance approved: actor no-Jhon rechazado" "rc=0 out=$CAPTURE_OUT"
fi
run_capture "TEAMDB_ACTOR=jhon bash '$ROOT/scripts/teamdb-claim.sh' --advance 'claim-test' 'task-1' --to=approved '$TEST_DIR'"
APPROVED_STATUS=$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE plan_id=? AND slug='task-1'" "$PLAN_ID")
if [ "$CAPTURE_RC" = "0" ] && [ "$APPROVED_STATUS" = "approved" ]; then
  assert_pass "advance approved: Jhon in_review → approved"
else
  assert_fail "advance approved: Jhon in_review → approved" "rc=$CAPTURE_RC status=$APPROVED_STATUS out=$CAPTURE_OUT"
fi

# 9c. Advance: solo Pau pasa approved → resolved
run_capture "TEAMDB_ACTOR=jhon bash '$ROOT/scripts/teamdb-claim.sh' --advance 'claim-test' 'task-1' --to=resolved --by=jhon '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "advance resolved: actor no-Pau rechazado"
else
  assert_fail "advance resolved: actor no-Pau rechazado" "rc=0 out=$CAPTURE_OUT"
fi
run_capture "TEAMDB_ACTOR=pau bash '$ROOT/scripts/teamdb-claim.sh' --advance 'claim-test' 'task-1' --to=resolved '$TEST_DIR'"
RESOLVED_STATUS=$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE plan_id=? AND slug='task-1'" "$PLAN_ID")
if [ "$CAPTURE_RC" = "0" ] && [ "$RESOLVED_STATUS" = "resolved" ]; then
  assert_pass "advance resolved: Pau approved → resolved"
else
  assert_fail "advance resolved: Pau approved → resolved" "rc=$CAPTURE_RC status=$RESOLVED_STATUS out=$CAPTURE_OUT"
fi

# 10. claim de task en estado terminal (resolved) rechazado
run_capture "TEAMDB_ACTOR=pau bash '$ROOT/scripts/teamdb-claim.sh' 'claim-test' 'task-1' --actor=pau --input-hash=hhh --ttl=300 '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "terminal|immutable|resolved"; then
  assert_pass "claim de task resolved rechazado (terminal)"
else
  assert_fail "claim de task resolved rechazado (terminal)" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 11. plan/task inexistente rechazado
run_capture "bash '$ROOT/scripts/teamdb-claim.sh' 'no-existe' 'task-1' --actor=alex '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "plan inexistente rechazado"
else
  assert_fail "plan inexistente rechazado" "rc=0"
fi

run_capture "bash '$ROOT/scripts/teamdb-claim.sh' 'claim-test' 'no-existe' --actor=alex '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "task inexistente rechazado"
else
  assert_fail "task inexistente rechazado" "rc=0"
fi

# 12. --help y --resume sin actor
run_capture "bash '$ROOT/scripts/teamdb-claim.sh' --help"
if [ "$CAPTURE_RC" != "0" ] || echo "$CAPTURE_OUT" | grep -q "Uso"; then
  assert_pass "--help muestra uso"
else
  assert_fail "--help muestra uso" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 13. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-claim.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-claim.sh shellcheck 0 errores"
else
  assert_fail "teamdb-claim.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

# 14. M1 (Luz): audit de claim/release/advance lleva actor_source='helper'
BAD_AUDIT="$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE action IN ('claim','release','advance') AND COALESCE(actor_source,'') != 'helper'" 2>/dev/null || echo 'ERR')"
if [ "$BAD_AUDIT" = "0" ]; then
  assert_pass "audit claim/release/advance con actor_source='helper'"
else
  assert_fail "audit claim/release/advance con actor_source='helper'" "rows sin actor_source helper: $BAD_AUDIT"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
