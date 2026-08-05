#!/usr/bin/env bash
# teamdb-export.sh — DB → .sql
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Fallback: funciona en repo (lib/lib-teamdb.sh) y en global (lib-teamdb.sh)
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
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

sqlite3 "$local_db" ".dump concepts" > "$OUT/data_concepts.sql" 2>/dev/null || true
sqlite3 "$local_db" ".dump decisions" > "$OUT/data_decisions.sql" 2>/dev/null || true
sqlite3 "$local_db" ".dump preferences" > "$OUT/data_preferences.sql" 2>/dev/null || true
sqlite3 "$local_db" ".dump known_problems" > "$OUT/data_problems.sql" 2>/dev/null || true
sqlite3 "$local_db" ".dump memory_links" > "$OUT/data_memory_links.sql" 2>/dev/null || true
sqlite3 "$local_db" ".dump memory_tags" > "$OUT/data_memory_tags.sql" 2>/dev/null || true

echo "exported: $OUT"
