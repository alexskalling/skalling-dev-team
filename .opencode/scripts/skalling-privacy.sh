#!/usr/bin/env bash
# skalling-privacy.sh — marca un proyecto como "interno" (memoria compartida
# vía git, comportamiento de siempre) o "externo" (memoria NUNCA sale de la
# máquina local, ni con un git push).
#
# Motivo: por diseño, Skalling commitea una fotografía completa de TeamDB
# (db/teamdb/team.dump.sql -- tareas, planes, decisiones) para que un equipo
# la comparta vía git. En un proyecto ajeno (de un cliente, no de la propia
# empresa), eso es exactamente lo que no se quiere: que la forma de trabajar
# interna quede pegada en el historial de un repositorio que no es propio.
#
# Qué hace en modo "external":
#   - Agrega .opencode/ y db/teamdb/ a .gitignore, en un bloque marcado
#     (idempotente: correrlo de nuevo no duplica el bloque).
#   - Chequea si esas rutas YA están trackeadas por git (de antes de marcar
#     el proyecto como externo) -- si encuentra algo, avisa fuerte y no
#     hace nada más: sacar algo del historial de git es una operación
#     distinta y más delicada (git rm --cached, o reescribir historia si ya
#     se pusheó), y eso requiere una decisión explícita del usuario, no
#     algo que este script decida solo.
#
# Qué hace en modo "internal": quita el bloque de .gitignore que este mismo
# script haya agregado antes (si existía), volviendo al comportamiento de
# memoria compartida. Nunca toca líneas de .gitignore que no haya agregado
# él mismo.
#
# Uso:
#   skalling-privacy.sh status [project]
#   skalling-privacy.sh internal [project]
#   skalling-privacy.sh external [project]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

MODE="${1:-}"
PROJECT="${2:-$(pwd)}"

# Alias en español -- para que instrucciones de agente en español ("interno"/
# "externo") no dependan de traducir bien antes de invocar el script.
case "$MODE" in
  interno) MODE="internal" ;;
  externo) MODE="external" ;;
esac

usage() {
  cat <<'EOF'
Uso:
  skalling-privacy.sh status [project]
  skalling-privacy.sh internal|interno [project]
  skalling-privacy.sh external|externo [project]
EOF
}

case "$MODE" in
  status|internal|external) ;;
  *) usage >&2; exit 2 ;;
esac

DB="$(teamdb_project_path "$PROJECT")"
GITIGNORE="$PROJECT/.gitignore"
MARK_START="# --- Skalling: modo externo (gestionado por /skalling-privacy, no editar a mano) ---"
MARK_END="# --- fin Skalling ---"

current_mode() {
  if [ -f "$DB" ]; then
    teamdb_exec_value "$DB" "SELECT value FROM schema_meta WHERE key='privacy_mode'" 2>/dev/null || true
  fi
}

if [ "$MODE" = "status" ]; then
  # Distinguir "nunca se preguntó" (key ausente) de "internal" elegido a
  # propósito -- para que /skalling-init sepa si tiene que preguntar todavía.
  mode="$(current_mode)"
  if [ -z "$mode" ]; then
    echo "privacy_mode: sin-configurar"
  else
    echo "privacy_mode: $mode"
  fi
  if [ -f "$GITIGNORE" ] && grep -qF "$MARK_START" "$GITIGNORE"; then
    echo "gitignore: bloque de Skalling presente"
  else
    echo "gitignore: sin bloque de Skalling"
  fi
  exit 0
fi

[ -f "$DB" ] || { echo "ERROR: TeamDB no existe: $DB (corré /skalling-init primero)" >&2; exit 1; }

# has_skalling_block: 0 si el bloque marcado ya está en .gitignore.
has_skalling_block() {
  [ -f "$GITIGNORE" ] && grep -qF "$MARK_START" "$GITIGNORE"
}

# remove_skalling_block <file>: borra SOLO las líneas entre los dos
# marcadores (inclusive), preserva todo lo demás tal cual estaba.
remove_skalling_block() {
  local file="$1" tmp
  tmp="$(mktemp)"
  awk -v start="$MARK_START" -v end="$MARK_END" '
    $0 == start { skip = 1; next }
    $0 == end   { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

if [ "$MODE" = "external" ]; then
  if ! has_skalling_block; then
    NEEDS_BLANK_LINE=0
    [ -s "$GITIGNORE" ] && NEEDS_BLANK_LINE=1
    {
      [ "$NEEDS_BLANK_LINE" = "1" ] && echo ""
      echo "$MARK_START"
      echo ".opencode/"
      echo "db/teamdb/"
      echo "$MARK_END"
    } >> "$GITIGNORE"
    echo "OK: .gitignore actualizado (.opencode/ y db/teamdb/ ya no se commitean)"
  else
    echo "OK: .gitignore ya tenía el bloque de Skalling (sin cambios)"
  fi

  if ! OUT="$(teamdb_exec_write "$DB" \
    "INSERT INTO schema_meta(key,value) VALUES('privacy_mode','external') ON CONFLICT(key) DO UPDATE SET value='external'" \
    2>&1)"; then
    echo "ERROR: no se pudo guardar privacy_mode=external ($OUT)" >&2
    exit 1
  fi

  # Lo que .gitignore YA tiene commiteado de antes no desaparece solo -- avisar
  # fuerte en vez de asumir que quedó protegido.
  if command -v git >/dev/null 2>&1 && git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
    TRACKED="$(git -C "$PROJECT" ls-files -- .opencode db/teamdb 2>/dev/null || true)"
    if [ -n "$TRACKED" ]; then
      echo "" >&2
      echo "AVISO IMPORTANTE: estas rutas YA estaban commiteadas ANTES de marcar el proyecto como externo." >&2
      echo "El .gitignore de ahora en más evita que se suba algo NUEVO -- no borra lo que ya está en el historial:" >&2
      # Prefijar cada linea con "  - " (no un reemplazo simple de parameter expansion).
      # shellcheck disable=SC2001
      echo "$TRACKED" | sed 's/^/  - /' >&2
      echo "" >&2
      echo "Si ya se pusheó al remoto, sacarlo del historial es una operación aparte (git rm --cached + commit," >&2
      echo "y si ya está en el remoto, reescribir historia) -- pedí ayuda explícita para eso, no se hace solo." >&2
    fi
  fi
  echo "privacy_mode: external"
  exit 0
fi

if [ "$MODE" = "internal" ]; then
  if has_skalling_block; then
    remove_skalling_block "$GITIGNORE"
    echo "OK: bloque de Skalling quitado de .gitignore (memoria vuelve a compartirse vía git)"
  else
    echo "OK: .gitignore no tenía el bloque de Skalling (sin cambios)"
  fi

  if ! OUT="$(teamdb_exec_write "$DB" \
    "INSERT INTO schema_meta(key,value) VALUES('privacy_mode','internal') ON CONFLICT(key) DO UPDATE SET value='internal'" \
    2>&1)"; then
    echo "ERROR: no se pudo guardar privacy_mode=internal ($OUT)" >&2
    exit 1
  fi
  echo "privacy_mode: internal"
  exit 0
fi
