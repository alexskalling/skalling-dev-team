#!/usr/bin/env bash
# scripts/merge-helper.sh — Asiste en resolución de conflictos de OKF bundle.
#
# Uso: bash scripts/merge-helper.sh [--target /path/to/project]
#
# Detecta:
#   - Archivos `.opencode/**` en estado de conflicto git.
#   - Decisiones ADRs con el mismo nombre en distintas branches.
#   - Conflictos en log.md / index.md (que con merge=union se auto-resuelven).
#   - Conflictos en workflow.json (lock).
#
# Para cada conflicto, sugiere la acción correcta.

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# LIBRERÍA COMPARTIDA
# ──────────────────────────────────────────────────────────────────────────────

# shellcheck source=lib/lib-os.sh
source "$(dirname "$0")/lib/lib-os.sh"

skalling_log_os

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_DIR="$(pwd)"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) PROJECT_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            sed -n '2,15p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

c_green='\033[32m'
c_yellow='\033[33m'
c_blue='\033[36m'
c_red='\033[31m'
c_reset='\033[0m'

log()  { printf "  ${c_blue}ℹ${c_reset} %s\n" "$*"; }
ok()   { printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
warn() { printf "  ${c_yellow}⚠${c_reset} %s\n" "$*" >&2; }
err()  { printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# 1. Detectar si hay un merge de git en curso
# ──────────────────────────────────────────────────────────────────────────────

check_git_merge_in_progress() {
    if [[ -d "$PROJECT_DIR/.git" ]] && [[ -f "$PROJECT_DIR/.git/MERGE_HEAD" ]]; then
        log "Git merge en curso detectado"
        return 0
    fi
    return 1
}

# ──────────────────────────────────────────────────────────────────────────────
# 2. Detectar archivos `.opencode/` con conflictos
# ──────────────────────────────────────────────────────────────────────────────

find_opencode_conflicts() {
    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        warn "No es un repositorio git — no hay nada que mergear"
        return 0
    fi

    log "Buscando conflictos en archivos de Skalling (.opencode/)..."

    local conflicted
    conflicted="$(cd "$PROJECT_DIR" && git diff --name-only --diff-filter=U 2>/dev/null | grep -E "(^|/)\.opencode/|/AGENTS\.md$" || true)"

    if [[ -z "$conflicted" ]]; then
        ok "Sin conflictos en archivos de Skalling"
        return 0
    fi

    echo ""
    printf "  ${c_yellow}━━━ Conflictos detectados ━━━${c_reset}\n"

    local file
    while IFS= read -r file; do
        echo ""
        printf "  ${c_yellow}⚠${c_reset}  %s\n" "$file"
        suggest_resolution "$file"
    done <<< "$conflicted"
}

# ──────────────────────────────────────────────────────────────────────────────
# 3. Sugerir resolución por tipo de archivo
# ──────────────────────────────────────────────────────────────────────────────

suggest_resolution() {
    local file="$1"
    local basename; basename="$(basename "$file")"
    local dir; dir="$(dirname "$file")"

    case "$file" in
        */.opencode/state/workflow.json)
            cat <<EOF
    [Tipo] Estado del workflow (lock — no auto-mergeable)

    [Problema] Alguien más está corriendo un ciclo activo.
    Conflictos en este archivo SIEMPRE requieren coordinación.

    [Resolución]
      1. Hablar con el otro dev: ¿quién continúa el ciclo?
      2. Si seguís vos: tomar theirs ("git checkout --theirs $file")
      3. Si sigue el otro: tomar ours ("git checkout --ours $file")
      4. Si ambos terminaron ciclos diferentes: regenerar manualmente
         (workflow.json refleja el ciclo activo, no histórico)
EOF
            ;;

        */.opencode/context/log.md)
            cat <<EOF
    [Tipo] Log cronológico del bundle OKF (merge=union)

    [Problema] NO debería entrar en conflicto si .gitattributes está aplicado.
    Si entra, significa que .opencode/.gitattributes no se aplicó.

    [Resolución]
      1. Verificar que .opencode/.gitattributes tenga:
           '.opencode/context/log.md merge=union'
      2. Si está pero el merge ocurrió sin la regla, resolver manualmente:
           - Conservar AMBAS secciones (es append-only)
           - Quitar los marcadores de conflicto <<<<<<<, =======, >>>>>>>
           - Ordenar cronológicamente si es posible
EOF
            ;;

        */.opencode/context/index.md)
            cat <<EOF
    [Tipo] Índice del bundle OKF (regenerable)

    [Resolución]
      1. Conservar ambas versiones (union ya las concatena).
      2. O regenerar: 'rm $file && bash $REPO_ROOT/bootstrap-context.sh --only-detection'
      3. Pau se encarga de deduplicar si es necesario.
