#!/usr/bin/env bash
# tests/run-all.sh — la batería completa que corre CI (.github/workflows/tests.yml)
# y la que corre Jhon al sellar un receipt en este repo (.opencode/project.yaml).
# Una sola lista: lo que se verifica localmente es lo mismo que verifica CI.
#
# Python: usa .venv/bin/python si existe (jsonschema y pyyaml instalados ahí);
# si no, python3 del sistema. Una dependencia faltante es un FALLO, no un salto.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if [ -x "$ROOT/.venv/bin/python" ]; then PY="$ROOT/.venv/bin/python"; else PY="python3"; fi
fi
if ! "$PY" -c 'import jsonschema, yaml' 2>/dev/null; then
  echo "FALLO: $PY no tiene jsonschema/pyyaml (python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml)" >&2
  exit 1
fi
# Los tests invocan python3 por nombre: que resuelva al mismo intérprete.
PATH="$(dirname "$PY"):$PATH"
export PATH

COMMANDS=(
  "bash tests/setup.test.sh"
  "python3 tests/dashboard-server.test.py"
  "bash tests/dashboard-launcher.test.sh"
  "bash tests/quality-priorities.test.sh"
  "python3 tests/routing-safety.test.py"
  "python3 tests/context-regressions.test.py"
  "python3 tests/installed-workflow.test.py"
  "python3 tests/memory-permissions.test.py"
  "python3 tests/agent-autonomy-contract.test.py"
  "python3 tests/agent-behavioral-evals.test.py"
  "python3 tests/permission-generation.test.py"
  "python3 tests/workflow-engine.test.py"
  "python3 tests/data-safety.test.py"
  "node --test tests/data-safety-plugin.test.mjs"
  "node --test tests/data-safety-v2.test.mjs"
  "node --test tests/workflow-plugin.test.mjs"
  "node --test tests/git-guard-plugin.test.mjs"
  "python3 tests/skalling-goal.test.py"
  "node --test tests/skalling-goal-plugin.test.mjs"
  "bash tests/bootstrap-readiness.test.sh"
  "bash tests/audit-regressions.test.sh"
  "python3 tests/git-close.test.py"
  "bash tests/teamdb-hardening-suite.sh"
  "bash tests/scripts-parity.test.sh"
)

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
FAIL=0
for cmd in "${COMMANDS[@]}"; do
  if bash -c "$cmd" >"$LOG" 2>&1; then
    echo "✓ $cmd"
  else
    echo "✗ $cmd"
    tail -n 30 "$LOG" | sed 's/^/    │ /'
    FAIL=$((FAIL + 1))
  fi
done
echo ""
echo "run-all: $(( ${#COMMANDS[@]} - FAIL )) OK, $FAIL fallidas"
[ "$FAIL" -eq 0 ]
