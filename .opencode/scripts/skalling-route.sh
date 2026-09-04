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

cmd_classify() {
  local risk="" clarity="clear" kind="code"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --risk) risk="${2:-}"; shift 2 ;;
      --clarity) clarity="${2:-}"; shift 2 ;;
      --kind) kind="${2:-}"; shift 2 ;;
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
  printf '{"risk":"%s","route":"%s","agents":"%s","verification":"%s"}\n' "$risk" "$route" "$agents" "$verification"
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
  if sqlite3 "$DB_GLOBAL" <<SQL
INSERT INTO routing_decisions (ts, user_intent, chosen_route, route_reason, agents_involved)
VALUES (
  datetime('now'),
  '$(printf "%s" "$intent" | tr "'" "''")',
  '$(printf "%s" "$route" | tr "'" "''")',
  'auto',
  '$(printf "%s" "$agent" | tr "'" "''")'
);
SQL
  then
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
    printf 'Uso:\n  %s list\n  %s record ROUTE AGENT [INTENT]\n' "$0" "$0"
    ;;
  *)
    printf 'Subcomando desconocido: %s\n' "$1" >&2
    exit 1
    ;;
esac
