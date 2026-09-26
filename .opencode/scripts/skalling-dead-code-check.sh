#!/usr/bin/env bash
# skalling-dead-code-check.sh — busca scripts/plugins instalables que ningún
# agente, comando u otro script invoca realmente.
#
# Motivo: pasó DOS veces en la misma sesión sin que nada lo señalara --
# skalling-context-cache.sh existía, tenía un bug real, y nadie lo llamaba
# (se encontró auditando a mano); teamdb-task-groups.sh se construyó y quedó
# sin que ningún agente lo invocara hasta que un humano lo notó. Este script
# convierte esa auditoría manual en un chequeo repetible.
#
# Qué NO cuenta como "uso real" (a propósito):
#   - Que el propio install-global.sh lo copie -- instalado no es lo mismo
#     que usado (exactamente el bug de skalling-context-cache.sh: se
#     instalaba, nunca se invocaba).
#   - Que scripts/.bundle-manifest lo liste -- mismo motivo.
#   - Que solo aparezca en tests/ -- un test prueba que la lógica funciona,
#     no que algún agente o comando la use de verdad en el flujo real
#     (exactamente el estado de teamdb-task-groups.sh antes de que
#     teamdb-plan.sh lo invocara).
#
# Qué SÍ cuenta como uso real: aparecer referenciado en agents-base/*.md
# (un agente lo corre), command/*.md (un comando lo corre), o en otro
# scripts/*.sh / scripts/*.py / plugins/**/*.js|*.mjs (una pieza real del
# sistema lo llama).
#
# Uso: skalling-dead-code-check.sh [--root <dir>]
# Exit: 0 si no hay huérfanos, 1 si encuentra al menos uno.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    *) echo "Arg desconocido: $1" >&2; exit 2 ;;
  esac
done

# Excepciones documentadas: herramientas de mantenimiento que un humano corre
# a mano cuando hace falta (no un agente, no un flujo automático), así que
# nunca van a aparecer invocadas por nombre en agents-base/command/otro
# script. No son código muerto -- son herramientas reales sin caller
# programático por diseño. Agregar acá SOLO con el motivo, no para silenciar
# un hallazgo real sin revisarlo primero.
ALLOWLIST=(
  # migrate-plans-md-to-db.sh: migración legacy de planes en .md a TeamDB,
  # para proyectos viejos que actualizan Skalling; se corre una vez a mano.
  "migrate-plans-md-to-db.sh"
  # teamdb-ingest-change.sh: misma categoría -- importa un .opencode/changes/
  # <slug>/ (proposal.md + tasks.md + specs/*.md) de antes de DB-first hacia
  # TeamDB. Se corre una vez a mano al migrar un proyecto viejo.
  "teamdb-ingest-change.sh"
)
is_allowlisted() {
  local name="$1" a
  for a in "${ALLOWLIST[@]}"; do
    [ "$a" = "$name" ] && return 0
  done
  return 1
}

# Candidatos: todo lo instalable que podría quedar sin uso.
CANDIDATES=()
for f in "$ROOT"/scripts/*.sh "$ROOT"/scripts/*.py "$ROOT"/plugins/*.js "$ROOT"/plugins/lib/*.mjs; do
  [ -f "$f" ] || continue
  CANDIDATES+=("$f")
done

# Dónde buscar uso real -- todo el árbol MENOS tests/ y el bundle-manifest
# (listar un nombre ahí no prueba que algo lo invoque, ver arriba). Incluye
# los scripts raíz (install-global.sh, setup.sh, setup-team-doctor.sh,
# bootstrap-context.sh) porque, además de copiar archivos con un glob (que
# nunca matchea un nombre literal, así que no tapa un huérfano real), también
# EJECUTAN scripts puntuales por su nombre literal (ej. render-agent.sh,
# skalling-bootstrap-context.py) -- excluirlos daba falsos positivos.
# También los SKILL.md (las skills instruyen qué script correr) y los git
# hooks (post-merge invoca teamdb-merge.sh). El propio candidato se excluye
# de su propia búsqueda.
SEARCH_FILES=("$ROOT/install-global.sh" "$ROOT/setup.sh" "$ROOT/setup-team-doctor.sh" "$ROOT/bootstrap-context.sh")
for f in "$ROOT"/agents-base/*.md "$ROOT"/command/*.md \
         "$ROOT"/scripts/*.sh "$ROOT"/scripts/*.py "$ROOT"/scripts/lib/*.sh \
         "$ROOT"/scripts/hooks/* \
         "$ROOT"/plugins/*.js "$ROOT"/plugins/lib/*.mjs \
         "$ROOT"/skills-base/*/SKILL.md; do
  [ -f "$f" ] || continue
  SEARCH_FILES+=("$f")
done

ORPHANS=()
for candidate in "${CANDIDATES[@]}"; do
  name="$(basename "$candidate")"
  is_allowlisted "$name" && continue
  found=0
  for f in "${SEARCH_FILES[@]}"; do
    [ "$f" = "$candidate" ] && continue
    if grep -q -- "$name" "$f" 2>/dev/null; then
      found=1
      break
    fi
  done
  [ "$found" = "0" ] && ORPHANS+=("$name")
done

if [ "${#ORPHANS[@]}" -eq 0 ]; then
  echo "OK: sin código instalable sin uso real detectado (${#CANDIDATES[@]} candidatos revisados)"
  exit 0
fi

echo "Código instalable sin uso real detectado (nadie lo invoca fuera de tests/install-global.sh/.bundle-manifest):"
for o in "${ORPHANS[@]}"; do
  echo "  - $o"
done
echo ""
echo "Si de verdad no lo usa nada, considerar borrarlo. Si es una pieza nueva"
echo "que todavía no se conectó, conectarla (agregar el caller real) antes de"
echo "darla por terminada -- construir algo y no usarlo vale lo mismo que no"
echo "construirlo."
exit 1
