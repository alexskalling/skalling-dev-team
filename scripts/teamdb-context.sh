#!/usr/bin/env bash
# teamdb-context.sh — Context capsule (selección filtrada) para handoff de Teo
# T-2.16
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
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

usage() {
  cat <<EOF
Uso:
  teamdb-context.sh link <plan> <task> --concepts=c1,c2 [--decisions=d1,d2] [--preferences=p1] [--problems=k1,k2] [project]
  teamdb-context.sh for-task <plan> <task> [project]

Subcomandos:
  link     Asocia memoria (concepts/decisions/preferences/known_problems) a una task
  for-task Emite la cápsula JSON con task + plan + memoria filtrada
EOF
  exit 2
}

OP="${1:-}"
[ -z "$OP" ] && usage
shift

case "$OP" in
  link)
    PLAN_SLUG="$1"; TASK_SLUG="$2"; shift 2
    PROJECT=""
    CONCEPTS=""
    DECISIONS=""
    PREFS=""
    PROBS=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --concepts=*) CONCEPTS="${CONCEPTS:+$CONCEPTS,}${1#--concepts=}" ;;
        --decisions=*) DECISIONS="${DECISIONS:+$DECISIONS,}${1#--decisions=}" ;;
        --preferences=*) PREFS="${PREFS:+$PREFS,}${1#--preferences=}" ;;
        --problems=*) PROBS="${PROBS:+$PROBS,}${1#--problems=}" ;;
        --help|-h) usage ;;
        -*) echo "[ERROR] argumento desconocido: $1" >&2; exit 2 ;;
        *) PROJECT="$1" ;;
      esac
      shift || break
    done
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[ERROR] DB no existe" >&2; exit 1; }
    PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
    [ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado: $PLAN_SLUG" >&2; exit 1; }
    TASK_ID="$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$TASK_SLUG")"
    [ -n "$TASK_ID" ] || { echo "[ERROR] task no encontrada: $TASK_SLUG" >&2; exit 1; }

    insert_capsule() {
      local table="$1"; local slug="$2"
      local mid
      mid="$(teamdb_exec_value "$DB" "SELECT id FROM $table WHERE slug = ?" "$slug")"
      [ -n "$mid" ] || { echo "[WARN] $table/$slug no existe" >&2; return 0; }
      teamdb_exec_write "$DB" \
        "INSERT OR IGNORE INTO task_context_capsules(task_id, memory_table, memory_id, relevance) VALUES(?, ?, ?, 1)" \
        "$TASK_ID" "$table" "$mid" >/dev/null
    }

    if [ -n "$CONCEPTS" ]; then
      IFS=',' read -ra CL <<< "$CONCEPTS"
      for s in "${CL[@]}"; do [ -n "$s" ] && insert_capsule "concepts" "$s"; done
    fi
    if [ -n "$DECISIONS" ]; then
      IFS=',' read -ra DL <<< "$DECISIONS"
      for s in "${DL[@]}"; do [ -n "$s" ] && insert_capsule "decisions" "$s"; done
    fi
    if [ -n "$PREFS" ]; then
      IFS=',' read -ra PL <<< "$PREFS"
      for s in "${PL[@]}"; do [ -n "$s" ] && insert_capsule "preferences" "$s"; done
    fi
    if [ -n "$PROBS" ]; then
      IFS=',' read -ra BL <<< "$PROBS"
      for s in "${BL[@]}"; do [ -n "$s" ] && insert_capsule "known_problems" "$s"; done
    fi
    echo "linked: task=$TASK_SLUG"
    ;;

  for-task)
    PLAN_SLUG="$1"; TASK_SLUG="$2"; shift 2
    PROJECT=""
    TOP_K=8
    MAX_BYTES=8000
    DISCOVER=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --top-k=*) TOP_K="${1#--top-k=}" ;;
        --max-bytes=*) MAX_BYTES="${1#--max-bytes=}" ;;
        --discover) DISCOVER=1 ;;
        --help|-h) usage ;;
        -*) echo "[ERROR] argumento desconocido: $1" >&2; exit 2 ;;
        *) PROJECT="$1" ;;
      esac
      shift || break
    done
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[]" ; exit 0; }
    python3 - "$DB" "$PLAN_SLUG" "$TASK_SLUG" "$TOP_K" "$MAX_BYTES" "$DISCOVER" <<'PYEOF'
import sqlite3, sys, json, re
db, plan_slug, task_slug = sys.argv[1], sys.argv[2], sys.argv[3]
top_k = int(sys.argv[4])
max_bytes = int(sys.argv[5])
discover = sys.argv[6] == '1'
conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row

plan = conn.execute("SELECT id, slug, title FROM plans WHERE slug = ?", (plan_slug,)).fetchone()
if not plan:
    print(json.dumps({'concepts': [], 'decisions': [], 'preferences': [], 'known_problems': [], 'task': None, 'plan': None}, ensure_ascii=False))
    sys.exit(0)