EOF
            ;;

        */.opencode/context/decisiones/*)
            cat <<EOF
    [Tipo] ADR (Architecture Decision Record)

    [Problema probable] Dos devs crearon ADRs con el mismo nombre (YYYY-MM-DD-titulo.md)
    pero distinto contenido.

    [Resolución]
      1. Leer ambos ADRs y entender qué decidieron.
      2. Si son la misma decisión con distinta versión:
         - Mantener la más completa
         - La otra pasa a superseded by [link]
      3. Si son decisiones distintas:
         - Renombrar una (ej. añadir sufijo del autor o fecha)
      4. Si son conflictivas:
         - Escalar al equipo: hay una decisión contradictoria que resolver
EOF
            ;;

        */.opencode/context/trabajo-en-curso/*)
            cat <<EOF
    [Tipo] Feature en curso

    [Problema probable] Dos devs trabajando en features distintas
    con el mismo slug, o el mismo feature con distintas versiones de status.

    [Resolución]
      1. Si son features diferentes: una debe renombrarse.
      2. Si es la misma feature: serializar el trabajo.
         - Una persona termina su ciclo, commitea, avisa
         - La otra espera o usa git worktree
      3. Pau consolida los WorkInProgress al final.
EOF
            ;;

        */.opencode/context/stack/*)
            cat <<EOF
    [Tipo] Concept doc de stack (auto-detectable)

    [Resolución]
      1. La detección de stack debería ser regenerable, no commiteable.
      2. Considerar agregar a .gitignore los concept docs de stack/.
      3. O aceptar el cambio y regenerar con /skalling-refresh.
EOF
            ;;

        */.opencode/context/proyecto/*)
            cat <<EOF
    [Tipo] Concept doc del proyecto

    [Resolución]
      1. Leer ambas versiones.
      2. Si una es más completa, esa gana.
      3. Si son complementarias, mergear manualmente.
      4. Actualizar el log.md con la resolución.
EOF
            ;;

        */.opencode/context/preferencias/*)
            cat <<EOF
    [Tipo] Preferencia del equipo

    [Problema probable] Dos devs definieron preferencias contradictorias.

    [Resolución]
      1. Escalar al equipo — preferencias son decisiones colectivas.
      2. Una gana, la otra se descarta o se refina.
      3. Actualizar log.md con la decisión.
EOF
            ;;

        */.opencode/context/problemas-conocidos/*)
            cat <<EOF
    [Tipo] Workaround o problema conocido

    [Resolución]
      1. Si son problemas distintos: ambos deben quedar (renombrar si colisionan).
      2. Si es el mismo problema con distinta solución: la mejor gana.
      3. Si un workaround ya no aplica: marcarlo como resuelto y archivar.
EOF
            ;;

        */.opencode/changes/*/proposal.md|*/.opencode/changes/*/design.md|*/.opencode/changes/*/tasks.md)
            local feature; feature="$(basename "$(dirname "$(dirname "$file")")")"
            cat <<EOF
    [Tipo] Artefacto SDD del feature "$feature"

    [Problema probable] Dos devs trabajaron en el MISMO feature-slug.

    [Resolución]
      1. Serializar: uno espera al otro.
      2. Si los cambios son compatibles: mergear manualmente preservando
         la estructura SDD (proposal → specs → design → tasks).
      3. Si son contradictorios: replantear el feature, una versión gana.
      4. Pau archiva el conflictivo y crea un nuevo change si es necesario.
EOF
            ;;

        */.opencode/project.yaml)
            cat <<EOF
    [Tipo] Project config (regenerable)

    [Resolución]
      1. Conservar la versión más reciente o más completa.
      2. O regenerar: 'bash $REPO_ROOT/bootstrap-context.sh --force'
