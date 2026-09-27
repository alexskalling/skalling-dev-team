#!/usr/bin/env bash
# tests/skalling-route-supersede.test.sh — una reclasificación cierra SOLO el
# pedido que nombra con --supersedes.
#
# Historia: (1) Survan, 2026-09-13: reclasificar dejaba métricas en 'pending'
# para siempre. (2) Se "arregló" cerrando cualquier métrica abierta de los
# últimos 30 min, y la auditoría externa de v0.12.0 mostró el efecto: el
# pedido independiente de otra sesión quedaba 'superseded'. El reemplazo
# tiene que ser explícito.
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
classify() { bash "$ROOT/scripts/skalling-route.sh" classify --kind research --risk low --record --project "$FIXTURE" "$@"; }
request_id() { python3 -c "import json,sys; print(json.load(sys.stdin)['request_id'])"; }

REQ1="$(classify --intent "pedido de la sesión A" --request-id req-a | request_id)"
REQ2="$(classify --intent "pedido independiente de la sesión B" --request-id req-b | request_id)"

if [ "$(query "SELECT completed_at IS NULL FROM workflow_metrics WHERE request_id='$REQ1'")" = "1" ]; then
  assert_pass "un pedido independiente no cierra el de otra sesión"
else
  assert_fail "un pedido independiente no cierra el de otra sesión" \
    "$(query "SELECT outcome FROM workflow_metrics WHERE request_id='$REQ1'")"
fi

REQ3="$(classify --intent "reclasifico el pedido A" --request-id req-a2 --supersedes "$REQ1" | request_id)"
OUTCOME1="$(query "SELECT outcome FROM workflow_metrics WHERE request_id='$REQ1'")"
if [ "$OUTCOME1" = "superseded" ]; then
  assert_pass "--supersedes cierra explícitamente el pedido reemplazado"
else
  assert_fail "--supersedes cierra el pedido reemplazado" "outcome=$OUTCOME1"
fi

if [ "$(query "SELECT completed_at IS NULL FROM workflow_metrics WHERE request_id='$REQ2'")" = "1" ] \
  && [ "$(query "SELECT completed_at IS NULL FROM workflow_metrics WHERE request_id='$REQ3'")" = "1" ]; then
  assert_pass "el reemplazo no toca otros pedidos abiertos"
else
  assert_fail "el reemplazo no toca otros pedidos abiertos"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
