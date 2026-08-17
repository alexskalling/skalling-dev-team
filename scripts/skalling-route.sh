#!/usr/bin/env bash
# skalling-route.sh — Tabla de despacho + audit de routing
#
# Uso:
#   bash skalling-route.sh list                              # imprime la tabla
#   bash skalling-route.sh record ROUTE AGENT [INTENT]       # registra decisión
#
# La tabla es read-only desde bash. El LLM la lee una vez al clasificar intención.

set -euo pipefail

DISPATCH_TABLE="$(cat <<'EOF'
INTENT                          | ROUTE        | AGENT
investigación / explicar        | RESEARCH     | Jes
auditoría / seguridad / calidad| DIRECT       | Luz
bug aislado reproducible        | INTERVENTION | Teo
cambio trivial (UI/typo/config) | FAST-TRACK   | Teo
1-3 archivos, scope claro       | INLINE       | Teo
4+ archivos, scope ambiguo      | SDD          | Pol → Sol → Teo
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
  record)  shift; cmd_record "$@" ;;
  help|-h|--help)
    printf 'Uso:\n  %s list\n  %s record ROUTE AGENT [INTENT]\n' "$0" "$0"
    ;;
  *)
    printf 'Subcomando desconocido: %s\n' "$1" >&2
    exit 1
    ;;
esac