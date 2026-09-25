#!/usr/bin/env bash
# teamdb-hardening-suite.sh — corre todas las tests del cambio v0.7.2 en paralelo.
#
# Antes corria en serie (73 tests, uno por uno). Cada test arma su propio
# fixture con mktemp y no toca estado global compartido (verificado: ninguno
# hace git add/commit/stash sobre el propio repo fuera de un fixture, y el
# unico que corre install-global.sh de verdad aisla SKALLING_OPENCODE_DIR) --
# son independientes entre si, asi que correrlos en paralelo no cambia QUE se
# prueba ni el resultado, solo el tiempo de pared.
#
# SKALLING_TEST_JOBS controla cuantos corren a la vez (default 8). Si algo
# nuevo alguna vez comparte estado global real, sacarlo de esta lista y
# correrlo aparte en serie -- no forzar paralelismo sobre algo que lo rompe.
#
# dashboard-survives-group-kill.test.sh queda afuera del lote paralelo a
# proposito: usa "set -m" para forzar su propio process group y mandarle una
# señal (asi prueba que el server sobrevive). Bajo xargs -P falla siempre
# (confirmado: pasa 100% solo, falla 100% en paralelo) -- el process group
# que arma no queda aislado igual dentro de un hijo de xargs. No es un test
# flaky para descartar; es una razon real para correrlo aparte, en serie.
set -e
SKALLING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SKALLING_ROOT"

JOBS="${SKALLING_TEST_JOBS:-8}"

TESTS=(
  tests/dashboard-server.test.py
  tests/dashboard-launcher.test.sh
  tests/quality-priorities.test.sh
  tests/skalling-metrics-summary.test.sh
  tests/skalling-metrics-orphan-cleanup.test.sh
  tests/permission-generation.test.py
  tests/workflow-engine.test.py
  tests/workflow-git-gate-bridge.test.py
  tests/teamdb-safe-query.test.sh
  tests/teamdb-read.test.sh
  tests/skalling-route-supersede.test.sh
  tests/skalling-coverage.test.sh
  tests/skills-shared-references.test.sh
  tests/teamdb-task-groups.test.sh
  tests/skalling-models.test.sh
  tests/git-gate-failclosed.test.sh
  tests/skalling-verify-gate.test.sh
  tests/teamdb-plan-parallel-groups.test.sh
  tests/mirror-parity.test.sh
  tests/skalling-review-sast.test.sh
  tests/teamdb-search-sqli.test.sh
  tests/teamdb-related-sqli.test.sh
  tests/teamdb-wip-tree-sqli.test.sh
  tests/teamdb-link-sqli.test.sh
  tests/scripts-parity.test.sh
  tests/teamdb-problems-fts.test.sh
  tests/install-script-copies.test.sh
  tests/install-orphan-cleanup.test.sh
  tests/install-hooks-paths.test.sh
  tests/audit-log-actor.test.sh
  tests/teamdb-plan.test.sh
  tests/teamdb-status.test.sh
  tests/teamdb-resume.test.sh
  tests/teamdb-export-audit.test.sh
  tests/teamdb-migrate-md-preserve.test.sh
  tests/migrate-plans-sqli.test.sh
  tests/version-coherence.test.sh
  tests/portability-bash32.test.sh
  tests/snippets-sync.test.sh
  tests/install-resolves-snippets.test.sh
  tests/install-platform-contract.test.sh
  tests/handoff-schema-validation.test.sh
  tests/agents-teamdb-integration.test.sh
  tests/audit-log-actor-source.test.sh
  tests/teamdb-global-heal.test.sh
  tests/teamdb-dag-tables-exist.test.sh
  tests/teamdb-amend-full.test.sh
  tests/teamdb-deps-dag.test.sh
  tests/teamdb-claim-lease.test.sh
  tests/teamdb-workflow-state-sync.test.sh
  tests/teamdb-plan-stdin-last-task.test.sh
  tests/teamdb-export-md.test.sh
  tests/teamdb-context-capsule.test.sh
  tests/teamdb-cycle-amended.test.sh
  tests/teamdb-claim-strict.test.sh
  tests/teamdb-independent-verification.test.sh
  tests/teamdb-claim-history.test.sh
  tests/teamdb-context-issue8.test.sh
  tests/teamdb-execute-plan-no-shell.test.sh
  tests/teamdb-ingest-change.test.sh
  tests/teamdb-migration-003-unique.test.sh
  tests/teamdb-plan-atomic-idempotent.test.sh
  tests/teamdb-python-bindparams.test.sh
  tests/teamdb-write-wal.test.sh
  tests/teamdb-operating-model.test.sh
  tests/agents-quality-contract.test.sh
  tests/workflow-routing.test.sh
  tests/commands-contract.test.sh
  tests/teamdb.test.sh
  tests/test-teamdb-dump-sync.test.sh
  tests/code-intelligence.test.sh
  tests/memory-protocol.test.sh
  tests/spec-memory-link.test.sh
  tests/skalling-drift.test.sh
  tests/concept-template.test.sh
  tests/conflict-detection.test.sh
  tests/teamdb-link.test.sh
  tests/review-lenses.test.sh
  tests/pre-push.test.sh
  tests/attempts.test.sh
)

RESULTS="$(printf '%s\n' "${TESTS[@]}" | xargs -P "$JOBS" -I{} bash -c '
  t="{}"
  if [ -f "$t" ]; then
    if { case "$t" in *.py) python3 "$t" ;; *) bash "$t" ;; esac; } >/dev/null 2>&1; then
      echo "PASS:$t"
    else
      echo "FAIL:$t"
    fi
  fi
')"

PASS=0; FAIL=0
while IFS= read -r line; do
  case "$line" in
    PASS:*) echo "✓ ${line#PASS:}"; PASS=$((PASS+1)) ;;
    FAIL:*) echo "✗ ${line#FAIL:}"; FAIL=$((FAIL+1)) ;;
  esac
done <<< "$RESULTS"

# Serial a proposito -- ver comentario arriba de TESTS.
t="tests/dashboard-survives-group-kill.test.sh"
if [ -f "$t" ]; then
  if bash "$t" >/dev/null 2>&1; then
    echo "✓ $t"
    PASS=$((PASS+1))
  else
    echo "✗ $t"
    FAIL=$((FAIL+1))
  fi
fi

echo ""
echo "Suite: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
