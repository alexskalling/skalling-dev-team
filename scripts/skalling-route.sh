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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  local risk="" clarity="clear" kind="" record=false intent="" project request_id=""
  local scope="unknown" decision="none" sensitive=false visual=false needs_user_decision=false implementation_allowed=false readiness="missing"
  local acceptance="" reuse="" plan_id=""
  local files=()
  project="$(pwd)"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --risk) risk="${2:-}"; shift 2 ;;
      --clarity) clarity="${2:-}"; shift 2 ;;
      --kind) kind="${2:-}"; shift 2 ;;
      --scope) scope="${2:-}"; shift 2 ;;
      --decision) decision="${2:-}"; shift 2 ;;
      --sensitive) sensitive=true; shift ;;
      --visual) visual=true; shift ;;
      --file) files+=("${2:?Falta ruta}"); shift 2 ;;
      --acceptance) acceptance="${2:?Falta aceptación}"; shift 2 ;;
      --reuse) reuse="${2:?Falta estrategia}"; shift 2 ;;
      --plan-id) plan_id="${2:?Falta plan}"; shift 2 ;;
      --record) record=true; shift ;;
      --intent) intent="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --request-id) request_id="${2:-}"; shift 2 ;;
      *) printf 'Argumento desconocido: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  case "$risk" in low|medium|high) ;; *) printf 'risk debe ser low, medium o high\n' >&2; return 2 ;; esac
  case "$clarity" in clear|ambiguous) ;; *) printf 'clarity inválida\n' >&2; return 2 ;; esac
  case "$kind" in code|research|audit) ;; *) printf 'kind requerido: code, research o audit\n' >&2; return 2 ;; esac
  case "$scope" in local|module|cross-cutting|unknown) ;; *) printf 'scope inválido\n' >&2; return 2 ;; esac
  case "$decision" in none|pending|resolved) ;; *) printf 'decision inválida\n' >&2; return 2 ;; esac
  if [ "$sensitive" = true ] || [ "$scope" = cross-cutting ] || [ "$clarity" = ambiguous ] || [ "$decision" = pending ]; then
    risk=high
  elif [ "$scope" = module ] && [ "$risk" = low ]; then
    risk=medium
  fi
  if [ "$visual" = true ] && [ "$risk" = low ]; then
    risk=medium
  fi
  if [ "$decision" = pending ] || [ "$clarity" = ambiguous ]; then needs_user_decision=true; fi
  if [ "$kind" = code ] && [ "$scope" != unknown ] && [ "$needs_user_decision" = false ]; then implementation_allowed=true; fi
  local route agents verification
  case "$kind" in
    research) route="RESEARCH"; agents="Alex → Jes"; verification="sources" ;;
    audit) route="DIRECT"; agents="Alex → Luz"; verification="audit" ;;
    *)
      if [ "$risk" = "high" ] || [ "$scope" = unknown ]; then
        route="SDD"; agents="Alex → Pol → Sol → Teo → Jhon → Luz → Pau"; verification="full"
      elif [ "$risk" = "medium" ]; then
        route="INLINE"; agents="Alex → Sol → Teo → Jhon"; verification="module"
      else
        route="FAST-TRACK"; agents="Alex → Teo → Jhon"; verification="focused"
      fi
      ;;
  esac
  local project_db="$project/.opencode/context/team.db"
  if [ -f "$project_db" ] && command -v sqlite3 >/dev/null 2>&1; then
    readiness="$(sqlite3 "$project_db" "SELECT value FROM schema_meta WHERE key='project_readiness' LIMIT 1" 2>/dev/null || true)"
    [ -n "$readiness" ] || readiness="missing"
  fi
  if [ "$kind" = code ] && [ "$readiness" != initialized ] && [ "$readiness" != ready ]; then
    implementation_allowed=false
    route="DISCOVERY"
    agents="Alex → Jes → Pol"
    verification="readiness"
  fi
  if [ "$record" = true ]; then
    [ -n "$intent" ] || { printf 'ERROR: --record requiere --intent\n' >&2; return 2; }
    [ -n "$request_id" ] || request_id="req-$(date +%Y%m%d%H%M%S)-$$"
    persist_classification "$project/.opencode/context/team.db" "$request_id" "$intent" "$route" "$agents" "$risk"
  fi
  python3 - "$risk" "$route" "$agents" "$verification" "$request_id" "$needs_user_decision" "$implementation_allowed" "$readiness" "$project" "$kind" "$acceptance" "$reuse" "$plan_id" "$visual" ${files[@]+"${files[@]}"} <<'PY'
import json, sys, sqlite3
from pathlib import Path
risk, route, agents, verification, request_id, decision, allowed, readiness = sys.argv[1:9]
project, kind, acceptance, reuse, plan_id, visual = sys.argv[9:15]
files = sys.argv[15:]
blockers = []
if kind == "code" and allowed == "true":
    root = Path(project).resolve()
    if not files:
        blockers.append("Falta evidencia: indicar --file por cada archivo existente consultado")
    for file in files:
        candidate = (root / file).resolve()
        if not candidate.is_relative_to(root) or not candidate.is_file():
            blockers.append("Archivo de contexto inválido: " + file)
    if not acceptance.strip():
        blockers.append("Falta --acceptance: resultado observable del pedido")
    if not reuse.strip():
        blockers.append("Falta --reuse: qué componente/patrón existente se reutiliza")
    with sqlite3.connect("file:" + str(root / ".opencode/context/team.db") + "?mode=ro", uri=True) as db:
        if not db.execute("SELECT 1 FROM concepts WHERE slug='project-summary' AND length(body_md)>0").fetchone():
            blockers.append("Falta resumen de proyecto en TeamDB")
        if visual == "true" and not db.execute("SELECT 1 FROM concepts WHERE slug='design-system' AND length(body_md)>0").fetchone():
            blockers.append("Falta sistema de diseño en TeamDB")
        if risk in ("medium", "high"):
            plan = db.execute("SELECT 1 FROM plans WHERE id=? AND status IN ('approved','in_progress') AND length(design_md)>0", (plan_id,)).fetchone()
            if not plan:
                blockers.append("Sol debe preparar un plan aprobado: --plan-id")
    if blockers:
        allowed = "false"
result = dict(risk=risk, route=route, agents=agents, verification=verification,
              needs_user_decision=decision == 'true', implementation_allowed=allowed == 'true',
              readiness=readiness, blockers=blockers,
              request_context=dict(files=files, acceptance=acceptance, reuse=reuse))
if request_id:
    result['request_id'] = request_id
print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))
PY
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
    printf 'Uso:\n  %s list\n  %s classify --kind code|research|audit --risk low|medium|high --scope local|module|cross-cutting|unknown [--clarity clear|ambiguous] [--decision none|pending|resolved] [--sensitive] [--visual] [--file RUTA --acceptance TEXTO --reuse TEXTO --plan-id ID] [--record --intent TEXTO --project RUTA]\n  %s record ROUTE AGENT [INTENT]\n' "$0" "$0" "$0"
    ;;
  *)
    printf 'Subcomando desconocido: %s\n' "$1" >&2
    exit 1
    ;;
esac
