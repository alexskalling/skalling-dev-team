#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

check() {
  local name="$1"
  shift
  if "$@"; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    FAIL=$((FAIL + 1))
  fi
}

check "claim legacy no interpola SQL con sqlite3" sh -c "! grep -q 'sqlite3 \"\$DB\"' '$ROOT/scripts/teamdb-claim-task.sh'"
check "pre-commit usa consultas parametrizadas" grep -q 'teamdb_exec_value' "$ROOT/scripts/hooks/pre-commit"
check "migración legacy falla si sqlite falla" sh -c "! grep -q 'sqlite3 \"\$local_db\" < \"\$1\".*|| true' '$ROOT/scripts/teamdb-migrate.sh'"
check "CI ejecuta pruebas del dashboard" grep -q 'dashboard-server.test.py' "$ROOT/.github/workflows/tests.yml"
check "CI ejecuta doctor estricto" grep -q 'setup-team-doctor.sh --strict' "$ROOT/.github/workflows/tests.yml"
check "doctor excluye respaldos de memoria" grep -q 'SKALLING_MEMORY_EXCLUDES' "$ROOT/setup-team-doctor.sh"
check "routing clasificado puede persistirse" grep -q -- '--record' "$ROOT/scripts/skalling-route.sh"
check "schema marca work_in_progress como legacy" grep -q 'legacy_surface.*work_in_progress' "$ROOT/sql/project-schema.sql"
check "política de retención es reutilizable" test -x "$ROOT/scripts/teamdb-prune-backups.sh"
check "licencia del proyecto existe" test -f "$ROOT/LICENSE"
check "versión fuente es 0.10.4" grep -q '0.10.4' "$ROOT/VERSION"
check "migración 0.10.4 existe" test -f "$ROOT/sql/migrations/025_version_0_10_4.sql"
check "instalador global falla si TeamDB no puede actualizarse" grep -q 'teamdb global: upgrade aditivo no aplicado' "$ROOT/install-global.sh"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/.opencode/context/.backups"
sqlite3 "$FIXTURE/.opencode/context/team.db" < "$ROOT/sql/project-schema.sql"
sqlite3 "$FIXTURE/.opencode/context/team.db" <<'SQL'
INSERT INTO proposals(slug,title,intent_md,status) VALUES('secure','Secure','# intent','approved');
INSERT INTO plans(slug,title,proposal_id,design_md,status)
VALUES('secure','Secure',(SELECT id FROM proposals WHERE slug='secure'),'# design','in_progress');
INSERT INTO tasks(plan_id,slug,title,status)
VALUES((SELECT id FROM plans WHERE slug='secure'),'task-1','Task 1','pending');
SQL
TASK_ID="$(sqlite3 "$FIXTURE/.opencode/context/team.db" "SELECT id FROM tasks WHERE slug='task-1'")"
bash "$ROOT/scripts/teamdb-claim-task.sh" "$TASK_ID" "teo'; DROP TABLE tasks; --" "$FIXTURE" >/dev/null
check "claim conserva la tabla ante entrada hostil" sqlite3 "$FIXTURE/.opencode/context/team.db" "SELECT 1 FROM tasks LIMIT 1"

ROUTE_OUTPUT="$(bash "$ROOT/scripts/skalling-route.sh" classify --risk high --kind code --record --intent "auditar ' routing" --project "$FIXTURE")"
check "routing devuelve request_id persistido" grep -q '"request_id"' <<< "$ROUTE_OUTPUT"
ROUTE_COUNTS="$(sqlite3 "$FIXTURE/.opencode/context/team.db" "SELECT (SELECT COUNT(*) FROM routing_decisions) || ':' || (SELECT COUNT(*) FROM workflow_metrics)")"
check "routing y métrica se guardan juntos" test "$ROUTE_COUNTS" = "1:1"

for index in 1 2 3 4 5 6 7; do
  touch "$FIXTURE/.opencode/context/.backups/team.db.backup-2026010$index-000000"
done
bash "$ROOT/scripts/teamdb-prune-backups.sh" "$FIXTURE" --keep 5 >/dev/null
check "retención conserva exactamente cinco backups" sh -c "[ \"\$(find '$FIXTURE/.opencode/context/.backups' -type f -name 'team.db.backup-*' | wc -l | tr -d ' ')\" = 5 ]"

printf '%s\n' '---' 'title: respaldo' '---' > "$FIXTURE/.opencode/context/.backups/agent.md"
MEMORY_LIST="$(bash -c '. "$1"; _skalling_list_concept_files "$2"' _ "$ROOT/scripts/lib/lib-memory-check.sh" "$FIXTURE/.opencode/context")"
check "memoria no indexa documentos de backups" sh -c "! grep -q '/.backups/' <<EOF
$MEMORY_LIST
EOF"

if [ "$FAIL" -gt 0 ]; then
  printf '%s checks fallaron\n' "$FAIL" >&2
  exit 1
fi
