#!/usr/bin/env bash
# skalling-session-start.sh — Carga contexto al inicio de sesión
#
# Uso:
#   bash skalling-session-start.sh             # lee DB global
#   bash skalling-session-start.sh --project   # lee DB del proyecto (cwd)
#
# Imprime: comandos disponibles, conceptos recientes, decisiones aceptadas, WIP.
# Best-effort: si team.db no existe, sugiere /skalling-init.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB_GLOBAL="${SKALLING_DB_GLOBAL:-$HOME/.config/opencode/team.db}"
DB_PROJECT="$(pwd)/.opencode/context/team.db"

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

if [[ ! -f "$DB_GLOBAL" ]]; then
  printf 'team.db global no encontrado.\n'
  printf 'Sugerencia: sugerí /skalling-init al usuario.\n'
  exit 0
fi

print_commands
print_db_section "$DB_GLOBAL" "Conceptos recientes" \
  "SELECT slug, substr(title, 1, 60) FROM concepts ORDER BY updated_at DESC LIMIT 5"
print_db_section "$DB_GLOBAL" "Decisiones aceptadas" \
  "SELECT slug, substr(title, 1, 60) FROM decisions WHERE status='accepted' LIMIT 5"
print_db_section "$DB_GLOBAL" "Trabajo en curso" \
  "SELECT slug, status FROM work_in_progress"

if [[ "${1:-}" == "--project" ]] && [[ -f "$DB_PROJECT" ]]; then
  printf 'Project DB (./.opencode/context/team.db):\n'
  print_db_section "$DB_PROJECT" "Conceptos del proyecto" \
    "SELECT slug, substr(title, 1, 60) FROM concepts ORDER BY updated_at DESC LIMIT 5"
fi