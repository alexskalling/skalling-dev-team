#!/usr/bin/env bash
# teamdb-search.sh — Búsqueda amigable en teamdb (T-2.10: bound-param via teamdb_exec_query)
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

PROJECT="${PROJECT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Lock file para evitar race conditions entre agentes
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

# SQLite WAL readers do not need the team's exclusive writer lock.
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "DB no existe: $DB" >&2; exit 1; }
python3 - "$DB" "$QUERY" "$TYPE" <<'PYEOF'
import re, sqlite3, sys
from pathlib import Path
path, query, kind = sys.argv[1:]
conn = sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True, timeout=5)
# Quote each literal token: punctuation and FTS operators cannot alter grammar.
terms = re.findall(r"[^\W_]+", query, re.UNICODE)[:24]
fts = ' AND '.join('"' + term.replace('"', '""') + '"*' for term in terms)
like = '%' + query.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%'
print(f"🔍 Buscando '{query}' (tipo: {kind})\n")
tables = {
    'concepts': ('concepts', 'concepts_fts', 'title', 'body_md', '📦 CONCEPTS'),
    'decisions': ('decisions', 'decisions_fts', 'title', 'body_md', '📋 DECISIONS'),
    'preferences': ('preferences', None, 'scope', 'body_md', '⚙️  PREFERENCES'),
    'problems': ('known_problems', 'problems_fts', 'title', "coalesce(symptom_md,'') || ' ' || coalesce(workaround_md,'')", '⚠️  PROBLEMAS'),
    'wip': ('work_in_progress', 'wip_fts', 'title', 'title', '🚧 WIP'),
}
try:
    conn.execute('BEGIN')  # One consistent read snapshot for all result groups.
    existing = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for key, (table, index, title, body, label) in tables.items():
        if kind not in ('all', key):
            continue
        if index in existing and fts:
            rows = conn.execute(f'SELECT m.slug,m.{title} FROM {index} JOIN {table} m ON m.id={index}.rowid '
                                f'WHERE {index} MATCH ? ORDER BY bm25({index}),m.slug LIMIT 10', (fts,)).fetchall()
        else:
            rows = conn.execute(f"SELECT slug,{title} FROM {table} WHERE {title} LIKE ? ESCAPE '\\' "
                                f"OR ({body}) LIKE ? ESCAPE '\\' ORDER BY slug LIMIT 10", (like, like)).fetchall()
        print(label + ':')
        for slug, title in rows:
            print(f'  • [{slug}] {title or ""}')
        print()
finally:
    conn.close()
PYEOF
