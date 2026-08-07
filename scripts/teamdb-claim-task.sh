#!/usr/bin/env bash
# teamdb-claim-task.sh — Claim task con CAS (compare-and-swap)
# Previene que 2 agentes editen la misma task simultáneamente
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

TASK_ID="${1:-}"
AGENT="${2:-teo}"
PROJECT="${3:-$(pwd)}"

if [ -z "$TASK_ID" ]; then
  echo "Uso: bash teamdb-claim-task.sh <task_id> [agent] [project]"
  echo ""
  echo "Ejemplo: bash teamdb-claim-task.sh 1 teo ."
  exit 1
fi

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

# CAS: solo actualiza si status actual = pending.
# Hacemos UPDATE + SELECT para capturar el resultado, luego INSERT separado
# en task_lock_history solo si la claim tuvo éxito.
RESULT=$(sqlite3 "$DB" <<SQL
UPDATE tasks
SET status = 'in_progress',
    owner = '$AGENT',
    locked_by = '$AGENT',
    locked_at = datetime('now'),
    version = version + 1,
    last_modified_by = '$AGENT',
    started_at = datetime('now')
WHERE id = $TASK_ID
  AND status = 'pending';

SELECT CASE WHEN changes() > 0 THEN 'claimed' ELSE 'failed' END as result;
SQL
)

# Solo registrar lock history si la claim fue exitosa
if [ "$RESULT" = "claimed" ]; then
  sqlite3 "$DB" <<SQL >/dev/null
INSERT INTO task_lock_history (task_id, agent, action, ts, new_version, details)
VALUES ($TASK_ID, '$AGENT', 'lock', datetime('now'),
        (SELECT version FROM tasks WHERE id = $TASK_ID),
        'CAS claim OK');
SQL
fi

if [ "$RESULT" = "claimed" ]; then
  echo "OK: task $TASK_ID claimed por $AGENT"
  exit 0
else
  echo "FAIL: task $TASK_ID no estaba pending (ya claimed por otro)"
  exit 1
fi
