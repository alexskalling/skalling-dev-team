#!/usr/bin/env bash
# La aprobación debe venir de un actor distinto al que entregó la implementación.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
TEST_DIR="$(mktemp -d)"
trap '[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/.opencode/context"

SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null
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

create_task "self-review" "jhon"
TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" self-review task --input-hash=self "$TEST_DIR" >/dev/null
SELF_CLAIM="$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE actor='jhon' AND status='active'")"
TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" --release "$SELF_CLAIM" --status=done --by=jhon "$TEST_DIR" >/dev/null
if TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" --advance self-review task --to=approved --by=jhon "$TEST_DIR" >/dev/null 2>&1; then
  echo "FAIL: Jhon pudo aprobar una implementación entregada por Jhon" >&2
  exit 1
fi

create_task "independent-review" "teo"
TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" independent-review task --input-hash=independent "$TEST_DIR" >/dev/null
TEO_CLAIM="$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE actor='teo' AND status='active'")"
TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" --release "$TEO_CLAIM" --status=done --by=teo "$TEST_DIR" >/dev/null
if TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" --advance independent-review task --to=approved --by=jhon "$TEST_DIR" >/dev/null 2>&1; then
  echo "FAIL: Jhon pudo aprobar sin receipt de verificación sellado" >&2
  exit 1
fi
TASK_ID="$(teamdb_exec_value "$DB" "SELECT t.id FROM tasks t JOIN plans p ON p.id=t.plan_id WHERE p.slug=? AND t.slug=?" independent-review task)"
teamdb_exec_write "$DB" "INSERT INTO receipts(id,task_id,agent,command,exit_code,output_summary,ts,tree_hash) VALUES(?,?,?,'independent-check',0,'ok',datetime('now'),'frozen-test')" "review-independent" "$TASK_ID" jhon >/dev/null
TEAMDB_ACTOR=jhon bash "$ROOT/scripts/teamdb-claim.sh" --advance independent-review task --to=approved --by=jhon "$TEST_DIR" >/dev/null

echo "PASS: la aprobación exige verificador distinto y receipt sellado de Jhon"
