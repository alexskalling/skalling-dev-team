#!/usr/bin/env bash
# tests/skalling-verify-gate.test.sh — jhon (test verifier) no puede sellar un
# receipt "aprobado" a partir de un exit code que el caller le pase de
# confianza: si el proyecto tiene testing.unit.command configurado en
# project.yaml, teamdb-seal-receipt.sh lo corre de verdad y usa SU exit code.
# Si el test real del proyecto falla, el receipt queda con exit_code != 0, y
# la transición in_review->approved (que exige un receipt exit_code=0 de
# jhon) se bloquea sola — sin depender de que nadie se acuerde de correr
# tsc/npm test/pytest a mano antes de aprobar.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TEST_DIR="$(mktemp -d)"
trap '[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/.opencode/context"
git -C "$TEST_DIR" init -q
git -C "$TEST_DIR" config user.email test@example.com
git -C "$TEST_DIR" config user.name Test

SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/lib-teamdb.sh"
DB="$TEST_DIR/.opencode/context/team.db"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

create_task() {
  local slug="$1" owner="$2"
  teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,'approved','pol',?,?)" "$slug" "Plan" "# Intent" "$NOW" "$NOW" >/dev/null
  local proposal_id
  proposal_id="$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "$slug")"
  teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'in_progress','sol',?,?)" "$slug" "Plan" "$proposal_id" "# Design" "$NOW" "$NOW" >/dev/null
  local plan_id
  plan_id="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "$slug")"
  teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,1,?,?,?)" "$plan_id" "task" "Task" "$owner" "$NOW" "$NOW" >/dev/null
}

setup_ready_for_review() {
  # Deja la task lista en in_review, implementada por "teo" (distinto de
  # jhon, que es quien va a intentar aprobar).
  local slug="$1"
  create_task "$slug" "teo"
  TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" "$slug" task --input-hash=impl "$TEST_DIR" >/dev/null
  local claim_id
  claim_id="$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE actor='teo' AND status='active'")"
  TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" --release "$claim_id" --status=done --by=teo "$TEST_DIR" >/dev/null
  teamdb_exec_value "$DB" "SELECT t.id FROM tasks t JOIN plans p ON p.id=t.plan_id WHERE p.slug=? AND t.slug=?" "$slug" task
}

write_project_yaml() {
  mkdir -p "$TEST_DIR/.opencode"
  cat > "$TEST_DIR/.opencode/project.yaml" <<EOF
testing:
  unit:
    available: true
    command: "$1"
EOF
}

stage_something() {
  echo "v$RANDOM" > "$TEST_DIR/app.txt"
  git -C "$TEST_DIR" add app.txt
}

# ── 1. testing.unit.command REAL y falla → seal registra exit_code != 0,
#      advance --to=approved queda bloqueado ──
TASK1="task-fails"
write_project_yaml "exit 1"
stage_something
TASK_ID1="$(setup_ready_for_review "$TASK1")"
bash "$ROOT/scripts/teamdb-seal-receipt.sh" "$TASK_ID1" jhon "$TEST_DIR" >/dev/null 2>&1
SEALED_EXIT="$(teamdb_exec_value "$DB" "SELECT exit_code FROM receipts WHERE task_id=? AND agent='jhon' ORDER BY id DESC LIMIT 1" "$TASK_ID1")"
if [ "$SEALED_EXIT" != "0" ]; then
  assert_pass "test real del proyecto falla → receipt de jhon queda con exit_code != 0"
else
  assert_fail "test real del proyecto falla → receipt de jhon queda con exit_code != 0" "exit_code=$SEALED_EXIT"
fi
if TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" --advance "$TASK1" task --to=approved --by=jhon "$TEST_DIR" >/dev/null 2>&1; then
  assert_fail "test real falla → in_review->approved se bloquea"
else
  assert_pass "test real falla → in_review->approved se bloquea"
fi

