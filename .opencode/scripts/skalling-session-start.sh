#!/usr/bin/env bash
# skalling-session-start.sh — Carga contexto al inicio de sesión
#
# Uso:
#   bash skalling-session-start.sh   # DB del proyecto (cwd) si existe, si no la global
#
# Imprime: comandos disponibles, conceptos recientes, decisiones aceptadas, WIP.
# Best-effort: si team.db no existe, sugiere /skalling-init.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Ruta de TeamDB: la del repositorio principal, también desde un worktree.
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then . "$SCRIPT_DIR/lib-teamdb.sh"; else . "$SCRIPT_DIR/lib/lib-teamdb.sh"; fi

DB_GLOBAL="${SKALLING_DB_GLOBAL:-$HOME/.config/opencode/team.db}"
DB_PROJECT="$(teamdb_project_path "$(pwd)")"
DB_ACTIVE="$DB_GLOBAL"
[ -f "$DB_PROJECT" ] && DB_ACTIVE="$DB_PROJECT"

# Base del proyecto atrasada respecto de los scripts instalados: se migra sola
# (aditivo, idempotente). Un fallo se muestra pero no corta el inicio.
if [ -f "$DB_PROJECT" ] && [ -f "$SCRIPT_DIR/teamdb-ensure-current.sh" ]; then
  bash "$SCRIPT_DIR/teamdb-ensure-current.sh" "$(dirname "$(dirname "$(dirname "$DB_PROJECT")")")" || true
fi

print_header() {
  printf '\n─── SKALLING SESSION START ───\n\n'
}

print_commands() {
  printf 'Comandos disponibles:\n'
  local cmd
  for cmd in "$HOME"/.config/opencode/command/skalling-*.md; do
    [[ -e "$cmd" ]] || continue
    printf '  /%s\n' "$(basename "${cmd%.md}")"
  done
  printf '\n'
}

print_db_section() {
  local db="$1"
  local label="$2"
  local query="$3"
  if [[ -f "$db" ]] && command -v sqlite3 >/dev/null 2>&1; then
    printf '%s:\n' "$label"
    if out="$(sqlite3 -separator ' | ' "$db" "$query" 2>/dev/null)" && [[ -n "$out" ]]; then
      printf '%s\n' "$out" | sed 's/^/  /'
    else
      printf '  (vacío)\n'
    fi
    printf '\n'
  fi
}

print_header

if [[ ! -f "$DB_ACTIVE" ]]; then
  printf 'team.db global no encontrado.\n'
  printf 'Sugerencia: sugerí /skalling-init al usuario.\n'
  exit 0
fi

# Check prompt drift without reading project memory again or mutating prompts.
if [ -f "$SCRIPT_DIR/skalling-project-config.py" ] && [ -d .opencode/agents ]; then
  python3 - "$SCRIPT_DIR" "$PWD" <<'PYEOF'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('config', Path(sys.argv[1]) / 'skalling-project-config.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
drift = module.sync_agents(Path(sys.argv[2]), check=True)
if drift:
    print('DRIFT de protocolos locales: ' + ', '.join(drift) + '; actualizar con skalling-project-config.py --sync-agents (backup automático).')
PYEOF
fi
print_commands
print_db_section "$DB_ACTIVE" "Conceptos recientes" \
  "SELECT slug, substr(title, 1, 60) FROM concepts ORDER BY updated_at DESC LIMIT 5"
print_db_section "$DB_ACTIVE" "Decisiones aceptadas" \
  "SELECT slug, substr(title, 1, 60) FROM decisions WHERE status='accepted' LIMIT 5"
print_db_section "$DB_ACTIVE" "Trabajo en curso" \
  "SELECT p.slug || '/' || t.slug, t.status FROM tasks t JOIN plans p ON p.id=t.plan_id WHERE t.status IN ('pending','in_progress','in_review','blocked') ORDER BY p.id,t.order_index LIMIT 12"
