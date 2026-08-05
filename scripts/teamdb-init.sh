#!/usr/bin/env bash
# teamdb-init.sh — Inicializa teamdb proyecto
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$(pwd)}"
export SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/lib-teamdb.sh"
teamdb_init_project "$PROJECT"
echo "teamdb init: $PROJECT"
