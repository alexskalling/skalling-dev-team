#!/usr/bin/env bash
# tests/skalling-route-supersede.test.sh — classify --record cierra en el
# codigo cualquier metrica reciente que haya quedado abierta, en vez de
# depender de que Alex se acuerde de cerrarla al reclasificar.
#
# Bug real (2026-09-13, proyecto Survan): 3 de 4 filas de workflow_metrics
# quedaron en 'pending' para siempre porque una reclasificacion abria un
# request_id nuevo sin cerrar el anterior, y nada mas que una instruccion en
# markdown le pedia a Alex hacerlo a mano.
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

query() { sqlite3 "$DB" "$1"; }

OUT1="$(bash "$ROOT/scripts/skalling-route.sh" classify --kind research --risk low \
  --record --intent "primera consulta" --project "$FIXTURE")"
REQ1="$(python3 -c "import json,sys; print(json.load(sys.stdin)['request_id'])" <<< "$OUT1")"

if [ "$(query "SELECT completed_at IS NULL FROM workflow_metrics WHERE request_id='$REQ1'")" = "1" ]; then
  assert_pass "primera clasificación queda abierta (completed_at NULL)"
else
  assert_fail "primera clasificación queda abierta"
fi

OUT2="$(bash "$ROOT/scripts/skalling-route.sh" classify --kind research --risk low \
  --record --intent "reclasifico" --project "$FIXTURE")"
REQ2="$(python3 -c "import json,sys; print(json.load(sys.stdin)['request_id'])" <<< "$OUT2")"

if [ "$REQ1" != "$REQ2" ]; then
  assert_pass "la reclasificación genera un request_id nuevo"
else
  assert_fail "la reclasificación genera un request_id nuevo" "mismo id: $REQ1"
fi

OUTCOME1="$(query "SELECT outcome FROM workflow_metrics WHERE request_id='$REQ1'")"
COMPLETED1="$(query "SELECT completed_at IS NOT NULL FROM workflow_metrics WHERE request_id='$REQ1'")"
if [ "$OUTCOME1" = "superseded" ] && [ "$COMPLETED1" = "1" ]; then
  assert_pass "classify --record cierra sola la métrica anterior como 'superseded'"
else
  assert_fail "classify --record cierra sola la métrica anterior" "outcome=$OUTCOME1 completed=$COMPLETED1"
fi

if [ "$(query "SELECT completed_at IS NULL FROM workflow_metrics WHERE request_id='$REQ2'")" = "1" ]; then
  assert_pass "la clasificación nueva (actual) sigue abierta"
else
  assert_fail "la clasificación nueva (actual) sigue abierta"
fi

# Una fila vieja (>30 min) no se toca -- eso lo cubre el barrido de 2h de
# skalling-metrics.sh start, pensado para crashes reales, no para esto.
sqlite3 "$DB" "INSERT INTO workflow_metrics (request_id,risk_level,route,agents_count,started_at) VALUES ('req-viejo','low','RESEARCH',1,datetime('now','-45 minutes'))"
bash "$ROOT/scripts/skalling-route.sh" classify --kind research --risk low \
  --record --intent "otra reclasificación" --project "$FIXTURE" >/dev/null

if [ "$(query "SELECT completed_at IS NULL FROM workflow_metrics WHERE request_id='req-viejo'")" = "1" ]; then
  assert_pass "una fila de más de 30 min no se cierra (queda para el barrido de crashes)"
else
  assert_fail "una fila de más de 30 min no se cierra"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
