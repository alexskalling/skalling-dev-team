#!/usr/bin/env bash
# teamdb-import.sh — .sql → DB (idempotente, no rompe DB existente)
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export SKALLING_ROOT="$SKALLING_ROOT_DIR"
# Fallback: funciona en repo (lib/lib-teamdb.sh) y en global (lib-teamdb.sh)
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
# Lock file para evitar race conditions entre agentes
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

teamdb_init_project "$PROJECT"
local_db="$(teamdb_project_path "$PROJECT")"

IN="$PROJECT/.opencode/context/teamdb"
[ -d "$IN" ] || { echo "no dir: $IN" >&2; exit 1; }

# Extraer solo INSERTs del dump (evita CREATE TABLE en DB existente)
extract_inserts() {
  local sql_file="$1"
  grep -E "^INSERT INTO " "$sql_file" 2>/dev/null || true
}

imported=0
skipped=0
for sql in "$IN"/data_*.sql; do
  [ -e "$sql" ] || continue
  [ -s "$sql" ] || continue

  inserts=$(extract_inserts "$sql")
  if [ -n "$inserts" ]; then
    table=$(basename "$sql" .sql | sed 's/^data_//')
    if echo "$inserts" | sqlite3 "$local_db" 2>/dev/null; then
      imported=$((imported + 1))
    else
      echo "WARNING: Could not import $table (may have conflicts)" >&2
      skipped=$((skipped + 1))
    fi
  fi
done

echo "imported: $local_db ($imported tables, $skipped skipped)"
