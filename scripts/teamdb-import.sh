#!/usr/bin/env bash
# teamdb-import.sh — .sql → DB
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/lib-teamdb.sh"

PROJECT="${1:-$(pwd)}"
teamdb_init_project "$PROJECT"
local_db="$(teamdb_project_path "$PROJECT")"

IN="$PROJECT/.opencode/context/teamdb"
[ -d "$IN" ] || { echo "no dir: $IN" >&2; exit 1; }

for sql in "$IN"/data_*.sql; do
  [ -e "$sql" ] || continue
  [ -s "$sql" ] && sqlite3 "$local_db" < "$sql"
done

echo "imported: $local_db"
