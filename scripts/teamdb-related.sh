#!/usr/bin/env bash
# teamdb-related.sh — Ver relaciones (T-2.10: bound-param via teamdb_exec_query)
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

# Whitelist de tipos -> tabla canonica. Cualquier otro falla (anti-SQLi).
case "$TYPE" in
  concept)    TABLE="concepts" ;;
  decision)   TABLE="decisions" ;;
  preference) TABLE="preferences" ;;
  problem)    TABLE="known_problems" ;;
  *) echo "[ERROR] Tipo inválido: $TYPE (usa: concept|decision|preference|problem)" >&2; exit 2 ;;
esac

echo "🔗 Relaciones de '$SLUG' ($TYPE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ID lookup con bind param
ID="$(teamdb_exec_value "$DB" "SELECT id FROM $TABLE WHERE slug = ?" "$SLUG" 2>/dev/null || true)"
case "$ID" in
  ''|*[!0-9]*) echo "❌ No existe $TYPE con slug '$SLUG'" >&2; exit 1 ;;
  *)
    [ "$ID" -gt 0 ] || { echo "[ERROR] ID inválido" >&2; exit 1; }
    ;;
esac

# Tags
echo "🏷️  TAGS:"
tags="$(teamdb_exec_query "$DB" \
  "SELECT t.name FROM tags t JOIN memory_tags mt ON mt.tag_id=t.id WHERE mt.memory_table = ? AND mt.memory_id = ?" \
  "$TABLE" "$ID" 2>/dev/null || true)"
if [ "$tags" = "[]" ] || [ -z "$tags" ]; then
  echo "  (sin tags)"
else
  echo "$tags" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    for r in rows:
        v = list(r.values())[0] if r else ''
        if v:
            print('  •', v)
except Exception:
    pass
"
fi
echo ""

# Links out (este -> otros)
echo "➡️  ESTE → otros (link_type):"
links_out="$(teamdb_exec_query "$DB" "
  SELECT ml.link_type, ml.to_table, COALESCE(c.slug, d.slug, p.slug, kp.slug) AS to_slug
  FROM memory_links ml
  LEFT JOIN concepts c ON ml.to_table='concepts' AND c.id=ml.to_id
  LEFT JOIN decisions d ON ml.to_table='decisions' AND d.id=ml.to_id
  LEFT JOIN preferences p ON ml.to_table='preferences' AND p.id=ml.to_id
  LEFT JOIN known_problems kp ON ml.to_table='known_problems' AND kp.id=ml.to_id
  WHERE ml.from_table = ? AND ml.from_id = ?
" "$TABLE" "$ID" 2>/dev/null || true)"
if [ "$links_out" = "[]" ] || [ -z "$links_out" ]; then
  echo "  (nada)"
else
  echo "$links_out" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    for r in rows:
        v = list(r.values())
        if len(v) >= 3:
            print('  • %s → %s (%s)' % (v[0], v[1], v[2]))
except Exception:
    pass
"
fi
echo ""

# Links in (otros -> este)
echo "⬅️  otros → ESTE (link_type):"
links_in="$(teamdb_exec_query "$DB" "
  SELECT ml.link_type, ml.from_table, COALESCE(c.slug, d.slug, p.slug, kp.slug) AS from_slug
  FROM memory_links ml
  LEFT JOIN concepts c ON ml.from_table='concepts' AND c.id=ml.from_id
  LEFT JOIN decisions d ON ml.from_table='decisions' AND d.id=ml.from_id
  LEFT JOIN preferences p ON ml.from_table='preferences' AND p.id=ml.from_id
  LEFT JOIN known_problems kp ON ml.from_table='known_problems' AND kp.id=ml.from_id
  WHERE ml.to_table = ? AND ml.to_id = ?
" "$TABLE" "$ID" 2>/dev/null || true)"
if [ "$links_in" = "[]" ] || [ -z "$links_in" ]; then
  echo "  (nada)"
else
  echo "$links_in" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    for r in rows:
        v = list(r.values())
        if len(v) >= 3:
            print('  • %s → %s (%s)' % (v[0], v[1], v[2]))
except Exception:
    pass
"
fi
echo ""