# Ni fabricando un TEAMDB_CLAIM_EXIT_CODE=0 se puede pasar por encima del
# resultado real: la corrida real de jhon manda, no lo que el caller pida.
TEAMDB_CLAIM_EXIT_CODE=0 bash "$ROOT/scripts/teamdb-seal-receipt.sh" "$TASK_ID1" jhon "$TEST_DIR" >/dev/null 2>&1
FORCED_EXIT="$(teamdb_exec_value "$DB" "SELECT exit_code FROM receipts WHERE task_id=? AND agent='jhon' ORDER BY id DESC LIMIT 1" "$TASK_ID1")"
if [ "$FORCED_EXIT" != "0" ]; then
  assert_pass "TEAMDB_CLAIM_EXIT_CODE=0 del caller no puede pisar el resultado real del test"
else
  assert_fail "TEAMDB_CLAIM_EXIT_CODE=0 del caller no puede pisar el resultado real del test"
fi

# ── 2. testing.unit.command REAL y pasa → approved sí procede ──
TASK2="task-passes"
write_project_yaml "exit 0"
stage_something
TASK_ID2="$(setup_ready_for_review "$TASK2")"
bash "$ROOT/scripts/teamdb-seal-receipt.sh" "$TASK_ID2" jhon "$TEST_DIR" >/dev/null 2>&1
if TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" --advance "$TASK2" task --to=approved --by=jhon "$TEST_DIR" >/dev/null 2>&1; then
  assert_pass "test real del proyecto pasa → in_review->approved procede"
else
  assert_fail "test real del proyecto pasa → in_review->approved procede"
fi

# ── 3. sin testing.unit.command configurado → seal no explota, pero el
#      output_summary lo deja anotado sin ambigüedad (no aparenta ser un test
#      que corrió y pasó) ──
TASK3="task-unconfigured"
rm -f "$TEST_DIR/.opencode/project.yaml"
stage_something
TASK_ID3="$(setup_ready_for_review "$TASK3")"
if bash "$ROOT/scripts/teamdb-seal-receipt.sh" "$TASK_ID3" jhon "$TEST_DIR" >/dev/null 2>&1; then
  SUMMARY3="$(teamdb_exec_value "$DB" "SELECT output_summary FROM receipts WHERE task_id=? AND agent='jhon' ORDER BY id DESC LIMIT 1" "$TASK_ID3")"
  if grep -q "SIN-CONFIGURAR" <<< "$SUMMARY3"; then
    assert_pass "sin testing.unit.command: seal no falla, pero el receipt queda anotado SIN-CONFIGURAR"
  else
    assert_fail "sin testing.unit.command: seal no falla, pero el receipt queda anotado SIN-CONFIGURAR" "summary=$SUMMARY3"
  fi
else
  assert_fail "sin testing.unit.command: seal no debería fallar (no hay para siempre un proyecto sin tests)"
fi

# ── 4. agente distinto de jhon (luz) no dispara ninguna corrida real; el
#      comportamiento previo (caller-trusted) sigue intacto para el resto ──
TASK4="task-luz"
write_project_yaml "exit 1"
stage_something
TASK_ID4="$(setup_ready_for_review "$TASK4")"
TEAMDB_CLAIM_EXIT_CODE=0 bash "$ROOT/scripts/teamdb-seal-receipt.sh" "$TASK_ID4" luz "$TEST_DIR" >/dev/null 2>&1
LUZ_EXIT="$(teamdb_exec_value "$DB" "SELECT exit_code FROM receipts WHERE task_id=? AND agent='luz' ORDER BY id DESC LIMIT 1" "$TASK_ID4")"
if [ "$LUZ_EXIT" = "0" ]; then
  assert_pass "agente != jhon: sin cambios de comportamiento, sigue siendo caller-trusted"
else
  assert_fail "agente != jhon: sin cambios de comportamiento, sigue siendo caller-trusted" "exit_code=$LUZ_EXIT"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$ROOT/scripts/skalling-verify.sh" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "skalling-verify.sh shellcheck 0 errores"
  else
    assert_fail "skalling-verify.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
