#!/usr/bin/env bash
# Reconciliar el índice de skills con archivos válidos; nunca instalar dependencias.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 # shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then source "$SCRIPT_DIR/lib-teamdb.sh"; else source "$SCRIPT_DIR/lib/lib-teamdb.sh"; fi
teamdb_init_global >/dev/null
args=()
if [ -n "${1:-}" ]; then args=(--project "$1"); fi
python3 "$SCRIPT_DIR/skalling_skills.py" sync "${args[@]}"
if [ -n "${1:-}" ]; then teamdb_refresh_dump "$1" >/dev/null; fi
