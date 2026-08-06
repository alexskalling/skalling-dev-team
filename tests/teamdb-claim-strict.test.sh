#!/usr/bin/env bash
# tests/teamdb-claim-strict.test.sh — Issues 1, 2, 3, 4, 5, 7
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

setup_plan() {
  local test_dir="$1"
  local plan_slug="$2"
  local db="$test_dir/.opencode/context/team.db"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  teamdb_exec_write "$db" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'pol',?,?)" \
    "$plan_slug" "Plan" "# I" "approved" "$now" "$now" >/dev/null
  local pid
  pid=$(teamdb_exec_value "$db" "SELECT id FROM proposals WHERE slug=?" "$plan_slug")
  teamdb_exec_write "$db" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'in_progress','sol',?,?)" \
    "$plan_slug" "Plan" "$pid" "# D" "$now" "$now" >/dev/null
  local plan_id
  plan_id=$(teamdb_exec_value "$db" "SELECT id FROM plans WHERE slug=?" "$plan_slug")
  teamdb_exec_write "$db" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,1,?,?,?)" \
    "$plan_id" "task-1" "T1" "teo" "$now" "$now" >/dev/null
  teamdb_exec_write "$db" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,2,?,?,?)" \
    "$plan_id" "task-2" "T2" "teo" "$now" "$now" >/dev/null
  teamdb_exec_write "$db" "INSERT INTO task_dependencies(task_id, depends_on_task_id, type, created_at) SELECT (SELECT id FROM tasks WHERE plan_id=? AND slug='task-2'), (SELECT id FROM tasks WHERE plan_id=? AND slug='task-1'), 'blocks', ?" \
    "$plan_id" "$plan_id" "$now" >/dev/null
  echo "$plan_id"
}

TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"

# ─── Issue 1: claim rechaza tareas en estados terminales
echo "=== Issue 1: claim rechaza estados terminales ==="
PLAN_ID=$(setup_plan "$TEST_DIR" "issue1")
for STATE in approved resolved rejected blocked; do
  teamdb_exec_write "$DB" "UPDATE tasks SET status=? WHERE plan_id=? AND slug='task-1'" "$STATE" "$PLAN_ID" >/dev/null
  run_capture() {
    local _CAP_RC=0
    _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
    CAPTURE_RC="$_CAP_RC"
    CAPTURE_OUT="$_CAP_OUT"
  }
  run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'issue1' 'task-1' --input-hash=h --ttl=300 '$TEST_DIR'"
  if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "status.*$STATE|terminal|inmutable|not.*allowed"; then
    assert_pass "claim rechazado en status=$STATE"
  else
    assert_fail "claim rechazado en status=$STATE" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
  fi
  # Revertir a pending para no contaminar siguientes tests
  teamdb_exec_write "$DB" "UPDATE tasks SET status='pending' WHERE plan_id=? AND slug='task-1'" "$PLAN_ID" >/dev/null
done

# ─── Issue 2: claim verifica deps blocks dentro de BEGIN IMMEDIATE
echo "=== Issue 2: claim verifica deps blocks ==="
PLAN_ID=$(setup_plan "$TEST_DIR" "issue2")
# task-2 depende de task-1 (pendiente). Claim directo de task-2 debe fallar
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'issue2' 'task-2' --input-hash=h --ttl=300 '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "deps|blocked|dependencies"; then
  assert_pass "claim directo de task-2 (con dep pendiente) rechazado"
else
  assert_fail "claim directo de task-2 (con dep pendiente) rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Sin embargo, runnable via teamdb-deps.sh sigue mostrando solo task-1
