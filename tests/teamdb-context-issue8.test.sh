#!/usr/bin/env bash
# tests/teamdb-context-issue8.test.sh — Issue 8: top-k, max-bytes, relevance, provenance, discovery
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

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
teamdb_exec_write "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
  "i8" "I8" "# I" "approved" "$NOW" "$NOW" >/dev/null
PID=$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "i8")
teamdb_exec_write "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'active','sol',?,?)" \
  "i8" "I8" "$PID" "# D" "$NOW" "$NOW" >/dev/null
PLAN_ID=$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "i8")
# Task con title/description con terminos reconocibles (para auto-discovery)
teamdb_exec_write "$DB" "INSERT INTO tasks(plan_id,slug,title,description_md,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,?,'pending',2,1,?,?,?)" \
  "$PLAN_ID" "task-1" "Integrar JWT en login" "El flujo de autenticacion usa JWT y rate limit" "teo" "$NOW" "$NOW" >/dev/null

# Memorias
teamdb_exec_write "$DB" "INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES(?,?,?,'concept',?)" \
  "jwt-auth" "JWT Auth" "JWT body extenso para la tarea de autenticacion" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES(?,?,?,'concept',?)" \
  "rate-limit" "Rate limit" "Limitador de requests" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES(?,?,?,'concept',?)" \
  "cache-redis" "Cache Redis" "Cache distribuida" "$NOW" >/dev/null
teamdb_exec_write "$DB" "INSERT INTO decisions(slug,title,body_md,status,decided_at,decided_by) VALUES(?,?,?,'accepted',?,?)" \
  "use-jwt" "Use JWT" "decision" "$NOW" "pol" >/dev/null

# ─── Case A: link setea provenance='linked' y for-task lo emite
echo "=== Issue 8: provenance ==="
bash "$ROOT/scripts/teamdb-context.sh" link "i8" "task-1" --concepts=jwt-auth "$TEST_DIR" >/dev/null 2>&1
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "i8" "task-1" "$TEST_DIR" 2>&1)
PROV=$(echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
c = [x for x in d['concepts'] if x['slug']=='jwt-auth']
print(c[0].get('provenance', '') if c else 'MISSING')
")
if [ "$PROV" = "linked" ]; then
  assert_pass "link → provenance=linked en cápsula"
else
  assert_fail "link → provenance=linked" "provenance=$PROV"
fi

# ─── Case B: auto-discovery por task title/description (bound params, sin link)
echo "=== Issue 8: auto-discovery ==="
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "i8" "task-1" --discover --top-k=5 "$TEST_DIR" 2>&1)
DISC=$(echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
disc = [x for x in d['concepts'] if x.get('provenance')=='discovered' and x['slug']=='rate-limit']
print('FOUND' if disc else 'NOT_FOUND')
")
if [ "$DISC" = "FOUND" ]; then
  assert_pass "discovery encuentra rate-limit (title match, sin link)"
else
  assert_fail "discovery encuentra rate-limit" "out=$CAPSULE"
fi
# Sin --discover, NO debe aparecer rate-limit (no linkeado)
CAPSULE2=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "i8" "task-1" "$TEST_DIR" 2>&1)
DISC2=$(echo "$CAPSULE2" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
disc = [x for x in d['concepts'] if x['slug']=='rate-limit']
print('FOUND' if disc else 'NOT_FOUND')
")
if [ "$DISC2" = "NOT_FOUND" ]; then
  assert_pass "sin --discover no incluye no-linkeados"
else
  assert_fail "sin --discover no incluye no-linkeados" "out=$CAPSULE2"
fi

# ─── Case C: top-k duro por categoría
echo "=== Issue 8: top-k ==="
bash "$ROOT/scripts/teamdb-context.sh" link "i8" "task-1" --concepts=cache-redis "$TEST_DIR" >/dev/null 2>&1
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "i8" "task-1" --top-k=1 "$TEST_DIR" 2>&1)
K_COUNT=$(echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(len(d['concepts']))
")
if [ "$K_COUNT" -le 1 ]; then
  assert_pass "top-k=1 limita concepts (got $K_COUNT)"
else
  assert_fail "top-k=1 limita concepts" "count=$K_COUNT"
fi

# ─── Case D: orden por relevance (relevance mayor primero)
echo "=== Issue 8: orden por relevance ==="
sqlite3 "$DB" "UPDATE task_context_capsules SET relevance=5 WHERE memory_table='concepts' AND memory_id=(SELECT id FROM concepts WHERE slug='jwt-auth')"
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "i8" "task-1" --top-k=5 "$TEST_DIR" 2>&1)
FIRST=$(echo "$CAPSULE" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d['concepts'][0]['slug'] if d['concepts'] else 'NONE')
")
if [ "$FIRST" = "jwt-auth" ]; then
  assert_pass "relevance mayor primero (jwt-auth)"
else
  assert_fail "relevance mayor primero" "first=$FIRST"
fi

# ─── Case E: max-bytes acotado
echo "=== Issue 8: max-bytes ==="
CAPSULE=$(bash "$ROOT/scripts/teamdb-context.sh" for-task "i8" "task-1" --max-bytes=120 "$TEST_DIR" 2>&1)
BYTES=$(echo "$CAPSULE" | wc -c | tr -d ' ')
if [ "$BYTES" -le 600 ]; then
  assert_pass "max-bytes acota salida (bytes=$BYTES <= 600)"
else
  assert_fail "max-bytes acota salida" "bytes=$BYTES"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
