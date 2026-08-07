#!/usr/bin/env bash
# teamdb-export.sh — DB → .sql (incluye audit_log, schema_meta, cycle + DAG + claims)
# T-2.7 + T-2.9: exporta todas las tablas relevantes para que `git diff` refleje cambios.
# Lock file para evitar race conditions entre agentes
LOCK_DIR="${PROJECT:-$(pwd)}/.opencode/context"
LOCK_FILE="$LOCK_DIR/team.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true
exec 9>"$LOCK_FILE" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  flock -w 10 9 || { echo "ERROR: no se pudo obtener lock en $LOCK_FILE" >&2; exit 1; }
fi
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

PROJECT="${1:-$(pwd)}"
local_db="$(teamdb_project_path "$PROJECT")"
[ -f "$local_db" ] || { echo "no DB: $local_db" >&2; exit 1; }

OUT="$PROJECT/.opencode/context/teamdb"
mkdir -p "$OUT"

# Tablas de "datos de usuario" + cycle + DAG + claims + history + capsules
USER_TABLES="concepts decisions preferences known_problems memory_links memory_tags work_in_progress proposals plans specs design_notes tasks task_dependencies task_claims plan_history task_context_capsules audit_log schema_meta"

for table in $USER_TABLES; do
  out="$OUT/data_${table}.sql"
  if sqlite3 "$local_db" ".dump $table" > "$out" 2>/dev/null; then
    :
  fi
done

echo "exported: $OUT"
