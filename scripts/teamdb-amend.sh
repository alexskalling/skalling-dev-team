#!/usr/bin/env bash
# teamdb-amend.sh — Amendment in-place real con version + history + preservación de aprobadas
# T-2.12
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

PROJECT="${PROJECT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
# Source lib-teamdb.sh ANTES del lock (teamdb_lock vive en lib-teamdb.sh). v0.8.3
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  . "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

# Lock cross-platform (mkdir-based, sin flock). v0.8.3
# Se aplica DESPUÉS del parsing de $PROJECT (posicional o env). v0.8.3
usage() {
  cat <<EOF
Uso: teamdb-amend.sh <plan-slug> [opciones] [project]

Operaciones (excluyentes):
  --add-task "<title>"                       crea una nueva task
  --modify-task=<slug> --new-title="<title>"  modifica título de task
  --deprecate-task=<slug>                    marca task como superseded (soft-delete)
  --show                                     muestra el historial de amendments

Otros:
  --by <actor>                               actor (default: TEAMDB_ACTOR o 'sol')
  --purpose <text>                           purpose obligatorio al --add-task (v0.7.7 Bloque 2)
  --acceptance <text>                        acceptance_md opcional al --add-task

El plan no debe tener status 'completed' o 'abandoned' para ser amendable.
Las tasks en status 'approved', 'resolved', 'in_progress' o 'in_review' son
inmutables. Para "cambiar" una task aprobada, crear una sucesora con --add-task
y marcarla con la dependencia correcta via teamdb-deps.sh.
EOF
  exit 2
}

[ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && usage

SLUG="${1:?Falta slug del plan}"
shift

OP=""
NEW_TITLE=""
TARGET_TASK=""
ACTOR=""
PROJECT=""
SHOW="0"
PURPOSE=""
ACCEPTANCE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --add-task) OP="add" ;;
    --add-task=*) OP="add"; NEW_TITLE="${1#--add-task=}" ;;
    --modify-task=*) OP="modify"; TARGET_TASK="${1#--modify-task=}" ;;
    --new-title=*) NEW_TITLE="${1#--new-title=}" ;;
    --deprecate-task=*) OP="deprecate"; TARGET_TASK="${1#--deprecate-task=}" ;;
    --by=*) ACTOR="${1#--by=}" ;;
    --by) shift; ACTOR="${1:-}" ;;
    --purpose=*) PURPOSE="${1#--purpose=}" ;;
    --purpose) shift; PURPOSE="${1:-}" ;;
    --acceptance=*) ACCEPTANCE="${1#--acceptance=}" ;;
    --acceptance) shift; ACCEPTANCE="${1:-}" ;;
    --show) SHOW="1" ;;
    -*) echo "[ERROR] opción desconocida: $1" >&2; exit 2 ;;
    *) PROJECT="$1" ;;
  esac
  shift || break
done

[ -d "$PROJECT" ] || PROJECT="$(pwd)"

# Lock cross-platform (mkdir-based, sin flock). v0.8.3
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "[ERROR] DB no existe: $DB" >&2; exit 1; }

# Modo --show
if [ "$SHOW" = "1" ]; then
  python3 - "$DB" "$SLUG" <<'PYEOF'
import sqlite3, sys, json
db, slug = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
plan = conn.execute("SELECT id FROM plans WHERE slug=?", (slug,)).fetchone()
if not plan:
    print("[]"); sys.exit(0)
rows = conn.execute("""
    SELECT version, changed_by, changed_at, operation, diff_md
    FROM plan_history WHERE plan_id=? ORDER BY version ASC
""", (plan['id'],)).fetchall()
for r in rows:
    print(f"v{r['version']:>3} {r['changed_at']} {r['changed_by']:>10} {r['operation']:>10}  {r['diff_md'] or ''}")
PYEOF
  exit 0
fi

[ -n "$OP" ] || usage

PLAN_ID="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug = ?" "$SLUG")"
[ -n "$PLAN_ID" ] || { echo "[ERROR] plan no encontrado: $SLUG" >&2; exit 1; }

# Validar que plan no esté completed/abandoned
PLAN_STATUS="$(teamdb_exec_value "$DB" "SELECT status FROM plans WHERE id = ?" "$PLAN_ID")"
case "$PLAN_STATUS" in
  completed|abandoned)
    echo "[ERROR] plan $SLUG está $PLAN_STATUS, no amendable" >&2
    exit 1
    ;;
esac

ACTOR="${ACTOR:-${TEAMDB_ACTOR:-sol}}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Snapshot ANTES del cambio
SNAPSHOT="$(teamdb_exec_value "$DB" "SELECT json_group_array(json_object('slug',slug,'status',status,'title',title)) FROM tasks WHERE plan_id = ?" "$PLAN_ID")"
NEW_VERSION="$(teamdb_exec_value "$DB" "SELECT COALESCE(MAX(version)+1, 1) FROM plan_history WHERE plan_id = ?" "$PLAN_ID")"

