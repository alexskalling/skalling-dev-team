#!/usr/bin/env bash
# tests/teamdb-claim-history.test.sh — Historial de attempts (Issue 6)
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

# 1. NO debe haber UNIQUE constraint en task_id (debe permitir multiples rows historicos)
HAS_UNIQUE=$(sqlite3 "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='task_claims' AND sql LIKE '%UNIQUE%' AND sql LIKE '%task_id%' AND sql NOT LIKE '%WHERE%'")
if [ "$HAS_UNIQUE" = "0" ]; then
  assert_pass "NO hay UNIQUE constraint global en task_claims.task_id"
else
  assert_fail "NO hay UNIQUE constraint global en task_claims.task_id" "found=$HAS_UNIQUE"
fi

# 2. Debe existir indice unico PARCIAL para status='active'
HAS_PARTIAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='task_claims' AND sql LIKE '%WHERE status%' AND sql LIKE '%active%'")
if [ "$HAS_PARTIAL" -ge 1 ]; then
  assert_pass "indice unico parcial WHERE status='active' existe"
else
  assert_fail "indice unico parcial WHERE status='active' existe" "count=$HAS_PARTIAL"
fi

# 3. Insertar 2 claims historicos (status='expired') con mismo task_id debe OK
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" "hist-test" "H" "# I" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "hist-test")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'in_progress','sol',?,?)" "hist-test" "H" "$PID" "# D" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "hist-test")
teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,1,?,?,?)" "$PLAN_ID" "task-1" "T1" "teo" "$NOW" "$NOW" >/dev/null
TASK_ID=$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE plan_id=? AND slug='task-1'" "$PLAN_ID")

# 2 claims con status distinto
teamdb_exec_write "$DB" "INSERT INTO task_claims(task_id,actor,attempt,input_hash,lease_until,status,claimed_at) VALUES(?,?,1,'h1',?,'expired',?)" "$TASK_ID" "alex" "2025-01-01 00:00:00" "2025-01-01 00:00:00" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO task_claims(task_id,actor,attempt,input_hash,lease_until,status,claimed_at) VALUES(?,?,2,'h2',?,'expired',?)" "$TASK_ID" "jhon" "2025-01-02 00:00:00" "2025-01-02 00:00:00" >/dev/null
HIST=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM task_claims WHERE task_id=?" "$TASK_ID")
if [ "$HIST" = "2" ]; then
  assert_pass "2 claims historicos (status distinto) coexisten"
else
  assert_fail "2 claims historicos (status distinto) coexisten" "count=$HIST"
fi

# 4. 2 claims con status='active' para mismo task_id debe FALLAR (UNIQUE parcial)
TEAMDB_ACTOR=teo teamdb_write_project "$DB" \
  "INSERT INTO task_claims(task_id,actor,attempt,input_hash,lease_until,status,claimed_at) VALUES(?,?,1,'h3',?,'active',?)" \
  "$TASK_ID" "teo" "2030-01-01 00:00:00" "2030-01-01 00:00:00" >/dev/null 2>&1
RC1=$?
TEAMDB_ACTOR=jhon teamdb_write_project "$DB" \
  "INSERT INTO task_claims(task_id,actor,attempt,input_hash,lease_until,status,claimed_at) VALUES(?,?,1,'h4',?,'active',?)" \
  "$TASK_ID" "jhon" "2030-01-01 00:00:00" "2030-01-01 00:00:00" >/dev/null 2>&1
RC2=$?
if [ "$RC1" = "0" ] && [ "$RC2" != "0" ]; then
  assert_pass "2 claims activos con mismo task_id: 2do falla (UNIQUE parcial)"
else
  assert_fail "2 claims activos con mismo task_id: 2do falla" "rc1=$RC1 rc2=$RC2"
fi

# 5. history muestra el orden cronologico
HIST_DETAIL=$(teamdb_exec_query "$DB" "SELECT actor, attempt, status FROM task_claims WHERE task_id=? ORDER BY attempt" "$TASK_ID")
echo "$HIST_DETAIL" | python3 -c "
import json, sys
rows = json.loads(sys.stdin.read())
actors = [r['actor'] for r in rows]
assert 'alex' in actors and 'jhon' in actors and 'teo' in actors, actors
print('OK')
" 2>/dev/null
if [ "$?" = "0" ]; then
  assert_pass "historial preserva multiples actores/attempts"
else
  assert_fail "historial preserva multiples actores/attempts" "$HIST_DETAIL"
fi

# 6. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/lib/lib-teamdb.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "lib-teamdb.sh shellcheck 0 errores"
else
  assert_fail "lib-teamdb.sh shellcheck 0 errores"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
