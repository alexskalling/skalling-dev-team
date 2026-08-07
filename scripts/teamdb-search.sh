#!/usr/bin/env bash
# teamdb-search.sh — Búsqueda amigable en teamdb (T-2.10: bound-param via teamdb_exec_query)
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

QUERY="${1:-}"
ARG2="${2:-}"
ARG3="${3:-}"

VALID_TYPES="all concepts decisions preferences problems wip"

if [ -z "$ARG2" ]; then
  TYPE="all"
  PROJECT="$(pwd)"
elif echo " $VALID_TYPES " | grep -q " $ARG2 "; then
  TYPE="$ARG2"
  PROJECT="${ARG3:-$(pwd)}"
else
  TYPE="all"
  PROJECT="$ARG2"
fi

if [ -z "$QUERY" ]; then
  echo "Uso: bash teamdb-search.sh <query> [type] [project]"
  echo ""
  echo "Tipos: all, concepts, decisions, preferences, problems, wip"
  echo ""
  echo "Ejemplos:"
  echo "  bash teamdb-search.sh 'JWT'"
  echo "  bash teamdb-search.sh 'auth' concepts"
  echo "  bash teamdb-search.sh 'refresh' decisions /ruta/al/proyecto"
  exit 1
fi

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }

echo "🔍 Buscando '$QUERY' (tipo: $TYPE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Detectar si problems_fts existe (FTS5 disponible)
HAS_PROBLEMS_FTS=""
if teamdb_has_table "$DB" problems_fts; then
  HAS_PROBLEMS_FTS=1
fi

# render_rows: convierte JSON array de teamdb_exec_query a texto human-readable
render_rows() {
  local label="$1"
  local rows_json="$2"
  [ -n "$rows_json" ] || return
  echo "$label:"
  echo "$rows_json" | python3 -c "
import json, sys
try:
    rows = json.loads(sys.stdin.read())
    for r in rows:
        vals = list(r.values())
        if len(vals) >= 2:
            print('  • [%s] %s' % (vals[0], vals[1]))
        elif len(vals) == 1:
            print('  • %s' % vals[0])
except Exception as e:
    pass
"
  echo ""
}

# Para FTS5, construir el query con el operador * (prefijo) para búsqueda parcial.
# FTS5 requiere sanitización básica de caracteres especiales del query del usuario.
fts_query="$(printf '%s' "$QUERY" | sed 's/[\\"]//g' | tr -d '^*()[]{}:' | sed 's/  */ /g; s/^ *//; s/ *$//')"
# Si quedó vacío, no hacer match
[ -z "$fts_query" ] && fts_query='""'

# LIKE pattern: escapar % y _ (caracteres wildcards de LIKE)
like_query="$(printf '%s' "$QUERY" | sed 's/[%_]/\\&/g')"

if [ "$TYPE" = "all" ] || [ "$TYPE" = "concepts" ]; then
  rows="$(teamdb_exec_query "$DB" \
    "SELECT slug, title || ' (' || COALESCE(category, '') || ')' AS label FROM concepts WHERE id IN (SELECT rowid FROM concepts_fts WHERE concepts_fts MATCH ?) ORDER BY updated_at DESC LIMIT 10" \
    "${fts_query}*")"
  render_rows "📦 CONCEPTS:" "$rows"
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "decisions" ]; then
  rows="$(teamdb_exec_query "$DB" \
    "SELECT slug, title || ' (' || COALESCE(status, '') || ')' AS label FROM decisions WHERE id IN (SELECT rowid FROM decisions_fts WHERE decisions_fts MATCH ?) ORDER BY decided_at DESC LIMIT 10" \
    "${fts_query}*")"
  render_rows "📋 DECISIONS:" "$rows"
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "preferences" ]; then
  rows="$(teamdb_exec_query "$DB" \
    "SELECT slug, '(' || COALESCE(scope, '') || ')' AS label FROM preferences WHERE body_md LIKE '%' || ? || '%' ESCAPE '\\' LIMIT 10" \
    "$like_query")"
  render_rows "⚙️  PREFERENCES:" "$rows"
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "problems" ]; then
  if [ -n "$HAS_PROBLEMS_FTS" ]; then
    rows="$(teamdb_exec_query "$DB" \
      "SELECT slug, title || ' (' || COALESCE(status, '') || ')' AS label FROM known_problems WHERE id IN (SELECT rowid FROM problems_fts WHERE problems_fts MATCH ?) ORDER BY discovered_at DESC LIMIT 10" \
      "${fts_query}*")"
  else
    rows="$(teamdb_exec_query "$DB" \
      "SELECT slug, title || ' (' || COALESCE(status, '') || ')' AS label FROM known_problems WHERE title LIKE '%' || ? || '%' ESCAPE '\\' OR symptom_md LIKE '%' || ? || '%' ESCAPE '\\' OR workaround_md LIKE '%' || ? || '%' ESCAPE '\\' LIMIT 10" \
      "$like_query" "$like_query" "$like_query")"
  fi
  render_rows "⚠️  PROBLEMAS:" "$rows"
fi

if [ "$TYPE" = "all" ] || [ "$TYPE" = "wip" ]; then
  rows="$(teamdb_exec_query "$DB" \
    "SELECT slug, status || ' (@' || COALESCE(owner, '') || ')' AS label FROM work_in_progress WHERE id IN (SELECT rowid FROM wip_fts WHERE wip_fts MATCH ?) OR title LIKE '%' || ? || '%' ESCAPE '\\' LIMIT 10" \
    "${fts_query}*" "$like_query")"
  render_rows "🚧 WIP:" "$rows"
fi
