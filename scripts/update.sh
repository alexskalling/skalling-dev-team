#!/usr/bin/env bash
# scripts/update.sh — Actualiza Skalling desde el repo source.
#
# Uso:
#   bash scripts/update.sh                    # actualiza desde cwd
#   bash scripts/update.sh --repo /path       # actualiza desde repo específico
#   bash scripts/update.sh --check-only       # solo verificar, no instalar
#   bash scripts/update.sh --dry-run          # ver qué haría sin tocar
#   bash scripts/update.sh --channel main     # mantenedores: seguir main
#
# Comportamiento:
#   1. Busca el repo de Skalling (skalling-dev-team).
#   2. Hace git fetch de los tags publicados.
#   3. Compara HEAD con el último release vX.Y.Z (canal por defecto).
#      Con SKALLING_REQUIRE_SIGNED_TAGS=1 exige que el tag esté firmado.
#   4. Si hay cambios, muestra el changelog.
#   5. Espera confirmación del usuario (stdin) para instalar.
#   6. Cambia al release + re-ejecuta install-global.sh con backup; si la
#      instalación falla vuelve a la versión anterior.
#
# Por qué releases y no main: main recibe trabajo en curso. Un equipo debe
# instalar solo versiones publicadas y verificadas por CI, no el último push.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_ONLY=false
DRY_RUN=false
SKALLING_REPO=""
CHANNEL="${SKALLING_UPDATE_CHANNEL:-release}"
TARGET=""
PROJECT_TARGET=""
LOCAL_ONLY=false
ASSUME_YES=false

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
        --project) PROJECT_TARGET="${2:?Falta ruta del proyecto}"; shift 2 ;;
        --local-only) LOCAL_ONLY=true; shift ;;
        --yes) ASSUME_YES=true; shift ;;
        --repo) SKALLING_REPO="$2"; shift 2 ;;
        --check-only) CHECK_ONLY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --channel) CHANNEL="$2"; shift 2 ;;
        --help|-h)
            sed -n '3,21p' "${BASH_SOURCE[0]}"
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

    # El checkout que registró install-global.sh; después, ubicaciones comunes.
    local recorded=""
    [[ -f "$SCRIPT_DIR/../skalling-data/source-dir" ]] && recorded="$(head -1 "$SCRIPT_DIR/../skalling-data/source-dir")"
    local candidates=(
        ${recorded:+"$recorded"}
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
    info "Verificando actualizaciones en $REPO_DIR (canal: $CHANNEL)..."

    cd "$REPO_DIR"

    case "$CHANNEL" in
        release)
            if ! git fetch --tags origin 2>/dev/null; then
                err "No se pudo conectar con origin. Sin internet?"
                return 1
            fi
            TARGET="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)"
            if [[ -z "$TARGET" ]]; then
                err "No hay releases publicados (tags vX.Y.Z). Pedí al mantenedor que publique uno."
                return 1
            fi
            if [[ "${SKALLING_REQUIRE_SIGNED_TAGS:-0}" == "1" ]] && ! git verify-tag "$TARGET" >/dev/null 2>&1; then
                err "El release $TARGET no tiene una firma válida; no se instala."
                return 1
            fi
            ;;
        main)
            warn "Canal main: incluye trabajo sin publicar. Solo para mantenedores."
            if ! git fetch origin 2>/dev/null; then
                err "No se pudo conectar con origin. Sin internet?"
                return 1
            fi
            TARGET="origin/main"
            ;;
        *)
            err "Canal desconocido: $CHANNEL (usá release o main)"
            return 1
            ;;
    esac

    if git merge-base --is-ancestor "$TARGET" HEAD 2>/dev/null; then
        echo ""
        ok "Ya estás en la última versión ($TARGET)."
        return 0
    fi

    local behind
    behind="$(git rev-list --count "HEAD..$TARGET" 2>/dev/null || echo "0")"

    echo ""
    info "$TARGET trae $behind commits nuevos:"
    echo ""
    git log "HEAD..$TARGET" --oneline --no-decorate 2>/dev/null | head -20

    echo ""
    info "Cambios en CHANGELOG:"
    echo ""
    git diff "HEAD..$TARGET" -- CHANGELOG.md 2>/dev/null | grep "^+" | grep -v "^\+\+\+" | head -15 | sed 's/^+/  /'

    return 2  # código especial: hay cambios
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALAR
# ──────────────────────────────────────────────────────────────────────────────

