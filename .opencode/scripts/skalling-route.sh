#!/usr/bin/env bash
# skalling-route.sh — Clasificación de intención/riesgo + audit de routing
#
# Uso:
#   bash skalling-route.sh classify --risk low|medium|high --clarity clear|ambiguous --kind code [--record ...]
#
# Las reglas viven en skalling_classify.py (las mismas que aplica
# skalling_workflow start). Para código este comando es solo VISTA PREVIA:
# la única autorización para implementar es `skalling_workflow start`.
# `--record` persiste research/audit en TeamDB.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"

persist_classification() {
  local db="$1" request_id="$2" intent="$3" route="$4" agents="$5" risk="$6" supersedes="$7"
  [ -f "$db" ] || { printf 'ERROR: TeamDB no existe: %s\n' "$db" >&2; return 1; }
  python3 - "$db" "$request_id" "$intent" "$route" "$agents" "$risk" "$supersedes" <<'PY'
import sqlite3
from teamdb_guard import connect as protected_connect
import sys

db, request_id, intent, route, agents, risk, supersedes = sys.argv[1:]
conn = protected_connect(db, timeout=5)
try:
    conn.execute("BEGIN IMMEDIATE")
    conn.execute(
        """INSERT INTO routing_decisions
           (ts, user_intent, chosen_route, route_reason, agents_involved)
           VALUES (datetime('now'), ?, ?, 'clasificación automática', ?)""",
        (intent, route, agents),
    )
    if conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='workflow_metrics'").fetchone():
        # Una reclasificación reemplaza SOLO al pedido que nombra
        # (--supersedes). Antes se cerraba cualquier métrica abierta de los
        # últimos 30 min y el pedido de otra sesión quedaba 'superseded'.
        if supersedes:
            conn.execute(
                """UPDATE workflow_metrics
                   SET outcome='superseded', completed_at=datetime('now'),
                       duration_ms=CAST((julianday('now')-julianday(started_at))*86400000 AS INTEGER)
                   WHERE completed_at IS NULL AND request_id = ? AND request_id != ?""",
                (supersedes, request_id),
            )
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
  local risk="" clarity="clear" kind="" record=false intent="" project request_id="" supersedes=""
  local scope="unknown" decision="none" sensitive=false visual=false
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
      --supersedes) supersedes="${2:?Falta request_id reemplazado}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) printf 'Argumento desconocido: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  # Para código registrar acá abriría un segundo request_id, paralelo al del
  # workflow que sí autoriza: la clasificación de código la registra
  # skalling_workflow start.
  if [ "$record" = true ] && [ "$kind" = code ]; then
    printf 'ERROR: para código la clasificación la registra skalling_workflow start (no skalling-route.sh --record)\n' >&2
    return 2
  fi
  local normalized
  normalized="$(python3 -c '
import sys
from skalling_classify import normalize
kind, risk, scope, clarity, decision, sensitive, visual = sys.argv[1:]
try:
    r = normalize(kind, risk, scope, clarity, decision, sensitive == "true", visual == "true")
except ValueError as error:
    print(error, file=sys.stderr)
    sys.exit(2)
print("\t".join([r["risk"], r["route"], r["agents"], r["verification"],
                 str(r["needs_user_decision"]).lower(), str(r["implementation_allowed"]).lower()]))
' "$kind" "$risk" "$scope" "$clarity" "$decision" "$sensitive" "$visual")" || return 2
  local route agents verification needs_user_decision implementation_allowed readiness="missing"
  IFS=$'\t' read -r risk route agents verification needs_user_decision implementation_allowed <<< "$normalized"
  local project_db="$project/.opencode/context/team.db"
  if [ -f "$project_db" ]; then
    readiness="$(python3 -c 'import sys; from skalling_classify import readiness; print(readiness(sys.argv[1]))' "$project_db")"
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
    persist_classification "$project/.opencode/context/team.db" "$request_id" "$intent" "$route" "$agents" "$risk" "$supersedes"
  fi
  python3 - "$risk" "$route" "$agents" "$verification" "$request_id" "$needs_user_decision" "$implementation_allowed" "$readiness" "$project" "$kind" "$acceptance" "$reuse" "$plan_id" "$visual" ${files[@]+"${files[@]}"} <<'PY'
import json, sys
from teamdb_guard import connect as protected_connect
from skalling_classify import memory_blockers
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
    db_path = root / ".opencode/context/team.db"
    blockers.extend(memory_blockers(db_path, visual == "true"))
    if risk in ("medium", "high"):
        with protected_connect("file:" + str(db_path) + "?mode=ro", uri=True) as db:
            plan = db.execute("SELECT 1 FROM plans WHERE id=? AND status IN ('approved','in_progress') AND length(design_md)>0", (plan_id,)).fetchone()
        if not plan:
            blockers.append("Sol debe preparar un plan aprobado: --plan-id")
    if blockers:
        allowed = "false"
result = dict(risk=risk, route=route, agents=agents, verification=verification,
              needs_user_decision=decision == 'true', implementation_allowed=allowed == 'true',
              readiness=readiness, blockers=blockers,
              request_context=dict(files=files, acceptance=acceptance, reuse=reuse))
if kind == "code":
    # Vista previa: lo que autoriza implementar es skalling_workflow start.
    result["authorizes"] = False
if request_id:
    result['request_id'] = request_id
print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))
PY
}

usage() {
    printf 'Uso:\n  %s classify --kind code|research|audit --risk low|medium|high --scope local|module|cross-cutting|unknown [--clarity clear|ambiguous] [--decision none|pending|resolved] [--sensitive] [--visual] [--file RUTA --acceptance TEXTO --reuse TEXTO --plan-id ID] [--record --intent TEXTO --project RUTA --supersedes REQUEST_ID]\n  --record solo para research/audit; para código la clasificación la registra skalling_workflow start.\n' "$0"
}

case "${1:-help}" in
  classify) shift; cmd_classify "$@" ;;
  help|-h|--help) usage ;;
  *)
    printf 'Subcomando desconocido: %s\n' "$1" >&2
    exit 1
    ;;
esac
