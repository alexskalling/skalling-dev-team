#!/usr/bin/env bash
# tests/skalling-metrics-orphan-cleanup.test.sh — auto-cierre de metricas huerfanas
# Motivacion: en uso real, la mayoria de las filas de workflow_metrics nunca
# llegaban a "finish" (agente cortado, sesion perdida) y quedaban con
# completed_at NULL para siempre -- invisibles en report/summary, dando una
# falsa sensacion de que no hay datos suficientes para medir nada.
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

# Fila vieja (>2h) sin cerrar: debe quedar marcada 'abandoned' al arrancar una nueva.
sqlite3 "$DB" "INSERT INTO workflow_metrics(request_id,risk_level,started_at) VALUES('old-orphan','low',datetime('now','-3 hours'))"
# Fila reciente (<2h) sin cerrar: podria ser una sesion concurrente legitima
# sobre el mismo proyecto -- NO debe tocarse.
sqlite3 "$DB" "INSERT INTO workflow_metrics(request_id,risk_level,started_at) VALUES('recent-concurrent','low',datetime('now','-30 minutes'))"

bash "$ROOT/scripts/skalling-metrics.sh" start new-request low "$FIXTURE" >/dev/null 2>&1

OLD_OUTCOME="$(sqlite3 "$DB" "SELECT outcome FROM workflow_metrics WHERE request_id='old-orphan'")"
OLD_COMPLETED="$(sqlite3 "$DB" "SELECT completed_at IS NOT NULL FROM workflow_metrics WHERE request_id='old-orphan'")"
if [ "$OLD_OUTCOME" = "abandoned" ] && [ "$OLD_COMPLETED" = "1" ]; then
  assert_pass "request huerfana (>2h) se cierra como 'abandoned' al arrancar una nueva"
else
  assert_fail "request huerfana (>2h) se cierra como 'abandoned'" "outcome=$OLD_OUTCOME completed=$OLD_COMPLETED"
fi

RECENT_OUTCOME="$(sqlite3 "$DB" "SELECT outcome FROM workflow_metrics WHERE request_id='recent-concurrent'")"
if [ -z "$RECENT_OUTCOME" ]; then
  assert_pass "request concurrente reciente (<2h) NO se toca"
else
  assert_fail "request concurrente reciente (<2h) NO se toca" "outcome=$RECENT_OUTCOME"
fi

NEW_EXISTS="$(sqlite3 "$DB" "SELECT COUNT(*) FROM workflow_metrics WHERE request_id='new-request' AND completed_at IS NULL")"
if [ "$NEW_EXISTS" = "1" ]; then
  assert_pass "la request nueva se inserta abierta, sin verse afectada por su propio cleanup"
else
  assert_fail "la request nueva se inserta abierta" "count=$NEW_EXISTS"
fi

# summary ya no ignora en silencio las huerfanas viejas: cuentan como run no-exitoso.
SUMMARY="$(bash "$ROOT/scripts/skalling-metrics.sh" summary "$FIXTURE")"
if printf '%s' "$SUMMARY" | grep -q "success=0"; then
  assert_pass "summary refleja la huerfana como run sin éxito, no la ignora"
else
  assert_fail "summary refleja la huerfana como run sin éxito" "summary=$SUMMARY"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$ROOT/scripts/skalling-metrics.sh" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "skalling-metrics.sh shellcheck 0 errores"
  else
    assert_fail "skalling-metrics.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