case "$OP" in
  add)
    TITLE="$NEW_TITLE"
    [ -n "$TITLE" ] || { echo "[ERROR] --add-task requiere título" >&2; exit 2; }
    # Bloque 2 v0.7.7: contract enforcement — purpose obligatorio al --add-task
    if [ -z "$PURPOSE" ]; then
      echo "[ERROR] --add-task requiere --purpose (1-2 frases: por qué existe la task). v0.7.7 Bloque 2." >&2
      exit 2
    fi
    NEW_TASK_SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//;s/--*/-/g')"
    [ -z "$NEW_TASK_SLUG" ] && NEW_TASK_SLUG="task-$NEW_VERSION"
    EXISTING="$(teamdb_exec_value "$DB" "SELECT id FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$NEW_TASK_SLUG")"
    if [ -n "$EXISTING" ]; then
      NEW_TASK_SLUG="${NEW_TASK_SLUG}-${NEW_VERSION}"
    fi
    NEXT_ORDER="$(teamdb_exec_value "$DB" "SELECT COALESCE(MAX(order_index)+1, 1) FROM tasks WHERE plan_id = ?" "$PLAN_ID")"
    TASK_SQL="INSERT INTO tasks(plan_id,slug,title,purpose,acceptance_md,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,?,?,'pending',2,?,?,?,?)"
    TASK_PARAMS_JSON="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$PLAN_ID" "$NEW_TASK_SLUG" "$TITLE" "$PURPOSE" "$ACCEPTANCE" "$NEXT_ORDER" "$ACTOR" "$NOW" "$NOW")"
    TARGET_TASK="$NEW_TASK_SLUG"
    HIST_OP="amended"
    DIFF="add task: $NEW_TASK_SLUG (purpose: ${PURPOSE:0:60})"
    ;;
  modify)
    [ -n "$TARGET_TASK" ] || { echo "[ERROR] --modify-task requiere slug" >&2; exit 2; }
    [ -n "$NEW_TITLE" ] || { echo "[ERROR] --modify-task requiere --new-title" >&2; exit 2; }
    CURRENT="$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$TARGET_TASK")"
    [ -n "$CURRENT" ] || { echo "[ERROR] task $TARGET_TASK no encontrada en plan $SLUG" >&2; exit 1; }
    case "$CURRENT" in
      approved|resolved|rejected|blocked|in_progress|in_review)
        echo "[ERROR] task $TARGET_TASK está en status=$CURRENT (inmutable). Crear sucesora con --add-task + --deprecate-task." >&2
        exit 3
        ;;
    esac
    TASK_SQL="UPDATE tasks SET title = ?, updated_at = ? WHERE plan_id = ? AND slug = ?"
    TASK_PARAMS_JSON="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$NEW_TITLE" "$NOW" "$PLAN_ID" "$TARGET_TASK")"
    HIST_OP="amended"
    DIFF="modify $TARGET_TASK: title -> $NEW_TITLE"
    ;;
  deprecate)
    [ -n "$TARGET_TASK" ] || { echo "[ERROR] --deprecate-task requiere slug" >&2; exit 2; }
    CURRENT="$(teamdb_exec_value "$DB" "SELECT status FROM tasks WHERE plan_id = ? AND slug = ?" "$PLAN_ID" "$TARGET_TASK")"
    [ -n "$CURRENT" ] || { echo "[ERROR] task $TARGET_TASK no encontrada en plan $SLUG" >&2; exit 1; }
    case "$CURRENT" in
      approved|resolved|rejected|blocked)
        echo "[ERROR] task $TARGET_TASK está en status=$CURRENT (inmutable para deprecate)." >&2
        exit 3
        ;;
    esac
    TASK_SQL="UPDATE tasks SET resolution_md = ?, status = 'rejected', updated_at = ? WHERE plan_id = ? AND slug = ?"
    TASK_PARAMS_JSON="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "deprecated via amend by $ACTOR at $NOW" "$NOW" "$PLAN_ID" "$TARGET_TASK")"
    HIST_OP="deprecated"
    DIFF="deprecate $TARGET_TASK"
    ;;
  *)
    usage
    ;;
esac

# Atomicidad (Issue 7): task + plan_history + plans.updated_at en una sola transaccion.
HIST_SQL="INSERT INTO plan_history(plan_id,version,changed_by,changed_at,operation,diff_md,snapshot_before) VALUES(?,?,?,?,?,?,?)"
HIST_PARAMS_JSON="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$PLAN_ID" "$NEW_VERSION" "$ACTOR" "$NOW" "$HIST_OP" "$DIFF" "$SNAPSHOT")"
# Bloque 2 v0.7.7: bump version y updated_by en plans (version se mantiene sincronizado con plan_history)
PLANS_SQL="UPDATE plans SET updated_at = ?, updated_by = ?, version = ? WHERE id = ?"
PLANS_PARAMS_JSON="$(python3 -c "import json,sys; print(json.dumps(list(sys.argv[1:])))" "$NOW" "$ACTOR" "$NEW_VERSION" "$PLAN_ID")"

python3 - "$DB" "$TASK_SQL" "$TASK_PARAMS_JSON" "$HIST_SQL" "$HIST_PARAMS_JSON" "$PLANS_SQL" "$PLANS_PARAMS_JSON" "$ACTOR" <<'PYEOF'
import sqlite3, sys, json
db = sys.argv[1]
task_sql, task_params = sys.argv[2], json.loads(sys.argv[3])
hist_sql, hist_params = sys.argv[4], json.loads(sys.argv[5])
plans_sql, plans_params = sys.argv[6], json.loads(sys.argv[7])
actor = sys.argv[8]
conn = sqlite3.connect(db, timeout=5)
conn.execute("PRAGMA foreign_keys=ON")
try:
    conn.execute("BEGIN IMMEDIATE")
    conn.execute(task_sql, task_params)
    conn.execute(hist_sql, hist_params)
    conn.execute(plans_sql, plans_params)
    conn.execute("INSERT INTO audit_log(ts, agent, action, table_name, actor_source) VALUES(datetime('now'), ?, 'amend', ?, 'helper')",
                 (actor, 'tasks'))
    conn.commit()
    print("ok")
except Exception as e:
    conn.rollback()
    print(f"error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

echo "amended: $SLUG v$NEW_VERSION ($OP) by $ACTOR"