EOF
            ;;

        */.opencode/context/constitucion.md)
            cat <<EOF
    [Tipo] Constitución per-project (lock)

    [Problema] Cambios en constitución requieren consenso del equipo.
    Conflictos aquí son SEÑAL de que hay un desacuerdo sobre las reglas.

    [Resolución]
      1. NO resolver en merge. Escalar al equipo.
      2. Decidir qué regla gana.
      3. Aplicar manualmente y commitear con mensaje claro.
EOF
            ;;

        *)
            cat <<EOF
    [Tipo] Desconocido (revisar manualmente)

    [Acción] Abrir el archivo y resolver como cualquier otro markdown.
EOF
            ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────────────
# 4. Detectar conflictos "soft" (mismo nombre, distinto autor)
# ──────────────────────────────────────────────────────────────────────────────

detect_name_collisions() {
    log "Buscando colisiones de nombres entre branches..."

    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        return 0
    fi

    local current_branch
    current_branch="$(cd "$PROJECT_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    [[ -z "$current_branch" ]] && return 0

    local other_branches
    other_branches="$(cd "$PROJECT_DIR" && git branch --list --no-color 2>/dev/null | grep -v "^\*" | head -5 || true)"
    if [[ -z "$other_branches" ]]; then
        ok "No hay otras branches para comparar"
        return 0
    fi

    local collisions=0
    while IFS= read -r branch; do
        branch="${branch## }"  # trim

        # Comparar decisiones del bundle
        local diff_files
        diff_files="$(cd "$PROJECT_DIR" && git diff --name-only "$branch"..."$current_branch" -- ".opencode/context/decisiones/" 2>/dev/null | grep "^[<>]" || true)"

        if [[ -n "$diff_files" ]]; then
            collisions=$((collisions + 1))
            echo ""
            printf "  ${c_yellow}⚠${c_reset}  Branch '%s' tiene cambios en decisiones/\n" "$branch"
            echo "$diff_files" | head -10
            echo "    Acción: revisar si hay colisiones de nombre antes de mergear."
        fi
    done <<< "$other_branches"

    if [[ "$collisions" -eq 0 ]]; then
        ok "Sin colisiones de nombres entre branches"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    log "Skalling Merge Helper"
    log "Project: $PROJECT_DIR"
    if [[ "$DRY_RUN" == true ]]; then
        warn "Modo dry-run"
    fi
    echo ""

    if check_git_merge_in_progress; then
        find_opencode_conflicts
        echo ""
        log "Si resolviste los conflictos manualmente:"
        log "  git add <archivos>"
        log "  git commit"
    else
        log "No hay merge en curso. Modo preventivo:"
        echo ""
        detect_name_collisions
        echo ""
        log "Para iniciar análisis durante un merge:"
        log "  bash $REPO_ROOT/scripts/merge-helper.sh"
    fi

    echo ""
    log "Tips generales:"
    cat <<EOF
  • Concept docs con NOMBRES distintos = no hay conflicto, mergea solo.
  • log.md con merge=union (si .gitattributes aplicado) = auto-resuelto.
  • workflow.json con merge=lock = SIEMPRE coordinación con el otro dev.
  • Un feature = un branch de git = menos conflictos.
  • Para features grandes: usar 'git worktree' y mergear al final.
EOF
}

main
