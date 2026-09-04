#!/usr/bin/env bash
# teamdb-graph-refresh.sh — Refresca AMBOS grafos (memoria + código) de un proyecto.
# Idempotente. Pau lo llama al consolidar memoria; agentes lo llaman antes de proponer cambios.
#
#   - Grafo de memoria: corre teamdb-link.sh (auto-enlaza conceptos por categoría/tag).
#   - Grafo de código:  hace POST /api/codegraph/refresh al dashboard server.
#
# Uso:
#   teamdb-graph-refresh.sh [proyecto]
#   teamdb-graph-refresh.sh --memory [proyecto]   # solo memoria
#   teamdb-graph-refresh.sh --code [proyecto]     # solo código

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback para lib-teamdb.sh (igual que teamdb-init.sh)
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

# Parse args
MODE="both"
PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --memory) MODE="memory"; shift ;;
    --code)   MODE="code";   shift ;;
    -h|--help)
      cat <<EOF
teamdb-graph-refresh.sh — Refresca grafos del proyecto

Uso:
  teamdb-graph-refresh.sh [proyecto]            # ambos grafos
  teamdb-graph-refresh.sh --memory [proyecto]   # solo memoria
  teamdb-graph-refresh.sh --code [proyecto]     # solo código

Proyecto default: \$(pwd)
EOF
      exit 0 ;;
    -*)
      echo "Flag desconocida: $1" >&2; exit 1 ;;
    *)
      PROJECT="$1"; shift ;;
  esac
done

PROJECT="${PROJECT:-$(pwd)}"
DB="$(teamdb_project_path "$PROJECT")"

if [ ! -f "$DB" ]; then
  echo "ERROR: team.db no existe en $PROJECT/.opencode/context/" >&2
  exit 1
fi

# ── 1. Grafo de MEMORIA ───────────────────────────────────────
if [ "$MODE" = "both" ] || [ "$MODE" = "memory" ]; then
  if [ -f "$SCRIPT_DIR/teamdb-link.sh" ]; then
    echo "▶ Refrescando grafo de memoria (auto-link)..."
    bash "$SCRIPT_DIR/teamdb-link.sh" "$PROJECT" --quiet 2>/dev/null || bash "$SCRIPT_DIR/teamdb-link.sh" "$PROJECT"
    N_LINKS="$(sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links" 2>/dev/null || echo 0)"
    N_CONCEPTS="$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts" 2>/dev/null || echo 0)"
    N_DECISIONS="$(sqlite3 "$DB" "SELECT COUNT(*) FROM decisions" 2>/dev/null || echo 0)"
    echo "  ✓ Memoria: $N_CONCEPTS concepts, $N_DECISIONS decisions, $N_LINKS links"
  else
    echo "WARN: teamdb-link.sh no encontrado, skip memoria" >&2
  fi
fi

# ── 2. Grafo de CÓDIGO ────────────────────────────────────────
if [ "$MODE" = "both" ] || [ "$MODE" = "code" ]; then
  PORT_FILE="/tmp/teamdb-dashboard.port"
  if [ -f "$PORT_FILE" ]; then
    PORT="$(cat "$PORT_FILE")"
    if curl -sf -X POST "http://localhost:$PORT/api/codegraph/refresh" -o /dev/null --max-time 120; then
      N_NODES="$(curl -sf "http://localhost:$PORT/api/codegraph" 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("nodes",[])))' 2>/dev/null || echo '?')"
      echo "  ✓ Código: $N_NODES archivos indexados"
    else
      echo "WARN: dashboard server no respondió (¿corriendo?) — code graph no refrescado" >&2
    fi
  else
    echo "  · Dashboard server no detectado — code graph se refrescará al abrir /skalling-dashboard"
  fi
fi

echo "✓ Grafos refrescados"
