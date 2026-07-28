#!/usr/bin/env bash
# scripts/update.sh — Actualiza Skalling desde el repo source.
#
# Uso:
#   bash scripts/update.sh                    # actualiza desde cwd
#   bash scripts/update.sh --repo /path       # actualiza desde repo específico
#   bash scripts/update.sh --check-only       # solo verificar, no instalar
#   bash scripts/update.sh --dry-run          # ver qué haría sin tocar
#
# Comportamiento:
#   1. Busca el repo de Skalling (skalling-dev-team).
#   2. Hace git fetch para ver cambios.
#   3. Compara HEAD con origin/main.
#   4. Si hay cambios, muestra el changelog.
#   5. Espera confirmación del usuario (stdin) para instalar.
#   6. Hace pull + re-ejecuta install-global.sh --force.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_ONLY=false
DRY_RUN=false
SKALLING_REPO=""

c_green='\033[32m'
c_yellow='\033[33m'
c_red='\033[31m'
c_blue='\033[36m'
c_reset='\033[0m'

ok()   { printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
warn() { printf "  ${c_yellow}⚠${c_reset} %s\n" "$*" >&2; }
err()  { printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
info() { printf "  ${c_blue}ℹ${c_reset} %s\n" "$*"; }

# ──────────────────────────────────────────────────────────────────────────────
# PARSEO
# ──────────────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) SKALLING_REPO="$2"; shift 2 ;;
        --check-only) CHECK_ONLY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            sed -n '3,12p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

# ──────────────────────────────────────────────────────────────────────────────
# LOCALIZAR REPO
# ──────────────────────────────────────────────────────────────────────────────

locate_repo() {
    if [[ -n "$SKALLING_REPO" ]]; then
        if [[ -d "$SKALLING_REPO/.git" ]]; then
            REPO_DIR="$SKALLING_REPO"
            return 0
        else
            err "El directorio especificado no es un repo git: $SKALLING_REPO"
            return 1
        fi
    fi

    # Buscar en ubicaciones comunes
    local candidates=(
        "$SCRIPT_DIR/.."  # scripts/ -> raíz del repo
        "$HOME/skalling-dev-team"
        "$HOME/Proyectos/skalling-dev-team"
        "$HOME/dev/skalling-dev-team"
        "$HOME/Documents/skalling-dev-team"
    )

    for dir in "${candidates[@]}"; do
        local canonical
        canonical="$(cd "$dir" 2>/dev/null && pwd)"
        if [[ -d "$canonical/.git" && -f "$canonical/install-global.sh" ]]; then
            REPO_DIR="$canonical"
            info "Repo encontrado: $REPO_DIR"
            return 0
        fi
    done

    err "No se encontró el repo Skalling. Usá --repo /ruta/al/skalling-dev-team"
    return 1
}

# ──────────────────────────────────────────────────────────────────────────────
# VERIFICAR ACTUALIZACIONES
# ──────────────────────────────────────────────────────────────────────────────

check_updates() {
    info "Verificando actualizaciones en $REPO_DIR..."

    cd "$REPO_DIR"

    if ! git fetch origin 2>/dev/null; then
        err "No se pudo conectar con origin. Sin internet?"
        return 1
    fi

    local behind
    behind="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "0")"

    if [[ "$behind" == "0" ]]; then
        echo ""
        ok "Ya estás en la última versión."
        return 0
    fi

    echo ""
    info "Hay $behind commits nuevos:"
    echo ""
    git log HEAD..origin/main --oneline --no-decorate 2>/dev/null | head -20

    echo ""
    info "Cambios en CHANGELOG:"
    echo ""
    git diff HEAD..origin/main -- CHANGELOG.md 2>/dev/null | grep "^+" | grep -v "^\+\+\+" | head -15 | sed 's/^+/  /'

    return 2  # código especial: hay cambios
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALAR
# ──────────────────────────────────────────────────────────────────────────────

do_update() {
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] git pull origin main"
        info "[dry-run] bash install-global.sh --force"
        ok "Dry-run completo. No se modificó nada."
        return 0
    fi

    cd "$REPO_DIR"

    info "Descargando cambios..."
    if ! git pull origin main; then
        err "Error al hacer pull. Revisá conflictos."
        return 1
    fi

    info "Reinstalando Skalling en ~/.config/opencode/..."
    if ! bash install-global.sh --force; then
        err "Error al instalar. Revisá el output."
        return 1
    fi

    local new_head
    new_head="$(git rev-parse --short HEAD 2>/dev/null || echo "desconocido")"
    echo ""
    ok "Skalling actualizado a $new_head"
    info "Corré /skalling-doctor para verificar."
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    info "=== Skalling Update ==="
    echo ""

    if ! locate_repo; then
        exit 1
    fi

    set +e
    check_updates
    local check_result=$?
    set -e

    if [[ $check_result -eq 0 ]]; then
        exit 0
    fi

    if [[ $check_result -eq 1 ]]; then
        exit 1
    fi

    # check_result == 2 → hay cambios
    if [[ "$CHECK_ONLY" == true ]]; then
        info "Modo check-only. No se instala nada."
        exit 0
    fi

    echo ""
    warn "Se requiere confirmación para instalar."
    echo ""
    printf "¿Procedo con la actualización? (s/N): "
    read -r respuesta
    echo ""

    case "$respuesta" in
        s|S|si|sí|y|yes)
            do_update
            ;;
        *)
            info "Actualización cancelada por el usuario."
            exit 0
            ;;
    esac
}

main
