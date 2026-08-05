#!/usr/bin/env bash
# teamdb-related.sh — Ver relaciones de un concept/decision
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

SLUG="${1:-}"
TYPE="${2:-concept}"
PROJECT="${3:-$(pwd)}"

if [ -z "$SLUG" ]; then
  echo "Uso: bash teamdb-related.sh <slug> [type] [project]"
  echo ""
  echo "Tipos: concept, decision, preference, problem"
  echo ""
  echo "Ejemplos:"
  echo "  bash teamdb-related.sh auth-jwt"
  echo "  bash teamdb-related.sh use-jwt decision"
  exit 1
fi

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

echo "🔗 Relaciones de '$SLUG' ($TYPE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

case "$TYPE" in
  concept) TABLE="concepts"; ID_QUERY="SELECT id FROM concepts WHERE slug='$SLUG'" ;;
  decision) TABLE="decisions"; ID_QUERY="SELECT id FROM decisions WHERE slug='$SLUG'" ;;
  preference) TABLE="preferences"; ID_QUERY="SELECT id FROM preferences WHERE slug='$SLUG'" ;;
  problem) TABLE="known_problems"; ID_QUERY="SELECT id FROM known_problems WHERE slug='$SLUG'" ;;
  *) echo "Tipo desconocido: $TYPE"; exit 1 ;;
esac

ID=$(sqlite3 "$DB" "$ID_QUERY" 2>/dev/null)
if [ -z "$ID" ]; then
  echo "❌ No existe $TYPE con slug '$SLUG'"
  exit 1
fi

echo "🏷️  TAGS:"
tags=$(sqlite3 -separator "│" "$DB" "SELECT t.name FROM tags t JOIN memory_tags mt ON mt.tag_id=t.id WHERE mt.memory_table='$TABLE' AND mt.memory_id=$ID")
if [ -z "$tags" ]; then
  echo "  (sin tags)"
else
  echo "$tags" | sed 's/^/  • /'
fi
echo ""

echo "➡️  ESTE → otros (link_type):"
links_out=$(sqlite3 -separator "│" "$DB" "
  SELECT ml.link_type, ml.to_table, COALESCE(c.slug, d.slug, p.slug, kp.slug)
  FROM memory_links ml
  LEFT JOIN concepts c ON ml.to_table='concepts' AND c.id=ml.to_id
  LEFT JOIN decisions d ON ml.to_table='decisions' AND d.id=ml.to_id
  LEFT JOIN preferences p ON ml.to_table='preferences' AND p.id=ml.to_id
  LEFT JOIN known_problems kp ON ml.to_table='known_problems' AND kp.id=ml.to_id
  WHERE ml.from_table='$TABLE' AND ml.from_id=$ID
")
if [ -z "$links_out" ]; then
  echo "  (nada)"
else
  echo "$links_out" | awk -F'│' '{printf "  • %s → %s (%s)\n", $1, $2, $3}'
fi
echo ""

echo "⬅️  otros → ESTE (link_type):"
links_in=$(sqlite3 -separator "│" "$DB" "
  SELECT ml.link_type, ml.from_table, COALESCE(c.slug, d.slug, p.slug, kp.slug)
  FROM memory_links ml
  LEFT JOIN concepts c ON ml.from_table='concepts' AND c.id=ml.from_id
  LEFT JOIN decisions d ON ml.from_table='decisions' AND d.id=ml.from_id
  LEFT JOIN preferences p ON ml.from_table='preferences' AND p.id=ml.from_id
  LEFT JOIN known_problems kp ON ml.from_table='known_problems' AND kp.id=ml.from_id
  WHERE ml.to_table='$TABLE' AND ml.to_id=$ID
")
if [ -z "$links_in" ]; then
  echo "  (nada)"
else
  echo "$links_in" | awk -F'│' '{printf "  • %s → %s (%s)\n", $1, $2, $3}'
fi
echo ""
