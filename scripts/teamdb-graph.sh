#!/usr/bin/env bash
# teamdb-graph.sh — Visualizar grafo de teamdb
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
FORMAT="${2:-text}"
DB="$(teamdb_project_path "$PROJECT")"

[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

case "$FORMAT" in
  text)
    echo "🕸️  Grafo de TeamDB (text)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Concepts:"
    sqlite3 -separator "│" "$DB" "SELECT slug, category FROM concepts ORDER BY category, slug" | awk -F'│' '{printf "  [%s] %s\n", $2, $1}'
    echo ""
    echo "Decisions:"
    sqlite3 -separator "│" "$DB" "SELECT slug, status FROM decisions ORDER BY status, slug" | awk -F'│' '{printf "  [%s] %s\n", $2, $1}'
    echo ""
    echo "Links:"
    sqlite3 -separator "│" "$DB" "
      SELECT COALESCE(c1.slug, d1.slug) || ' --' || ml.link_type || '--> ' || COALESCE(c2.slug, d2.slug)
      FROM memory_links ml
      LEFT JOIN concepts c1 ON c1.id=ml.from_id AND ml.from_table='concepts'
      LEFT JOIN decisions d1 ON d1.id=ml.from_id AND ml.from_table='decisions'
      LEFT JOIN concepts c2 ON c2.id=ml.to_id AND ml.to_table='concepts'
      LEFT JOIN decisions d2 ON d2.id=ml.to_id AND ml.to_table='decisions'
    " | sed 's/^/  /'
    ;;

  mermaid)
    echo "graph TD"
    sqlite3 -separator "│" "$DB" "
      SELECT '  ' || COALESCE(c1.slug, d1.slug, '?') || ' -->|' || ml.link_type || '| ' || COALESCE(c2.slug, d2.slug, '?')
      FROM memory_links ml
      LEFT JOIN concepts c1 ON c1.id=ml.from_id AND ml.from_table='concepts'
      LEFT JOIN decisions d1 ON d1.id=ml.from_id AND ml.from_table='decisions'
      LEFT JOIN concepts c2 ON c2.id=ml.to_id AND ml.to_table='concepts'
      LEFT JOIN decisions d2 ON d2.id=ml.to_id AND ml.to_table='decisions'
    "
    ;;

  dot)
    echo "digraph G {"
    echo "  rankdir=LR;"
    sqlite3 -separator "│" "$DB" "
      SELECT '  \"' || COALESCE(c1.slug, d1.slug, '?') || '\" -> \"' || COALESCE(c2.slug, d2.slug, '?') || '\" [label=\"' || ml.link_type || '\"];'
      FROM memory_links ml
      LEFT JOIN concepts c1 ON c1.id=ml.from_id AND ml.from_table='concepts'
      LEFT JOIN decisions d1 ON d1.id=ml.from_id AND ml.from_table='decisions'
      LEFT JOIN concepts c2 ON c2.id=ml.to_id AND ml.to_table='concepts'
      LEFT JOIN decisions d2 ON d2.id=ml.to_id AND ml.to_table='decisions'
    "
    echo "}"
    ;;

  *)
    echo "Formato desconocido: $FORMAT"
    echo "Formatos: text, mermaid, dot"
    exit 1
    ;;
esac
