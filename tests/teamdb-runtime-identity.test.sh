#!/usr/bin/env bash
# tests/teamdb-runtime-identity.test.sh — la identidad de quien reclama,
# libera, aprueba o sella la pone el runtime de OpenCode
# (SKALLING_RUNTIME_AGENT, que inyecta el plugin), no un --by/--actor que el
# propio agente escribe. Sin esto, Teo podía aprobar su propio trabajo con
# `teamdb-claim.sh --advance ... --by=jhon`.
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

SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/lib-teamdb.sh"
DB="$TEST_DIR/.opencode/context/team.db"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES('p','Plan','# I','approved','pol',?,?)" "$NOW" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES('p','Plan',(SELECT id FROM proposals WHERE slug='p'),'# D','in_progress','sol',?,?)" "$NOW" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES((SELECT id FROM plans WHERE slug='p'),'t','Task','pending',2,1,'teo',?,?)" "$NOW" "$NOW" >/dev/null

# 1. Claim con --actor falso bajo runtime: rechazado, sin claim creado.
set +e
SKALLING_RUNTIME_AGENT=teo bash "$ROOT/scripts/teamdb-claim.sh" p t --actor=jhon --input-hash=h "$TEST_DIR" >/dev/null 2>&1
RC=$?
set -e
CLAIMS="$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_claims")"
if [ "$RC" -eq 2 ] && [ "$CLAIMS" = "0" ]; then
  assert_pass "claim con --actor distinto del runtime se rechaza"
else
  assert_fail "claim con --actor distinto del runtime se rechaza" "rc=$RC claims=$CLAIMS"
fi

# 2. Claim sin --actor bajo runtime: el actor es el agente real.
SKALLING_RUNTIME_AGENT=Teo bash "$ROOT/scripts/teamdb-claim.sh" p t --input-hash=h "$TEST_DIR" >/dev/null
ACTOR="$(teamdb_exec_value "$DB" "SELECT actor FROM task_claims WHERE status='active'")"
if [ "$ACTOR" = "teo" ]; then
  assert_pass "claim toma el actor del runtime"
else
  assert_fail "claim toma el actor del runtime" "actor=$ACTOR"
fi
CLAIM_ID="$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE status='active'")"

# 3. Release con --by falso: rechazado, el claim sigue activo.
set +e
SKALLING_RUNTIME_AGENT=jhon bash "$ROOT/scripts/teamdb-claim.sh" --release "$CLAIM_ID" --status=done --by=teo "$TEST_DIR" >/dev/null 2>&1
RC=$?
set -e
STATUS="$(teamdb_exec_value "$DB" "SELECT status FROM task_claims WHERE id=?" "$CLAIM_ID")"
if [ "$RC" -eq 2 ] && [ "$STATUS" = "active" ]; then
  assert_pass "release con --by distinto del runtime se rechaza"
else
  assert_fail "release con --by distinto del runtime se rechaza" "rc=$RC status=$STATUS"
fi

SKALLING_RUNTIME_AGENT=teo bash "$ROOT/scripts/teamdb-claim.sh" --release "$CLAIM_ID" --status=done "$TEST_DIR" >/dev/null
TASK_STATUS="$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE slug='t'")"
if [ "$TASK_STATUS" = "in_review" ]; then
  assert_pass "release del agente real deja la task en in_review"
else
  assert_fail "release del agente real deja la task en in_review" "status=$TASK_STATUS"
fi

# 4. El caso de la auditoría: Teo intenta aprobar como jhon.
set +e
OUT="$(SKALLING_RUNTIME_AGENT=teo bash "$ROOT/scripts/teamdb-claim.sh" --advance p t --to=approved --by=jhon "$TEST_DIR" 2>&1)"
RC=$?
set -e
TASK_STATUS="$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE slug='t'")"
if [ "$RC" -eq 2 ] && [ "$TASK_STATUS" = "in_review" ] && grep -q "no coincide" <<< "$OUT"; then
  assert_pass "teo no puede aprobar como jhon"
else
  assert_fail "teo no puede aprobar como jhon" "rc=$RC status=$TASK_STATUS"
fi

# Sin --by, el advance se evalúa como teo, y teo no es quien aprueba.
set +e
SKALLING_RUNTIME_AGENT=teo bash "$ROOT/scripts/teamdb-claim.sh" --advance p t --to=approved "$TEST_DIR" >/dev/null 2>&1
RC=$?
set -e
TASK_STATUS="$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE slug='t'")"
if [ "$RC" -ne 0 ] && [ "$TASK_STATUS" = "in_review" ]; then
  assert_pass "advance sin --by usa el agente real (teo) y se rechaza"
else
  assert_fail "advance sin --by usa el agente real (teo) y se rechaza" "rc=$RC status=$TASK_STATUS"
fi

# 5. Sellar receipt a nombre de otro agente: rechazado; sin nombre, queda el real.
set +e
SKALLING_RUNTIME_AGENT=teo TEAMDB_CLAIM_TREE_HASH=abc bash "$ROOT/scripts/teamdb-seal-receipt.sh" review luz "$TEST_DIR" >/dev/null 2>&1
RC=$?
set -e
if [ "$RC" -eq 2 ]; then
  assert_pass "teo no puede sellar un receipt a nombre de luz"
else
  assert_fail "teo no puede sellar un receipt a nombre de luz" "rc=$RC"
fi

SKALLING_RUNTIME_AGENT=luz TEAMDB_CLAIM_TREE_HASH=abc bash "$ROOT/scripts/teamdb-seal-receipt.sh" review "" "$TEST_DIR" >/dev/null 2>&1 || true
AGENT="$(teamdb_exec_value "$DB" "SELECT agent FROM receipts WHERE tree_hash='abc' ORDER BY id DESC LIMIT 1")"
if [ "$AGENT" = "luz" ]; then
  assert_pass "receipt queda sellado a nombre del agente real"
else
  assert_fail "receipt queda sellado a nombre del agente real" "agent=$AGENT"
fi

# 6. Sin runtime (humano en la CLI, CI), vale lo declarado como siempre.
if [ "$(teamdb_runtime_actor jhon)" = "jhon" ] && [ "$(teamdb_runtime_actor '')" = "unknown" ]; then
  assert_pass "sin runtime se respeta el actor declarado"
else
  assert_fail "sin runtime se respeta el actor declarado"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
