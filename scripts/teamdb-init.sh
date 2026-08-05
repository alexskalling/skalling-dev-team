#!/usr/bin/env bash
# teamdb-init.sh — Inicializa teamdb proyecto (idempotente, aplica migrations pendientes)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$(pwd)}"
SKALLING_ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export SKALLING_ROOT="$SKALLING_ROOT_DIR"
# Fallback: funciona en repo (lib/lib-teamdb.sh) y en global (lib-teamdb.sh)
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

# Init base schema si la DB no existe
teamdb_init_project "$PROJECT"

# Si la DB existe pero le faltan tablas nuevas (migrations), aplicarlas (T-2.9)
DB="$(teamdb_project_path "$PROJECT")"
MIG_DIR="$SKALLING_ROOT_DIR/sql/migrations"
if [ -d "$MIG_DIR" ]; then
  for mig in "$MIG_DIR"/*.sql; do
    [ -f "$mig" ] || continue
    sqlite3 "$DB" < "$mig" 2>/dev/null || true
  done
fi

echo "teamdb init: $PROJECT"
