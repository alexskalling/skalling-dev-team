#!/usr/bin/env bash
# teamdb-claim-task.sh — Claim task con CAS (compare-and-swap)
# Previene que 2 agentes editen la misma task simultáneamente
# Lock file (se aplica al final, después de parsing $PROJECT)
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
# Lock file para evitar race conditions entre agentes
LOCK_DIR="$PROJECT/.opencode/context"
LOCK_FILE="$LOCK_DIR/team.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" 2>/dev/null || true
  flock -w 10 9 || { echo "ERROR: no se pudo obtener lock en $LOCK_FILE" >&2; exit 1; }
fi
trap 'exec 9>&- 2>/dev/null' EXIT


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
  # Validación: que el comando realmente corrió
  # Si el comando es test/build, guardar el exit_code real
  COMMAND="${TEAMDB_CLAIM_COMMAND:-}"
  EXIT_CODE="${TEAMDB_CLAIM_EXIT_CODE:-}"

  if [ -n "$COMMAND" ] && [ -n "$EXIT_CODE" ]; then
    DB="$(teamdb_project_path "$PROJECT")"
    RECEIPT_ID="rcpt_$(date +%s%N | head -c 16)"
    sqlite3 "$DB" "INSERT INTO receipts (id, task_id, agent, command, exit_code, ts) VALUES ('$RECEIPT_ID', $TASK_ID, '$AGENT', '$COMMAND', $EXIT_CODE, datetime('now'))"
  fi

  echo "OK: task $TASK_ID claimed por $AGENT"
  exit 0
else
  echo "FAIL: task $TASK_ID no estaba pending (ya claimed por otro)"
  exit 1
fi
