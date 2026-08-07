#!/usr/bin/env bash
# teamdb-hardening-suite.sh — corre todas las tests del cambio v0.7.2 en serie
set -e
SKALLING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SKALLING_ROOT"

PASS=0; FAIL=0
for t in tests/teamdb-safe-query.test.sh \
         tests/teamdb-search-sqli.test.sh \
         tests/teamdb-related-sqli.test.sh \
         tests/teamdb-problems-fts.test.sh \
         tests/install-script-copies.test.sh \
         tests/install-hooks-paths.test.sh \
         tests/audit-log-actor.test.sh \
         tests/teamdb-plan.test.sh \
         tests/teamdb-status.test.sh \
         tests/teamdb-resume.test.sh \
         tests/teamdb-export-audit.test.sh \
         tests/teamdb-migrate-md-preserve.test.sh \
         tests/version-coherence.test.sh \
         tests/portability-bash32.test.sh \
         tests/snippets-sync.test.sh \
         tests/install-resolves-snippets.test.sh \
         tests/handoff-schema-validation.test.sh \
         tests/agents-teamdb-integration.test.sh \
         tests/audit-log-actor-source.test.sh \
         tests/teamdb-global-heal.test.sh \
         tests/teamdb-dag-tables-exist.test.sh \
         tests/teamdb-amend-full.test.sh \
         tests/teamdb-deps-dag.test.sh \
         tests/teamdb-claim-lease.test.sh \
         tests/teamdb-export-md.test.sh \
         tests/teamdb-context-capsule.test.sh \
         tests/teamdb-cycle-amended.test.sh \
         tests/teamdb-claim-strict.test.sh \
         tests/teamdb-claim-history.test.sh \
         tests/teamdb-context-issue8.test.sh \
         tests/teamdb-execute-plan-no-shell.test.sh \
         tests/teamdb-migration-003-unique.test.sh \
         tests/teamdb-plan-atomic-idempotent.test.sh \
         tests/teamdb-python-bindparams.test.sh \
         tests/teamdb-write-wal.test.sh \
         tests/teamdb.test.sh \
         tests/code-intelligence.test.sh \
         tests/memory-protocol.test.sh \
         tests/spec-memory-link.test.sh \
         tests/skalling-drift.test.sh \
         tests/concept-template.test.sh \
         tests/conflict-detection.test.sh \
         tests/teamdb-link.test.sh \
         tests/review-lenses.test.sh \
         tests/pre-push.test.sh \
         tests/attempts.test.sh; do
  if [ -f "$t" ]; then
    if bash "$t" >/dev/null 2>&1; then
      echo "✓ $t"
      PASS=$((PASS+1))
    else
      echo "✗ $t"
      FAIL=$((FAIL+1))
    fi
  fi
done

echo ""
echo "Suite: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
