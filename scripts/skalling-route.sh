#!/usr/bin/env bash
# skalling-route.sh — Tabla de despacho + audit de routing
#
# Uso:
#   bash skalling-route.sh list                              # imprime la tabla
#   bash skalling-route.sh record ROUTE AGENT [INTENT]       # registra decisión
#   bash skalling-route.sh classify --risk low|medium|high --clarity clear|ambiguous --kind code
#
# La tabla es read-only desde bash. El LLM la lee una vez al clasificar intención.

set -euo pipefail

DISPATCH_TABLE="$(cat <<'EOF'
INTENT / RISK                   | ROUTE        | AGENTS
investigación / explicar        | RESEARCH     | Jes
auditoría / seguridad / calidad| DIRECT       | Luz
riesgo bajo, alcance claro       | FAST-TRACK   | Teo → Jhon
riesgo medio, alcance claro      | INLINE       | Sol → Teo → Jhon
riesgo alto o intención ambigua | SDD          | Pol → Sol → Teo → Jhon → Luz → Pau
memoria / WIP / followups       | MEMORY       | Pau
specs / propuesta de cambio     | SPEC         | Pol
plan técnico / design / tasks   | DESIGN       | Sol
verificación / regresión        | VERIFY       | Jhon
commits                         | COMMIT       | Alex (con permiso)
EOF
)"

DB_GLOBAL="${SKALLING_DB_GLOBAL:-$HOME/.config/opencode/team.db}"

cmd_list() {
  printf 'TABLA DE DESPACHO\n'
  printf '%s\n' "$DISPATCH_TABLE"
}

persist_classification() {
  local db="$1" request_id="$2" intent="$3" route="$4" agents="$5" risk="$6"
  [ -f "$db" ] || { printf 'ERROR: TeamDB no existe: %s\n' "$db" >&2; return 1; }
  python3 - "$db" "$request_id" "$intent" "$route" "$agents" "$risk" <<'PY'
import sqlite3
import sys

db, request_id, intent, route, agents, risk = sys.argv[1:]
conn = sqlite3.connect(db, timeout=5)
try:
    conn.execute("BEGIN IMMEDIATE")
    conn.execute(
        """INSERT INTO routing_decisions
           (ts, user_intent, chosen_route, route_reason, agents_involved)
           VALUES (datetime('now'), ?, ?, 'clasificación automática', ?)""",
        (intent, route, agents),
    )
    if conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='workflow_metrics'").fetchone():
        conn.execute(
            """INSERT INTO workflow_metrics
               (request_id, risk_level, route, agents_count, started_at)
               VALUES (?, ?, ?, ?, datetime('now'))
               ON CONFLICT(request_id) DO NOTHING""",
            (request_id, risk, route, agents.count('→') + 1),
        )
    conn.commit()
finally:
    conn.close()
PY
}

cmd_classify() {
  local risk="" clarity="clear" kind="code" record=false intent="" project request_id=""
  project="$(pwd)"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --risk) risk="${2:-}"; shift 2 ;;
      --clarity) clarity="${2:-}"; shift 2 ;;
      --kind) kind="${2:-}"; shift 2 ;;
      --record) record=true; shift ;;
      --intent) intent="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --request-id) request_id="${2:-}"; shift 2 ;;
      *) printf 'Argumento desconocido: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  case "$risk" in low|medium|high) ;; *) printf 'risk debe ser low, medium o high\n' >&2; return 2 ;; esac
  local route agents verification
  case "$kind" in
    research) route="RESEARCH"; agents="Alex → Jes"; verification="sources" ;;
    audit) route="DIRECT"; agents="Alex → Luz"; verification="audit" ;;
    *)
      if [ "$risk" = "high" ] || [ "$clarity" = "ambiguous" ]; then
        route="SDD"; agents="Alex → Pol → Sol → Teo → Jhon → Luz → Pau"; verification="full"
      elif [ "$risk" = "medium" ]; then
        route="INLINE"; agents="Alex → Sol → Teo → Jhon"; verification="module"
      else
        route="FAST-TRACK"; agents="Alex → Teo → Jhon"; verification="focused"
      fi
      ;;
  esac
  if [ "$record" = true ]; then
    [ -n "$intent" ] || { printf 'ERROR: --record requiere --intent\n' >&2; return 2; }
    [ -n "$request_id" ] || request_id="req-$(date +%Y%m%d%H%M%S)-$$"
    persist_classification "$project/.opencode/context/team.db" "$request_id" "$intent" "$route" "$agents" "$risk"
    printf '{"risk":"%s","route":"%s","agents":"%s","verification":"%s","request_id":"%s"}\n' "$risk" "$route" "$agents" "$verification" "$request_id"
  else
    printf '{"risk":"%s","route":"%s","agents":"%s","verification":"%s"}\n' "$risk" "$route" "$agents" "$verification"
  fi
}

cmd_record() {
  local route="${1:-}"
  local agent="${2:-}"
  local intent="${3:-}"
  if [[ -z "$route" || -z "$agent" ]]; then
    printf 'Uso: skalling-route.sh record <route> <agent> [intent]\n' >&2
    return 1
  fi
  if [[ ! -f "$DB_GLOBAL" ]]; then
    printf 'audit skipped (teamdb no disponible)\n'
    return 0
  fi
  if ! command -v sqlite3 >/dev/null 2>&1; then
    printf 'audit skipped (sqlite3 no instalado)\n'
    return 0
  fi
  if ! sqlite3 "$DB_GLOBAL" "SELECT 1 FROM routing_decisions LIMIT 1" >/dev/null 2>&1; then
    printf 'audit skipped (tabla routing_decisions no existe en schema)\n'
    return 0
  fi
  if python3 "$SCRIPT_DIR/teamdb_exec.py" --db "$DB_GLOBAL" --mode write \
    --sql "INSERT INTO routing_decisions (ts,user_intent,chosen_route,route_reason,agents_involved) VALUES (datetime('now'),?,?,'manual',?)" \
    --params "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$intent" "$route" "$agent")" >/dev/null; then
    printf 'audit ok (%s → %s)\n' "$route" "$agent"
  else
    printf 'audit failed (%s)\n' "$route"
  fi
}

case "${1:-help}" in
  list)    shift; cmd_list "$@" ;;
  classify) shift; cmd_classify "$@" ;;
  record)  shift; cmd_record "$@" ;;
  help|-h|--help)
    printf 'Uso:\n  %s list\n  %s classify --risk NIVEL [--record --intent TEXTO --project RUTA]\n  %s record ROUTE AGENT [INTENT]\n' "$0" "$0" "$0"
    ;;
  *)
    printf 'Subcomando desconocido: %s\n' "$1" >&2
    exit 1
    ;;
esac