do_update() {
    if [[ "$DRY_RUN" == true ]]; then
        info "[dry-run] git checkout $TARGET"
        info "[dry-run] bash install-global.sh"
        ok "Dry-run completo. No se modificó nada."
        return 0
    fi

    cd "$REPO_DIR"

    if [[ -n "$(git status --porcelain)" ]]; then
        err "El repo tiene cambios locales. Guardalos o commitealos antes de actualizar."
        return 1
    fi

    local previous
    previous="$(git rev-parse HEAD)"

    info "Cambiando a $TARGET..."
    if [[ "$CHANNEL" == "main" ]]; then
        if ! git merge --ff-only "$TARGET"; then
            err "No se pudo avanzar a $TARGET sin merge. Revisá la rama local."
            return 1
        fi
    elif ! git -c advice.detachedHead=false checkout --quiet "$TARGET"; then
        err "No se pudo cambiar a $TARGET."
        return 1
    fi

    info "Reinstalando Skalling en ~/.config/opencode/..."
    if ! bash install-global.sh; then
        err "Error al instalar $TARGET. Volviendo a la versión anterior (${previous:0:7})..."
        git -c advice.detachedHead=false checkout --quiet "$previous" && bash install-global.sh >/dev/null 2>&1 \
            && warn "Se restauró la versión anterior." \
            || err "No se pudo restaurar automáticamente; el backup del instalador está en ~/.config/opencode/.skalling-backups/"
        return 1
    fi

    echo ""
    ok "Skalling actualizado a $TARGET ($(git rev-parse --short HEAD))"
    info "Corré /skalling-doctor para verificar."
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

sync_project() {
    [[ -n "$PROJECT_TARGET" ]] || { info "Solo instalación global; proyectos locales no sincronizados."; return 0; }
    if [[ "$CHECK_ONLY" == true || "$DRY_RUN" == true ]]; then
        python3 "$REPO_DIR/scripts/skalling-runtime.py" check --root "$REPO_DIR" --target "$PROJECT_TARGET/.opencode"
        return $?
    fi
    if [[ "$ASSUME_YES" != true ]]; then
        err "Sincronización local pendiente: usar --project <ruta> --yes después de aprobar el cambio"
        return 1
    fi
    bash "$REPO_DIR/setup.sh" --target "$PROJECT_TARGET" </dev/null
    python3 "$REPO_DIR/scripts/skalling-runtime.py" check --root "$REPO_DIR" --target "$PROJECT_TARGET/.opencode"
}

main() {
    echo ""
    info "=== Skalling Update ==="
    echo ""

    if ! locate_repo; then
        exit 1
    fi

    if [[ "$LOCAL_ONLY" == true ]]; then
        [[ -n "$PROJECT_TARGET" ]] || { err "--local-only requiere --project <ruta>"; exit 2; }
        sync_project
        exit $?
    fi
    set +e
    check_updates
    local check_result=$?
    set -e

    if [[ $check_result -eq 0 ]]; then
        sync_project
        exit $?
    fi

    if [[ $check_result -eq 1 ]]; then
        exit 1
    fi

    # check_result == 2 → hay cambios
    if [[ "$CHECK_ONLY" == true ]]; then
        info "Modo check-only. No se instala nada."
        exit 0
    fi

    if [[ "$ASSUME_YES" == true ]]; then
        do_update
        sync_project
        exit $?
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
            sync_project
            ;;
        *)
            info "Actualización cancelada por el usuario."
            exit 0
            ;;
    esac
}

main
