#!/usr/bin/env bash
# tests/teamdb-workflow-state-sync.test.sh — workflow_state (dashboard,
# /skalling-resume, merge-helper.sh) tenia lectores desde 2026-08-17 pero
# ningun escritor real (solo tests con INSERT manual). teamdb-claim.sh ahora
# la sincroniza en claim/release/advance via teamdb_workflow_state.py.
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
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "sync-test" "Sync test" "# I" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "sync-test")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'in_progress','sol',?,?)" \
  "sync-test" "Sync test" "$PID" "# D" "$NOW" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES((SELECT id FROM plans WHERE slug='sync-test'),?,?,'pending',2,1,'teo',?,?)" \
  "task-1" "Task 1" "$NOW" "$NOW" >/dev/null

state() { teamdb_exec_value "$DB" "SELECT phase||' '||COALESCE(actor,'-')||' '||active_cycle_slug FROM workflow_state WHERE id=1"; }

# 0. Antes de tocar nada, la fila puede no existir o estar vacia.
if [ -z "$(state)" ]; then
  assert_pass "workflow_state arranca vacio (sin escritor todavia)"
else
  assert_fail "workflow_state arranca vacio" "ya tenia datos: $(state)"
fi

# 1. claim -> build / teo
TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" sync-test task-1 --actor=teo --input-hash=h1 --ttl=300 "$TEST_DIR" >/dev/null
if [ "$(state)" = "build teo sync-test" ]; then
  assert_pass "claim sincroniza workflow_state (build/teo)"
else
  assert_fail "claim sincroniza workflow_state" "got: $(state)"
fi

# 2. release done -> review (actor queda en quien libero, teo)
CLAIM_ID=$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE actor='teo' AND status='active'")
TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" --release "$CLAIM_ID" --status=done --by=teo "$TEST_DIR" >/dev/null
if [ "$(state)" = "review teo sync-test" ]; then
  assert_pass "release done sincroniza workflow_state (review)"
else
  assert_fail "release done sincroniza workflow_state" "got: $(state)"
fi

# 3. advance approved (jhon, con receipt sellado sobre el diff real) -> verificación / jhon
echo "value = 1" > "$TEST_DIR/app.py"
git -C "$TEST_DIR" add -- app.py
TASK_ID=$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE slug='task-1'")
DIFF_TEXT="$(git -C "$TEST_DIR" diff --cached -- . ':(exclude)db/teamdb/team.dump.sql')"
TREE_HASH="$(printf '%s' "$DIFF_TEXT" | shasum -a 256 | cut -c1-16)"
teamdb_exec_write "$DB" "INSERT INTO receipts(id,task_id,agent,command,exit_code,output_summary,ts,tree_hash) VALUES(?,?,?,'check',0,'ok',datetime('now'),?)" \
  "rcpt-sync-test" "$TASK_ID" "jhon" "$TREE_HASH" >/dev/null
TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" --advance sync-test task-1 --to=approved --by=jhon "$TEST_DIR" >/dev/null
if [ "$(state)" = "verificación jhon sync-test" ]; then
  assert_pass "advance approved sincroniza workflow_state (verificación/jhon)"
else
  assert_fail "advance approved sincroniza workflow_state" "got: $(state)"
fi

# 4. advance resolved (pau) -> entrega / pau
TEAMDB_ACTOR=pau bash "$ROOT/scripts/teamdb-claim.sh" --advance sync-test task-1 --to=resolved --by=pau "$TEST_DIR" >/dev/null
if [ "$(state)" = "entrega pau sync-test" ]; then
  assert_pass "advance resolved sincroniza workflow_state (entrega/pau)"
else
  assert_fail "advance resolved sincroniza workflow_state" "got: $(state)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
