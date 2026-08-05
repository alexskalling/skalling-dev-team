#!/usr/bin/env bash
# teamdb-search.sh — Búsqueda amigable en teamdb
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

QUERY="${1:-}"
TYPE="${2:-all}"
PROJECT="${3:-$(pwd)}"

if [ -z "$QUERY" ]; then
  echo "Uso: bash teamdb-search.sh <query> [type] [project]"
  echo ""
  echo "Tipos: all, concepts, decisions, preferences, problems, wip"
  echo ""
  echo "Ejemplos:"
  echo "  bash teamdb-search.sh 'JWT'"
  echo "  bash teamdb-search.sh 'auth' concepts"
  echo "  bash teamdb-search.sh 'refresh' decisions"
  exit 1
fi

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

echo "🔍 Buscando '$QUERY' (tipo: $TYPE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$TYPE" = "all" ] || [ "$TYPE" = "concepts" ]; then
  echo "📦 CONCEPTS:"
  sqlite3 -separator "│" "$DB" "SELECT slug, title, category FROM concepts WHERE id IN (SELECT rowid FROM concepts_fts WHERE concepts_fts MATCH '$QUERY') ORDER BY updated_at DESC LIMIT 10" 2>/dev/null | awk -F'│' '{printf "  • [%s] %s (%s)\n", $1, $2, $3}'
  echo ""
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "decisions" ]; then
  echo "📋 DECISIONS:"
  sqlite3 -separator "│" "$DB" "SELECT slug, title, status FROM decisions WHERE id IN (SELECT rowid FROM decisions_fts WHERE decisions_fts MATCH '$QUERY') ORDER BY decided_at DESC LIMIT 10" 2>/dev/null | awk -F'│' '{printf "  • [%s] %s (%s)\n", $1, $2, $3}'
  echo ""
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "preferences" ]; then
  echo "⚙️  PREFERENCES:"
  sqlite3 -separator "│" "$DB" "SELECT slug, scope FROM preferences WHERE body_md LIKE '%$QUERY%' LIMIT 10" 2>/dev/null | awk -F'│' '{printf "  • [%s] (%s)\n", $1, $2}'
  echo ""
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "problems" ]; then
  echo "⚠️  PROBLEMAS:"
  sqlite3 -separator "│" "$DB" "SELECT slug, title, status FROM known_problems WHERE id IN (SELECT rowid FROM concepts_fts WHERE concepts_fts MATCH '$QUERY') OR symptom_md LIKE '%$QUERY%' OR workaround_md LIKE '%$QUERY%' LIMIT 10" 2>/dev/null | awk -F'│' '{printf "  • [%s] %s (%s)\n", $1, $2, $3}'
  echo ""
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "wip" ]; then
  echo "🚧 WIP:"
  sqlite3 -separator "│" "$DB" "SELECT slug, status, owner FROM work_in_progress WHERE id IN (SELECT rowid FROM wip_fts WHERE wip_fts MATCH '$QUERY') OR title LIKE '%$QUERY%' LIMIT 10" 2>/dev/null | awk -F'│' '{printf "  • [%s] %s (@%s)\n", $1, $2, $3}'
  echo ""
fi
