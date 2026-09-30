#!/usr/bin/env bash
# teamdb-context.sh — Context capsule (selección filtrada) para handoff de Teo
# T-2.16
# Lock file (se aplica al final, después de parsing $PROJECT)
set -euo pipefail

PROJECT="${PROJECT:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Lock file para evitar race conditions entre agentes
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
  teamdb-context.sh for-task <plan> <task> [--linked-only] [--seen=read_key] [--max-bytes=8000] [project]
  teamdb-context.sh for-request <query> [--top-k=8] [--max-bytes=8000] [--file=path] [project]

Subcomandos:
  link     Asocia memoria (concepts/decisions/preferences/known_problems) a una task
  for-task Emite la cápsula JSON con task + plan + memoria filtrada
  for-request Emite memoria relevante para un pedido antes de que exista plan
EOF
  exit 2
}

OP="${1:-}"
[ -z "$OP" ] && usage
shift

case "$OP" in
  for-request)
    QUERY="${1:?Falta query}"; shift
    case "$QUERY" in -*) echo "ERROR: falta el texto del pedido antes de las opciones" >&2; exit 2 ;; esac
    [ -n "$QUERY" ] || { echo "ERROR: pedido vacío" >&2; exit 2; }
    PROJECT=""; TOP_K=8; MAX_BYTES=8000; VISUAL=false; FILE_ANCHORS=(); SEEN=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --seen=*) SEEN+=("${1#--seen=}") ;;
        --visual) VISUAL=true ;;
        --file=*) FILE_ANCHORS+=("${1#--file=}") ;;
        --top-k=*) TOP_K="${1#--top-k=}" ;;
        --max-bytes=*) MAX_BYTES="${1#--max-bytes=}" ;;
        -*) echo "[ERROR] argumento desconocido: $1" >&2; exit 2 ;;
        *) PROJECT="$1" ;;
      esac
      shift
    done
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo '{"concepts":[],"decisions":[],"known_problems":[],"preferences":[]}' ; exit 0; }
    python3 - "$DB" "$QUERY" "$TOP_K" "$MAX_BYTES" "$VISUAL" "$SCRIPT_DIR" "$PROJECT" "${SEEN[@]+${SEEN[@]/#/seen:}}" "${FILE_ANCHORS[@]+${FILE_ANCHORS[@]}}" <<'PYEOF'
import json, sqlite3, sys
sys.path.insert(0, sys.argv[6])
from skalling_context import request_context
with sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True) as conn:
    result = request_context(conn, sys.argv[7], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5] == 'true', sys.argv[8:])
print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
PYEOF
    ;;
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
    # Lock cross-platform (mkdir-based, sin flock). v0.8.3
    LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
    mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
    if ! teamdb_lock "$LOCK_DIR" 10; then
      exit 1
    fi
    trap 'teamdb_unlock "$LOCK_DIR"' EXIT
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
    # FASE 1: dump fresco post-escritura
    teamdb_refresh_dump "$PROJECT" >/dev/null 2>&1 || true
    echo "linked: task=$TASK_SLUG"
    ;;

  for-task)
    PLAN_SLUG="$1"; TASK_SLUG="$2"; shift 2
    PROJECT=""
    TOP_K=8
    MAX_BYTES=8000
    DISCOVER=1; SEEN=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --top-k=*) TOP_K="${1#--top-k=}" ;;
        --max-bytes=*) MAX_BYTES="${1#--max-bytes=}" ;;
        --discover) DISCOVER=1 ;;
        --linked-only) DISCOVER=0 ;;
        --seen=*) SEEN+=("${1#--seen=}") ;;
        --help|-h) usage ;;
        -*) echo "[ERROR] argumento desconocido: $1" >&2; exit 2 ;;
        *) PROJECT="$1" ;;
      esac
      shift || break
    done
    [ -d "$PROJECT" ] || PROJECT="$(pwd)"
    DB="$(teamdb_project_path "$PROJECT")"
    [ -f "$DB" ] || { echo "[]" ; exit 0; }
    python3 - "$DB" "$PLAN_SLUG" "$TASK_SLUG" "$TOP_K" "$MAX_BYTES" "$DISCOVER" "$SCRIPT_DIR" "$PROJECT" "${SEEN[@]+${SEEN[@]}}" <<'PYEOF'
import sqlite3, sys, json
sys.path.insert(0, sys.argv[7])
from skalling_context import task_context
with sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True) as conn:
    result = task_context(conn, sys.argv[8], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6] == '1', sys.argv[9:])
print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))
PYEOF
    ;;

  *)
    usage
    ;;
esac
