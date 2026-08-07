#!/usr/bin/env bash
# teamdb-deps.sh — DAG de dependencies + runnable query + cycle detection
# T-2.13
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

OP="${1:?Uso: teamdb-deps.sh <add|remove|show|runnable|list> <plan> [args] [project]}"
shift

case "$OP" in
  add)
    PLAN_SLUG="$1"; TASK_SLUG="$2"; DEPENDS_ON="$3"; PROJECT="${4:-$(pwd)}"
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[ERROR] DB no existe" >&2; exit 1; }

    PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
    [ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado: $PLAN_SLUG" >&2; exit 1; }

    TASK_ID="$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$TASK_SLUG")"
    [ -n "$TASK_ID" ] || { echo "[ERROR] task no encontrada: $TASK_SLUG" >&2; exit 1; }

    DEP_ID="$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$DEPENDS_ON")"
    [ -n "$DEP_ID" ] || { echo "[ERROR] dependency task no encontrada: $DEPENDS_ON" >&2; exit 1; }

    [ "$TASK_ID" != "$DEP_ID" ] || { echo "[ERROR] self-dependency no permitida" >&2; exit 1; }

    # Cycle detection via Python DFS
    HAS_CYCLE="$(python3 - "$DB" "$TASK_ID" "$DEP_ID" <<'PYEOF'
import sqlite3, sys
db, task_id, dep_id = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
conn = sqlite3.connect(db)
edges = {}
for row in conn.execute("SELECT task_id, depends_on_task_id FROM task_dependencies"):
    edges.setdefault(row[0], []).append(row[1])

def reaches(start, end):
    visited = set()
    stack = [start]
    while stack:
        n = stack.pop()
        if n == end:
            return True
        if n in visited:
            continue
        visited.add(n)
        stack.extend(edges.get(n, []))
    return False

# Si DEP_ID puede llegar a TASK_ID con la nueva arista TASK_ID->DEP_ID, hay ciclo
if reaches(dep_id, task_id):
    print("CYCLE")
else:
    print("OK")
PYEOF
)"
    if [ "$HAS_CYCLE" != "OK" ]; then
      echo "[ERROR] ciclo detectado: agregar $TASK_SLUG -> $DEPENDS_ON cerraría el DAG" >&2
      exit 4
    fi

    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    teamdb_exec_write "$DB" \
      "INSERT INTO task_dependencies(task_id, depends_on_task_id, type, created_at) VALUES(?, ?, 'blocks', ?)" \
      "$TASK_ID" "$DEP_ID" "$NOW" >/dev/null
    echo "added: $TASK_SLUG depends on $DEPENDS_ON"
    ;;

  remove)
    PLAN_SLUG="$1"; TASK_SLUG="$2"; DEPENDS_ON="$3"; PROJECT="${4:-$(pwd)}"
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[ERROR] DB no existe" >&2; exit 1; }
    PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
    TASK_ID="$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$TASK_SLUG")"
    DEP_ID="$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$DEPENDS_ON")"
    teamdb_exec_write "$DB" \
      "DELETE FROM task_dependencies WHERE task_id = ? AND depends_on_task_id = ?" \
      "$TASK_ID" "$DEP_ID" >/dev/null
    echo "removed: $TASK_SLUG no longer depends on $DEPENDS_ON"
    ;;

  runnable)
    PLAN_SLUG="$1"; PROJECT="${2:-$(pwd)}"
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[ERROR] DB no existe" >&2; exit 1; }
    PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
    [ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado" >&2; exit 1; }
    teamdb_exec_query "$DB" "
      SELECT t.slug, t.title, t.status
      FROM tasks t
      WHERE t.plan_id = ? AND t.status = 'pending'
        AND NOT EXISTS (
          SELECT 1 FROM task_dependencies d
          JOIN tasks dep ON dep.id = d.depends_on_task_id
          WHERE d.task_id = t.id AND dep.status NOT IN ('approved', 'resolved')
        )
      ORDER BY t.order_index
    " "$PLAN_ID"
    ;;

  show)
    PLAN_SLUG="$1"; PROJECT="${2:-$(pwd)}"
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[ERROR] DB no existe" >&2; exit 1; }
    PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
    [ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado" >&2; exit 1; }
    teamdb_exec_query "$DB" "
      SELECT t.slug, COALESCE(dep.slug, '(root)') AS depends_on, d.type
      FROM tasks t
      LEFT JOIN task_dependencies d ON d.task_id = t.id
      LEFT JOIN tasks dep ON dep.id = d.depends_on_task_id
      WHERE t.plan_id = ?
      ORDER BY t.order_index, d.id
    " "$PLAN_ID"
    ;;

  list)
    PLAN_SLUG="$1"; PROJECT="${2:-$(pwd)}"
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[ERROR] DB no existe" >&2; exit 1; }
    PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$PLAN_SLUG")"
    [ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado" >&2; exit 1; }
    teamdb_exec_query "$DB" "
      SELECT t.slug, GROUP_CONCAT(dep.slug, ',') AS depends_on
      FROM tasks t
      LEFT JOIN task_dependencies d ON d.task_id = t.id
      LEFT JOIN tasks dep ON dep.id = d.depends_on_task_id
      WHERE t.plan_id = ?
      GROUP BY t.id, t.slug, t.order_index
      ORDER BY t.order_index
    " "$PLAN_ID"
    ;;

  *)
    echo "Uso: teamdb-deps.sh <add|remove|show|runnable|list> <plan> [args] [project]" >&2
    exit 2
    ;;
esac
