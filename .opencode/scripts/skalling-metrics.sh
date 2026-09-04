#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OP="${1:-}"; shift || true

project_from_last() {
  PROJECT="${1:-$(pwd)}"
  DB="$PROJECT/.opencode/context/team.db"
  [ -f "$DB" ] || { echo "ERROR: DB no existe: $DB" >&2; exit 1; }
}

write_sql() {
  local sql="$1"; shift
  local params
  params="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"
  python3 "$SCRIPT_DIR/teamdb_exec.py" --db "$DB" --mode write --sql "$sql" --params "$params" >/dev/null
}

case "$OP" in
  start)
    REQUEST_ID="${1:?Falta request-id}"; RISK="${2:?Falta risk}"; project_from_last "${3:-$(pwd)}"; ROUTE="${4:-}"; AGENTS="${5:-0}"
    write_sql "INSERT INTO workflow_metrics(request_id,risk_level,route,agents_count,started_at) VALUES(?,?,?,?,datetime('now')) ON CONFLICT(request_id) DO NOTHING" "$REQUEST_ID" "$RISK" "$ROUTE" "$AGENTS"
    ;;
  event)
    REQUEST_ID="${1:?Falta request-id}"; FIELD="${2:?Falta campo}"; VALUE="${3:?Falta valor}"; project_from_last "${4:-$(pwd)}"
    case "$FIELD" in handoff) COLUMN="handoffs" ;; permission) COLUMN="permission_prompts" ;; context_bytes) COLUMN="context_bytes" ;; agents) COLUMN="agents_count" ;; *) echo "ERROR: evento no permitido" >&2; exit 2 ;; esac
    write_sql "UPDATE workflow_metrics SET $COLUMN=$COLUMN+? WHERE request_id=?" "$VALUE" "$REQUEST_ID"
    ;;
  finish)
    REQUEST_ID="${1:?Falta request-id}"; OUTCOME="${2:?Falta outcome}"; project_from_last "${3:-$(pwd)}"
    write_sql "UPDATE workflow_metrics SET outcome=?,completed_at=datetime('now'),duration_ms=CAST((julianday('now')-julianday(started_at))*86400000 AS INTEGER) WHERE request_id=?" "$OUTCOME" "$REQUEST_ID"
    ;;
  report)
    project_from_last "${1:-$(pwd)}"
    sqlite3 -separator ' ' "$DB" "SELECT request_id||' risk='||risk_level||' route='||COALESCE(route,'')||' agents='||agents_count||' handoffs='||handoffs||' permissions='||permission_prompts||' context_bytes='||context_bytes||' duration_ms='||COALESCE(duration_ms,0)||' outcome='||COALESCE(outcome,'pending') FROM workflow_metrics ORDER BY started_at DESC;"
    ;;
  *) echo "Uso: skalling-metrics.sh start|event|finish|report ..." >&2; exit 2 ;;
esac
