#!/usr/bin/env bash
# teamdb-link.sh — Auto-enlazar memoria en grafo de teamdb
# Reglas:
#   R1 related      — conceptos que comparten categoría
#   R2 related      — conceptos/decisiones que comparten tag (same_table: related, cross_table: same_tag)
#   R3 uses         — concepto no-stack -> concepto de categoría 'stack'
#   R4 part_of      — WIP hijo (feature/task) -> WIP padre (plan/feature)
#   R5 references   — decisión -> concept cuando body_md menciona el slug del concept
# Idempotente (no duplica links). Usa teamdb_write_project (audit + parámetros).
# Flags:
#   --dry-run   solo muestra conteos, no escribe nada
#   --quiet     suprime output decorativo (errores se siguen mostrando)
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

PROJECT="${PROJECT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Lock file para evitar race conditions entre agentes
LOCK_DIR="$PROJECT/.opencode/context"
LOCK_FILE="$LOCK_DIR/team.lock"
mkdir -p "$LOCK_DIR" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" 2>/dev/null || true
  flock -w 10 9 || { echo "ERROR: no se pudo obtener lock en $LOCK_FILE" >&2; exit 1; }
fi
trap 'exec 9>&- 2>/dev/null' EXIT


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
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --quiet) QUIET=1; shift ;;
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
part_of_before="$(count_type part_of)"
references_before="$(count_type references)"
same_tag_before="$(count_type same_tag)"

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

SQL_R4=$(cat <<'SQL'
INSERT INTO memory_links(from_table, from_id, to_table, to_id, link_type, confidence)
SELECT 'work_in_progress', child.id, 'work_in_progress', parent.id, 'part_of', 1.0
FROM work_in_progress child
JOIN work_in_progress parent ON child.parent_id = parent.id
WHERE child.type IN ('feature', 'task')
  AND child.parent_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM memory_links ml
    WHERE ml.from_table='work_in_progress' AND ml.from_id=child.id
      AND ml.to_table='work_in_progress' AND ml.to_id=parent.id
      AND ml.link_type='part_of'
  )
SQL
)

SQL_R5=$(cat <<'SQL'
INSERT INTO memory_links(from_table, from_id, to_table, to_id, link_type, confidence)
SELECT 'decisions', d.id, 'concepts', c.id, 'references', 0.9
FROM decisions d, concepts c
WHERE d.body_md IS NOT NULL
  AND d.body_md LIKE '%' || c.slug || '%'
  AND NOT EXISTS (
    SELECT 1 FROM memory_links ml
    WHERE ml.from_table='decisions' AND ml.from_id=d.id
      AND ml.to_table='concepts' AND ml.to_id=c.id
      AND ml.link_type='references'
  )
SQL
)

out() {
  [ "$QUIET" = "1" ] || echo "$@"
}

report() {
  local rule="$1" before="$2" after="$3"
  if [ "$after" -gt "$before" ]; then
    out "  $rule: +$((after - before)) links ($before -> $after)"
  else
    out "  $rule: sin cambios ($after)"
  fi
}

out "🔗 Enlazando memoria en $DB"
out "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$DRY_RUN" = "1" ]; then
  out "  (dry-run: no se escribe nada)"
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
  part_of_before="$(count_type part_of)"
  TEAMDB_ACTOR="skalling-link" teamdb_write_project "$DB" "$SQL_R4"
  report "part_of (WIP -> parent)" "$part_of_before" "$(count_type part_of)"
  references_before="$(count_type references)"
  TEAMDB_ACTOR="skalling-link" teamdb_write_project "$DB" "$SQL_R5"
  report "references (decision -> concept)" "$references_before" "$(count_type references)"
else
  out "  related (categoría): $related_before existentes"
  out "  related (tags): $(count_type related) existentes"
  out "  uses (-> stack): $uses_before existentes"
  out "  part_of (WIP -> parent): $part_of_before existentes"
  out "  references (decision -> concept): $references_before existentes"
fi

out ""
out "Grafo: bash $(dirname "$0")/teamdb-graph.sh \"$PROJECT\" text"
