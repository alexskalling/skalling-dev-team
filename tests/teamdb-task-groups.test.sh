#!/usr/bin/env bash
# tests/teamdb-task-groups.test.sh — teamdb-task-groups.sh agrupa tasks
# pendientes en lotes seguros para paralelo usando SOLO task_dependencies
# real, nunca inferencia de archivos tocados (esa señal no existe en el
# schema). Regla a pedido explícito: cualquier vínculo, no solo "blocks",
# fuerza secuencia entre dos tasks que ya están listas para arrancar.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

FIXTURE="$(mktemp -d)"
trap '[ -n "$FIXTURE" ] && [ -d "$FIXTURE" ] && rm -rf -- "$FIXTURE"' EXIT
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$FIXTURE" >/dev/null 2>&1
DB="$FIXTURE/.opencode/context/team.db"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

sqlite3 "$DB" "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES('p','P','#i','approved','pol','$NOW','$NOW')"  # lens:ok: NOW viene de date -u, formato fijo, nunca input externo
sqlite3 "$DB" "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES('plan-1','Plan 1',1,'#d','in_progress','sol','$NOW','$NOW')"  # lens:ok: mismo NOW de arriba
sqlite3 "$DB" "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,created_at,updated_at) VALUES
  (1,'done-task','Done','resolved',2,0,'$NOW','$NOW'),
  (1,'free-after-done','Free after done','pending',2,1,'$NOW','$NOW'),
  (1,'task-a','Task A','pending',2,2,'$NOW','$NOW'),
  (1,'task-b','Task B','pending',2,3,'$NOW','$NOW'),
  (1,'task-c','Task C','pending',2,4,'$NOW','$NOW'),
  (1,'task-d','Task D','pending',2,5,'$NOW','$NOW'),
  (1,'task-e','Task E','pending',2,6,'$NOW','$NOW')"
sqlite3 "$DB" "INSERT INTO task_dependencies(task_id,depends_on_task_id,type,created_at) VALUES
  (2,1,'blocks','$NOW'),
  (5,3,'blocks','$NOW'),
  (4,6,'relates_to','$NOW')"

OUT="$(bash "$ROOT/scripts/teamdb-task-groups.sh" "$FIXTURE" "plan-1")"

get() { python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)$1))" <<< "$OUT"; }

if [ "$(get "['not_ready'][0]['slug']" 2>/dev/null)" = '"task-c"' ] && \
   [ "$(python3 -c "import json,sys; print(len(json.load(sys.stdin)['not_ready']))" <<< "$OUT")" = "1" ]; then
  assert_pass "solo la task con dependencia 'blocks' sin resolver queda not_ready"
else
  assert_fail "solo la task con dependencia 'blocks' sin resolver queda not_ready" "out=$OUT"
fi

GROUPS_OK="$(OUT_JSON="$OUT" python3 <<'PY'
import json, os
d = json.loads(os.environ["OUT_JSON"])
slugs = {tuple(sorted(g)) for g in d["parallel_groups"]}
expected = {("free-after-done",), ("task-a",), ("task-b", "task-d"), ("task-e",)}
print(slugs == expected)
PY
)"
if [ "$GROUPS_OK" = "True" ]; then
  assert_pass "una dependencia ya resuelta no bloquea, y relates_to fuerza secuencia entre listas"
else
  assert_fail "grupos paralelos calculados correctamente" "out=$OUT"
fi

# El plan no existe -> error explícito, no un resultado vacío que parezca "todo ok".
OUT_MISSING="$(bash "$ROOT/scripts/teamdb-task-groups.sh" "$FIXTURE" "plan-inexistente" 2>&1 || true)"
if grep -q "error" <<< "$OUT_MISSING"; then
  assert_pass "plan inexistente devuelve error explícito"
else
  assert_fail "plan inexistente devuelve error explícito" "out=$OUT_MISSING"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$ROOT/scripts/teamdb-task-groups.sh" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "teamdb-task-groups.sh shellcheck 0 errores"
  else
    assert_fail "teamdb-task-groups.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