RUNNABLE=$(bash "$ROOT/scripts/teamdb-deps.sh" runnable "issue2" "$TEST_DIR" 2>&1)
RUNNABLE_TASKS=$(echo "$RUNNABLE" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    slugs = [r.get('slug', '') for r in rows if isinstance(r, dict) and 'slug' in r]
    print(','.join(slugs))
except Exception as e:
    print('PARSE_ERROR:' + str(e))
")
if echo "$RUNNABLE_TASKS" | grep -q "task-1" && ! echo "$RUNNABLE_TASKS" | grep -q "task-2"; then
  assert_pass "runnable excluye task con deps pendientes (task-1 si, task-2 no)"
else
  assert_fail "runnable excluye task con deps pendientes" "runnable=$RUNNABLE_TASKS"
fi

# ─── Issue 3: input hash determinista
echo "=== Issue 3: input hash determinista ==="
# Sin --input-hash, el default debe ser el mismo para mismo (plan, task, actor, context)
H1=$(TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" "issue2" "task-1" --ttl=300 "$TEST_DIR" 2>&1 || true)
sleep 1  # para que NOW sea distinto si depende de tiempo
H2=$(TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" "issue2" "task-1" --ttl=300 "$TEST_DIR" 2>&1 || true)
# Extraer el default hash usado en el audit log
# Para esto, validamos que el --resume encuentra exactamente 1 claim activo
RESUME=$(TEAMDB_ACTOR=teo bash "$ROOT/scripts/teamdb-claim.sh" --resume "$TEST_DIR" 2>&1)
RESUME_COUNT=$(echo "$RESUME" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    print(len([r for r in rows if r.get('task_slug') == 'task-1']))
except Exception:
    print(-1)
")
if [ "$RESUME_COUNT" = "1" ]; then
  assert_pass "mismo (plan,task,actor) → 1 solo claim activo (idempotente sin PID)"
else
  assert_fail "mismo (plan,task,actor) → 1 solo claim activo" "resume_count=$RESUME_COUNT h1=$H1 h2=$H2"
fi

# ─── Issue 4: lease comparación correcta con epoch (plan aislado)
echo "=== Issue 4: lease comparación fechas ==="
PLAN_ID=$(setup_plan "$TEST_DIR" "issue4")
# Claim con lease corto (5 segundos)
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'issue4' 'task-1' --input-hash=lease-test --ttl=5 '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  # Esperar a que el lease expire
  sleep 7
  # Re-claim debe ser posible (lease vencido)
  run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'issue4' 'task-1' --input-hash=lease-test --ttl=300 '$TEST_DIR'"
  if [ "$CAPTURE_RC" = "0" ]; then
    # El nuevo claim debe tener attempt > 1
    ATTEMPT=$(teamdb_exec_value "$DB" "SELECT attempt FROM task_claims WHERE task_id=(SELECT id FROM tasks WHERE plan_id=? AND slug='task-1') AND status='active'" "$PLAN_ID")
    if [ "$ATTEMPT" -ge 2 ]; then
      assert_pass "lease vencido permite re-claim (attempt=$ATTEMPT)"
    else
      assert_fail "lease vencido permite re-claim" "attempt=$ATTEMPT"
    fi
  else
    assert_fail "re-claim tras lease vencido" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
  fi
else
  assert_fail "claim inicial con lease corto" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Verificar que el formato de lease_until es numerico (epoch, no ISO con T/Z)
LEASE_TYPE=$(sqlite3 "$DB" "SELECT typeof(lease_until) FROM task_claims WHERE status='active' LIMIT 1")
if [ "$LEASE_TYPE" = "integer" ] || [ "$LEASE_TYPE" = "real" ]; then
  assert_pass "lease_until es numerico (epoch o julianday) — typeof=$LEASE_TYPE"
else
  assert_fail "lease_until es numerico (epoch o julianday)" "typeof=$LEASE_TYPE"
fi

# ─── Issue 5: release con state transitions whitelist (planes aislados)
echo "=== Issue 5: release state transitions ==="
# Caso A: done → task in_review (no resolved)
PLAN_5A=$(setup_plan "$TEST_DIR" "issue5a")
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'issue5a' 'task-1' --input-hash=release-test --ttl=300 '$TEST_DIR'"
CLAIM_ID=$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE input_hash='release-test' AND status='active' LIMIT 1")
[ -n "$CLAIM_ID" ] || { echo "FAIL: setup claim no creó"; exit 1; }

# Release done: task debe ir a in_review (no a resolved)
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' --release '$CLAIM_ID' --status=done --by=teo '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  TASK_STATUS=$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE id=(SELECT task_id FROM task_claims WHERE id=?)" "$CLAIM_ID")
  if [ "$TASK_STATUS" = "in_review" ]; then
    assert_pass "release done → task=in_review (no resolved)"
  else
    assert_fail "release done → task=in_review" "status=$TASK_STATUS"
  fi
else
  assert_fail "release done retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Claim inexistente rechazado
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' --release 99999 --status=done '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "no.*existe|not.*found"; then
  assert_pass "release claim inexistente rechazado"
else
  assert_fail "release claim inexistente rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Release por actor incorrecto (no el owner) — plan propio
setup_plan "$TEST_DIR" "issue5c" >/dev/null
run_capture "TEAMDB_ACTOR=alex bash '$ROOT/scripts/teamdb-claim.sh' 'issue5c' 'task-1' --input-hash=other-actor --ttl=300 '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  # alex es owner del nuevo claim. Intentar release con jhon debe fallar
  ALICE_CLAIM=$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE input_hash='other-actor' AND actor='alex' AND status='active' LIMIT 1")
  if [ -n "$ALICE_CLAIM" ]; then
    run_capture "TEAMDB_ACTOR=jhon bash '$ROOT/scripts/teamdb-claim.sh' --release '$ALICE_CLAIM' --status=done '$TEST_DIR'"
    if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "owner|not.*owner|wrong.*actor"; then
      assert_pass "release por actor incorrecto rechazado"
    else
      assert_fail "release por actor incorrecto rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
    fi
  else
    assert_fail "setup: alex claim no creado"
  fi
else
  assert_fail "setup: claim por alex falló" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Release de claim ya released (status=done) rechazado — reuse CLAIM_ID del caso A
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' --release '$CLAIM_ID' --status=done --by=teo '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "status|not.*active|already"; then
  assert_pass "release de claim ya released rechazado"
else
  assert_fail "release de claim ya released rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Status no permitido (e.g., 'unknown') — plan propio
setup_plan "$TEST_DIR" "issue5e" >/dev/null
run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' 'issue5e' 'task-1' --input-hash=val-stat --ttl=300 '$TEST_DIR'"
TASK_CLAIM=$(teamdb_exec_value "$DB" "SELECT id FROM task_claims WHERE input_hash='val-stat' AND status='active' LIMIT 1")
if [ -n "$TASK_CLAIM" ]; then
  run_capture "TEAMDB_ACTOR=teo bash '$ROOT/scripts/teamdb-claim.sh' --release '$TASK_CLAIM' --status=unknown --by=teo '$TEST_DIR'"
  if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "status.*invalid|invalid.*status"; then
    assert_pass "release con status inválido rechazado"
  else
    assert_fail "release con status inválido rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
  fi
else
  assert_fail "setup: claim para test status inválido" "no claim activo con val-stat"
fi

# ─── Issue 7: amend atómico + sin --force-advance
echo "=== Issue 7: amend atómico sin --force-advance ==="
run_capture() {
  local _CAP_RC=0
  _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
  CAPTURE_RC="$_CAP_RC"
  CAPTURE_OUT="$_CAP_OUT"
}

# --force-advance NO debe existir
if bash "$ROOT/scripts/teamdb-amend.sh" --help 2>&1 | grep -qE "force-advance"; then
  assert_fail "--force-advance no debe existir en help" "todavia aparece"
else
  assert_pass "--force-advance no existe en help (eliminado)"
fi

# Verificar que amend --modify de una task approved falla
PLAN_ID=$(setup_plan "$TEST_DIR" "issue7")
teamdb_exec_write "$DB" "UPDATE tasks SET status='approved' WHERE plan_id=? AND slug='task-1'" "$PLAN_ID" >/dev/null
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'issue7' --modify-task=task-1 --new-title='X' --by teo '$TEST_DIR'"
if [ "$CAPTURE_RC" != "0" ] && echo "$CAPTURE_OUT" | grep -qE "immutable|approved"; then
  assert_pass "amend --modify de task approved rechazado (sin --force-advance)"
else
  assert_fail "amend --modify de task approved rechazado" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Amend --modify de pending OK
run_capture "bash '$ROOT/scripts/teamdb-amend.sh' 'issue7' --modify-task=task-2 --new-title='Modified' --by teo '$TEST_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  assert_pass "amend --modify de task pending OK"
else
  assert_fail "amend --modify de task pending" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Atomicidad: amend debe usar multi-statement (BEGIN IMMEDIATE)
# Esto se valida porque el plan_history debe tener el row, no quedar inconsistente
HIST_AFTER_AMEND=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='issue7')")
if [ "$HIST_AFTER_AMEND" -ge 1 ]; then
  assert_pass "amend atómico: plan_history tiene row (=$HIST_AFTER_AMEND)"
else
  assert_fail "amend atómico: plan_history sin row" "count=$HIST_AFTER_AMEND"
fi

# ─── Limpiar
rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
