#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/teamdb-dashboard.sh"
PASS=0
FAIL=0

check() {
  local name="$1"; shift
  if "$@"; then echo "✓ $name"; PASS=$((PASS+1)); else echo "✗ $name"; FAIL=$((FAIL+1)); fi
}

check "soporta start, stop y status" grep -Eq 'start\|stop\|status' "$SCRIPT"
check "estado temporal aislado por proyecto" grep -q 'PROJECT_KEY' "$SCRIPT"
check "no se apaga a los cinco minutos" sh -c "! grep -q 'TIMEOUT_SECS=300' '$SCRIPT'"
check "no depende de netcat" sh -c "! grep -Eq '\bnc -z\b' '$SCRIPT'"
check "espera readiness HTTP" grep -q '/api/health' "$SCRIPT"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