task = conn.execute("""
    SELECT id, slug, title, description_md, acceptance_md, status
    FROM tasks WHERE plan_id = ? AND slug = ?
""", (plan['id'], task_slug)).fetchone()
if not task:
    print(json.dumps({'concepts': [], 'decisions': [], 'preferences': [], 'known_problems': [], 'task': None, 'plan': {'slug': plan['slug'], 'title': plan['title']}}, ensure_ascii=False))
    sys.exit(0)

# Per-tabla: columnas de texto a buscar, filtro de status, campo body.
# (tabla, col_slug, col_title, col_body, filtro_status_sql, status_ok_lambda)
TABLES = {
    'concepts': ('concepts', 'slug', 'title', 'body_md', None),
    'decisions': ('decisions', 'slug', 'title', 'body_md', "status = 'accepted'"),
    'preferences': ('preferences', 'slug', 'scope', 'body_md', None),
    'known_problems': ('known_problems', 'slug', 'title', 'symptom_md', "status != 'wontfix'"),
}

def table_entry(tbl_key, mid, relevance, provenance):
    t = TABLES[tbl_key]
    row = conn.execute("SELECT %s, %s, %s FROM %s WHERE id = ?" % (t[1], t[2], t[3], t[0]), (mid,)).fetchone()
    if not row:
        return None
    obj = {'slug': row[0], 'title': row[1] if row[1] is not None else '', 'relevance': relevance, 'provenance': provenance}
    body = row[2]
    if body:
        obj['body_md'] = body[:500]
    return obj

budget = {'bytes': 0}

def fits_size(obj):
    size = len(json.dumps(obj, ensure_ascii=False))
    if budget['bytes'] + size > max_bytes:
        return False
    budget['bytes'] += size
    return True

result = {'concepts': [], 'decisions': [], 'preferences': [], 'known_problems': []}

# 1. Capsules linkeadas (provenance='linked'), ordenadas por relevance DESC
linked = conn.execute("""
    SELECT memory_table, memory_id, relevance, provenance
    FROM task_context_capsules
    WHERE task_id = ?
    ORDER BY relevance DESC, memory_table, memory_id
""", (task['id'],)).fetchall()

for row in linked:
    tbl_key = row['memory_table']
    if tbl_key not in TABLES:
        continue
    if len(result[tbl_key]) >= top_k:
        continue
    t = TABLES[tbl_key]
    if t[4]:
        ok = conn.execute("SELECT 1 FROM %s WHERE id = ? AND %s" % (t[0], t[4]), (row['memory_id'],)).fetchone()
        if not ok:
            continue
    obj = table_entry(tbl_key, row['memory_id'], row['relevance'], row['provenance'] or 'linked')
    if obj and fits_size(obj):
        result[tbl_key].append(obj)

# 2. Auto-discovery opcional: términos del title+description de la task
#    Busquedas LIKE con bound params (sin cargar tablas completas).
if discover:
    haystack = ((task['title'] or '') + ' ' + (task['description_md'] or '')).lower()
    terms = [t for t in re.findall(r"[a-z0-9]{3,}", haystack)]
    if terms:
        seen = {k: set(e['slug'] for e in v) for k, v in result.items()}
        for tbl_key, t in TABLES.items():
            like_clauses = []
            params = []
            for term in terms:
                like_clauses.append("(LOWER(%s) LIKE ? OR LOWER(%s) LIKE ?)" % (t[2], t[3]))
                params.append('%' + term + '%')
                params.append('%' + term + '%')
            sql = "SELECT id, %s, %s, %s FROM %s WHERE %s" % (t[1], t[2], t[3], t[0], ' OR '.join(like_clauses))
            if t[4]:
                sql += " AND " + t[4]
            hits = conn.execute(sql, params).fetchall()
            scored = []
            for h in hits:
                if h[1] in seen[tbl_key]:
                    continue
                text = ((h[1] or '') + ' ' + (h[2] or '')).lower()
                rel = sum(1 for term in terms if term in text)
                if rel > 0:
                    scored.append((rel, h[0], h[1], h[2], h[3]))
            scored.sort(key=lambda x: (-x[0], x[2]))
            for rel, mid, tslug, title_col, body_col in scored:
                if len(result[tbl_key]) >= top_k:
                    break
                obj = {'slug': tslug, 'relevance': rel, 'provenance': 'discovered'}
                if t[2] == 'scope':
                    obj['title'] = tslug
                else:
                    obj['title'] = title_col or tslug
                if body_col:
                    obj['body_md'] = body_col[:500]
                if fits_size(obj):
                    result[tbl_key].append(obj)

output = {
    'task': {
        'slug': task['slug'],
        'title': task['title'],
        'status': task['status'],
        'description_md': task['description_md'],
        'acceptance_md': task['acceptance_md'],
    },
    'plan': {'slug': plan['slug'], 'title': plan['title']},
}
output.update(result)
print(json.dumps(output, indent=2, default=str))
PYEOF
    ;;

  *)
    usage
    ;;
esac
