#!/usr/bin/env bash
# teamdb-init.sh — Inicializa teamdb proyecto
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$(pwd)}"
export SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
# Fallback: funciona en repo (lib/lib-teamdb.sh) y en global (lib-teamdb.sh)
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi
teamdb_init_project "$PROJECT"
echo "teamdb init: $PROJECT"
