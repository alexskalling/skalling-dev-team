#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Ruta de TeamDB: la del repositorio principal, también desde un worktree.
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then . "$SCRIPT_DIR/lib-teamdb.sh"; else . "$SCRIPT_DIR/lib/lib-teamdb.sh"; fi
PROJECT="${PROJECT:-$(pwd)}"

if [ "${1:-}" = "--project" ]; then
  PROJECT="${2:?Falta project}"
  shift 2
fi

KIND="${1:-}"
shift || true
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "ERROR: DB no existe: $DB" >&2; exit 1; }

run_write() {
  local sql="$1"
  shift
  local params
  params="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"
  TEAMDB_ACTOR="${TEAMDB_ACTOR:-pau}" python3 "$SCRIPT_DIR/teamdb_exec.py" \
    --db "$DB" --mode write --sql "$sql" --params "$params"
  echo
}

case "$KIND" in
  concept)
    SLUG="${1:?Falta slug}"; TITLE="${2:?Falta title}"; BODY="${3:?Falta body}"; CATEGORY="${4:-general}"
    run_write "INSERT INTO concepts(slug,title,body_md,category,updated_at) VALUES(?,?,?,?,datetime('now')) ON CONFLICT(slug) DO UPDATE SET title=excluded.title,body_md=excluded.body_md,category=excluded.category,updated_at=excluded.updated_at" "$SLUG" "$TITLE" "$BODY" "$CATEGORY"
    ;;
  decision)
    SLUG="${1:?Falta slug}"; TITLE="${2:?Falta title}"; BODY="${3:?Falta body}"; STATUS="${4:-accepted}"
    run_write "INSERT INTO decisions(slug,title,body_md,status,decided_at,decided_by) VALUES(?,?,?,?,datetime('now'),?) ON CONFLICT(slug) DO UPDATE SET title=excluded.title,body_md=excluded.body_md,status=excluded.status,decided_at=excluded.decided_at,decided_by=excluded.decided_by" "$SLUG" "$TITLE" "$BODY" "$STATUS" "${TEAMDB_ACTOR:-pau}"
    ;;
  preference)
    SLUG="${1:?Falta slug}"; BODY="${2:?Falta body}"; SCOPE="${3:-project}"
    run_write "INSERT INTO preferences(slug,body_md,scope,source) VALUES(?,?,?,?) ON CONFLICT(slug) DO UPDATE SET body_md=excluded.body_md,scope=excluded.scope,source=excluded.source" "$SLUG" "$BODY" "$SCOPE" "${TEAMDB_ACTOR:-pau}"
    ;;
  problem)
    SLUG="${1:?Falta slug}"; TITLE="${2:?Falta title}"; SYMPTOM="${3:?Falta symptom}"; WORKAROUND="${4:-}"; STATUS="${5:-open}"
    run_write "INSERT INTO known_problems(slug,title,symptom_md,workaround_md,status,discovered_at) VALUES(?,?,?,?,?,datetime('now')) ON CONFLICT(slug) DO UPDATE SET title=excluded.title,symptom_md=excluded.symptom_md,workaround_md=excluded.workaround_md,status=excluded.status" "$SLUG" "$TITLE" "$SYMPTOM" "$WORKAROUND" "$STATUS"
    ;;
  *)
    cat >&2 <<'USAGE'
Uso: teamdb-memory.sh [--project <path>] <tipo> <campos>
  concept    <slug> <título> <cuerpo> [categoría]
  decision   <slug> <título> <cuerpo> [accepted|proposed|superseded|rejected]
  preference <slug> <cuerpo> [scope]
  problem    <slug> <título> <síntoma> [workaround] [open|monitoring|resolved|wontfix]
Ej.: teamdb-memory.sh --project "$PWD" decision orm-drizzle "ORM" "Usamos Drizzle por X" accepted
Mismo slug = actualización (queda versionada para el merge del equipo).
USAGE
    exit 2
    ;;
esac

if command -v bash >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/teamdb-dump.sh" ]; then
  bash "$SCRIPT_DIR/teamdb-dump.sh" "$PROJECT" >/dev/null
fi
