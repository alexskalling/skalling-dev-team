#!/usr/bin/env bash
# teamdb-link.sh — Auto-enlazar memoria en grafo de teamdb
# Reglas:
#   R1 related  — conceptos que comparten categoría
#   R2 related  — conceptos/decisiones que comparten tag
#   R3 uses     — concepto no-stack -> concepto de categoría 'stack'
# Idempotente (no duplica links). Usa teamdb_write_project (audit + parámetros).
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

PROJECT="$(pwd)"
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) PROJECT="$1"; shift ;;
  esac
done

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB (corre teamdb-init primero)" >&2; exit 1; }

count_type() {
  sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links WHERE link_type = '$1'"
}

related_before="$(count_type related)"
uses_before="$(count_type uses)"

SQL_R1=$(cat <<'SQL'
INSERT INTO memory_links(from_table, from_id, to_table, to_id, link_type, confidence)
SELECT 'concepts', a.id, 'concepts', b.id, 'related', 1.0
FROM concepts a
JOIN concepts b ON a.category = b.category AND a.category IS NOT NULL AND a.id < b.id
WHERE NOT EXISTS (
  SELECT 1 FROM memory_links ml
  WHERE ml.from_table='concepts' AND ml.from_id=a.id
    AND ml.to_table='concepts' AND ml.to_id=b.id AND ml.link_type='related'
)
SQL
)

SQL_R2=$(cat <<'SQL'
INSERT INTO memory_links(from_table, from_id, to_table, to_id, link_type, confidence)
SELECT a.memory_table, a.memory_id, b.memory_table, b.memory_id, 'related', 0.8
FROM memory_tags a
JOIN memory_tags b ON a.tag_id = b.tag_id
  AND (a.memory_table, a.memory_id) < (b.memory_table, b.memory_id)
WHERE a.memory_table IN ('concepts','decisions')
  AND b.memory_table IN ('concepts','decisions')
  AND NOT EXISTS (
    SELECT 1 FROM memory_links ml
    WHERE ml.from_table=a.memory_table AND ml.from_id=a.memory_id
      AND ml.to_table=b.memory_table AND ml.to_id=b.memory_id AND ml.link_type='related'
  )
SQL
)

SQL_R3=$(cat <<'SQL'
INSERT INTO memory_links(from_table, from_id, to_table, to_id, link_type, confidence)
SELECT 'concepts', m.id, 'concepts', s.id, 'uses', 1.0
FROM concepts m
JOIN concepts s ON s.category = 'stack' AND s.category IS NOT NULL
WHERE (m.category IS NULL OR m.category <> 'stack')
AND NOT EXISTS (
  SELECT 1 FROM memory_links ml
  WHERE ml.from_table='concepts' AND ml.from_id=m.id
    AND ml.to_table='concepts' AND ml.to_id=s.id AND ml.link_type='uses'
)
SQL
)

report() {
  local rule="$1" before="$2" after="$3"
  if [ "$after" -gt "$before" ]; then
    echo "  $rule: +$((after - before)) links ($before -> $after)"
  else
    echo "  $rule: sin cambios ($after)"
  fi
}

echo "🔗 Enlazando memoria en $DB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$DRY_RUN" = "1" ]; then
  echo "  (dry-run: no se escribe nada)"
fi

if [ "$DRY_RUN" = "0" ]; then
  TEAMDB_ACTOR="skalling-link" teamdb_write_project "$DB" "$SQL_R1"
  report "related (categoría)" "$related_before" "$(count_type related)"
  related_before="$(count_type related)"
  TEAMDB_ACTOR="skalling-link" teamdb_write_project "$DB" "$SQL_R2"
  report "related (tags)" "$related_before" "$(count_type related)"
  uses_before="$(count_type uses)"
  TEAMDB_ACTOR="skalling-link" teamdb_write_project "$DB" "$SQL_R3"
  report "uses (-> stack)" "$uses_before" "$(count_type uses)"
else
  echo "  related (categoría): $related_before existentes"
  echo "  related (tags): $(count_type related) existentes"
  echo "  uses (-> stack): $uses_before existentes"
fi

echo ""
echo "Grafo: bash $(dirname "$0")/teamdb-graph.sh \"$PROJECT\" text"
