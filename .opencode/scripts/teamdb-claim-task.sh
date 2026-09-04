#!/usr/bin/env bash
# teamdb-claim-task.sh — Claim task con CAS (compare-and-swap)
# Previene que 2 agentes editen la misma task simultáneamente
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback
# shellcheck disable=SC1091
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
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT


if [ -z "$TASK_ID" ]; then
  echo "Uso: bash teamdb-claim-task.sh <task_id> [agent] [project]"
  echo ""
  echo "Ejemplo: bash teamdb-claim-task.sh 1 teo ."
  exit 1
fi

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

case "$TASK_ID" in
  ''|*[!0-9]*) echo "ERROR: task_id debe ser un entero positivo" >&2; exit 2 ;;
esac

RESULT="$(python3 - "$DB" "$TASK_ID" "$AGENT" <<'PY'
import sqlite3
import sys

db, task_id, agent = sys.argv[1], int(sys.argv[2]), sys.argv[3]
conn = sqlite3.connect(db, timeout=10)
try:
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("BEGIN IMMEDIATE")
    cursor = conn.execute(
        """UPDATE tasks
           SET status='in_progress', owner=?, locked_by=?, locked_at=datetime('now'),
               version=version+1, last_modified_by=?, started_at=datetime('now')
           WHERE id=? AND status='pending'""",
        (agent, agent, agent, task_id),
    )
    if cursor.rowcount != 1:
        conn.rollback()
        print("failed")
    else:
        conn.execute(
            """INSERT INTO task_lock_history
               (task_id, agent, action, ts, new_version, details)
               VALUES (?, ?, 'lock', datetime('now'),
                       (SELECT version FROM tasks WHERE id=?), 'CAS claim OK')""",
            (task_id, agent, task_id),
        )
        conn.commit()
        print("claimed")
finally:
    conn.close()
PY
)"

if [ "$RESULT" = "claimed" ]; then
  # Validación: que el comando realmente corrió
  # Si el comando es test/build, guardar el exit_code real
  COMMAND="${TEAMDB_CLAIM_COMMAND:-}"
  EXIT_CODE="${TEAMDB_CLAIM_EXIT_CODE:-}"

  if [ -n "$COMMAND" ] && [ -n "$EXIT_CODE" ]; then
    RECEIPT_ID="rcpt_$(date +%s%N | head -c 16)"
    case "$EXIT_CODE" in
      ''|*[!0-9]*) echo "ERROR: TEAMDB_CLAIM_EXIT_CODE debe ser entero" >&2; exit 2 ;;
    esac
    teamdb_exec_write "$DB" \
      "INSERT INTO receipts (id, task_id, agent, command, exit_code, ts) VALUES (?, ?, ?, ?, ?, datetime('now'))" \
      "$RECEIPT_ID" "$TASK_ID" "$AGENT" "$COMMAND" "$EXIT_CODE" >/dev/null
  fi

  # FASE 1: dump fresco post-escritura
  teamdb_refresh_dump "$PROJECT" >/dev/null 2>&1 || true

  echo "OK: task $TASK_ID claimed por $AGENT"
  exit 0
else
  echo "FAIL: task $TASK_ID no estaba pending (ya claimed por otro)"
  exit 1
fi
