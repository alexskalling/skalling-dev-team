#!/usr/bin/env bash
# bootstrap-context.sh — Inicializa el bundle OKF en un proyecto.
#
# Detecta stack, genera concept docs iniciales, crea project.yaml.
# Es invocado por /skalling-init (por Alex) o manualmente.
#
# Uso:
#   bash bootstrap-context.sh                    # bootstrap en directorio actual
#   bash bootstrap-context.sh --target /path/proj # bootstrap en proyecto específico
#   bash bootstrap-context.sh --dry-run          # ver qué haría sin tocar
#   bash bootstrap-context.sh --force            # regenerar sin preguntar
#   bash bootstrap-context.sh --only-detection   # solo detecta, no escribe

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# LIBRERÍA COMPARTIDA
# ──────────────────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/lib-os.sh
source "$(dirname "$0")/scripts/lib/lib-os.sh"

# shellcheck source=scripts/lib/lib-stack-detect.sh
source "$(dirname "$0")/scripts/lib/lib-stack-detect.sh"

skalling_log_os

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
DATA_DIR="$SCRIPT_DIR/data"
STACK_DETECTORS_YAML="$DATA_DIR/stack-detectors.yaml"

PROJECT_DIR="$(pwd)"
OPENCODE_DIR="$PROJECT_DIR/.opencode"
CONTEXT_DIR="$OPENCODE_DIR/context"
DRY_RUN=false
FORCE=false
ONLY_DETECTION=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) PROJECT_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --only-detection) ONLY_DETECTION=true; shift ;;
        --help|-h)
            sed -n '2,12p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

OPENCODE_DIR="$PROJECT_DIR/.opencode"
CONTEXT_DIR="$OPENCODE_DIR/context"
DOCS_DESIGN_DIR="$CONTEXT_DIR/proyecto"

c_green='\033[32m'
c_yellow='\033[33m'
c_blue='\033[36m'
c_red='\033[31m'
c_reset='\033[0m'

log() { local level="$1"; shift; printf "  ${c_blue}ℹ${c_reset} %s\n" "$*"; }
ok() { printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
warn() { printf "  ${c_yellow}⚠${c_reset} %s\n" "$*" >&2; }
err() { printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Variables detectadas (via lib-stack-detect.sh)
# ──────────────────────────────────────────────────────────────────────────────

# Wrapper para mantener compatibilidad con el código existente
# (usa skalling_detected_<key> de la lib)
set_detected() {
    skalling_set_detected "$@"
}

get_detected() {
    skalling_get_detected "$@"
}

# ──────────────────────────────────────────────────────────────────────────────
# DETECCIÓN DE STACK (data-driven via stack-detectors.yaml)
# ──────────────────────────────────────────────────────────────────────────────

detect_stack() {
    log "Detectando stack (data-driven desde stack-detectors.yaml)..."

    skalling_init_detected

    if [[ -f "$STACK_DETECTORS_YAML" ]]; then
        skalling_detect_from_yaml "$STACK_DETECTORS_YAML" "$PROJECT_DIR"
    else
        warn "stack-detectors.yaml no encontrado en $DATA_DIR"
        warn "Fallback: detección básica deshabilitada. Creá el data file."
        return 0
    fi

    log "Stack detectado:"
    local key
    for key in language runtime framework test_runner package_manager has_ui; do
        local val; val="$(get_detected "$key")"
        if [[ -n "$val" ]]; then
            printf "       %s: %s\n" "$key" "$val"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# GENERACIÓN DEL BUNDLE OKF
# ──────────────────────────────────────────────────────────────────────────────

generate_bundle() {
    log "Generando bundle OKF en $CONTEXT_DIR"

    # Directorios
    run mkdir -p "$CONTEXT_DIR"
    for dir in stack proyecto decisiones trabajo-en-curso preferencias problemas-conocidos; do
        run mkdir -p "$CONTEXT_DIR/$dir"
    done
    # design-system.md se crea en CONTEXT_DIR/proyecto/ (R13, solo OKF bundle)

    local project_name="${PROJECT_DIR##*/}"

    # README.md del bundle
    run cp "$TEMPLATES_DIR/okf/README.template.md" "$CONTEXT_DIR/README.md"
    if [[ "$DRY_RUN" == false ]]; then
        skalling_sed_inplace "$CONTEXT_DIR/README.md" "s|\[Bundle name\]|${project_name}|g"
    fi

    # index.md
    run cp "$TEMPLATES_DIR/okf/index.template.md" "$CONTEXT_DIR/index.md"

    # log.md
    run cp "$TEMPLATES_DIR/okf/log.template.md" "$CONTEXT_DIR/log.md"
    if [[ "$DRY_RUN" == false ]]; then
        # Append atómico para evitar corrupción si crashea
        local log_entry
        log_entry="$(printf '\n## %s — Bootstrap inicial\n**Por:** alex\n**Acción:** Bundle OKF creado con detección automática.\n**Path:** `.opencode/context/` completo\n**Razón:** Primer arranque de Skalling en este proyecto.' "$(date +%Y-%m-%d\ %H:%M)")"
        skalling_atomic_append "$CONTEXT_DIR/log.md" "$log_entry"
    fi

    # Index por carpeta
    run cp "$TEMPLATES_DIR/okf/stack-index.template.md" "$CONTEXT_DIR/stack/index.md"
    run cp "$TEMPLATES_DIR/okf/proyecto-index.template.md" "$CONTEXT_DIR/proyecto/index.md"
    run cp "$TEMPLATES_DIR/okf/decisiones-index.template.md" "$CONTEXT_DIR/decisiones/index.md"
    run cp "$TEMPLATES_DIR/okf/trabajo-en-curso-index.template.md" "$CONTEXT_DIR/trabajo-en-curso/index.md"
    run cp "$TEMPLATES_DIR/okf/preferencias-index.template.md" "$CONTEXT_DIR/preferencias/index.md"
    run cp "$TEMPLATES_DIR/okf/problemas-conocidos-index.template.md" "$CONTEXT_DIR/problemas-conocidos/index.md"

    # Concept docs detectados
    local language; language="$(get_detected language)"
    if [[ -n "$language" ]]; then
        run cp "$TEMPLATES_DIR/okf/stack-concept.template.md" "$CONTEXT_DIR/stack/backend.md"
        if [[ "$DRY_RUN" == false ]]; then
            skalling_sed_inplace "$CONTEXT_DIR/stack/backend.md" "s|\[Componente del stack\]|Backend stack (${language})|g"
            skalling_sed_inplace "$CONTEXT_DIR/stack/backend.md" "s|\[Framework / librería / runtime detectado\]|${language} runtime|g"
        fi

        local has_ui; has_ui="$(get_detected has_ui)"
        local framework; framework="$(get_detected framework)"
        if [[ "$has_ui" == "true" ]]; then
            run cp "$TEMPLATES_DIR/okf/stack-concept.template.md" "$CONTEXT_DIR/stack/frontend.md"
            if [[ "$DRY_RUN" == false ]]; then
                skalling_sed_inplace "$CONTEXT_DIR/stack/frontend.md" "s|\[Componente del stack\]|Frontend stack (${framework})|g"
                skalling_sed_inplace "$CONTEXT_DIR/stack/frontend.md" "s|\[Framework / librería / runtime detectado\]|${framework} UI framework|g"
            fi
        fi

        local test_runner; test_runner="$(get_detected test_runner)"
        if [[ -n "$test_runner" ]]; then
            run cp "$TEMPLATES_DIR/okf/stack-concept.template.md" "$CONTEXT_DIR/stack/testing.md"
            if [[ "$DRY_RUN" == false ]]; then
                skalling_sed_inplace "$CONTEXT_DIR/stack/testing.md" "s|\[Componente del stack\]|Testing (${test_runner})|g"
                skalling_sed_inplace "$CONTEXT_DIR/stack/testing.md" "s|\[Framework / librería / runtime detectado\]|${test_runner} test runner|g"
            fi
        fi
    fi

    # Proyecto / que-es.md
    run cp "$TEMPLATES_DIR/okf/proyecto-que-es.template.md" "$CONTEXT_DIR/proyecto/que-es.md"
    if [[ "$DRY_RUN" == false ]]; then
        local desc; desc="$(get_detected description)"
        [[ -z "$desc" ]] && desc="Sin descripción detectada."
        skalling_sed_inplace "$CONTEXT_DIR/proyecto/que-es.md" "s|\[Nombre del proyecto\]|${project_name}|g"
        skalling_sed_inplace "$CONTEXT_DIR/proyecto/que-es.md" "s|\[Una línea del README\]|${desc}|g"
    fi

    # .gitattributes para estrategias de merge (R15)
    if [[ -f "$TEMPLATES_DIR/gitattributes.template" ]]; then
        run cp "$TEMPLATES_DIR/gitattributes.template" "$OPENCODE_DIR/.gitattributes"
        if [[ "$DRY_RUN" == false ]]; then
            log "  ✓ .gitattributes instalado (estrategias de merge R15)"
        fi
    fi

    # Verificar size del bundle (R-MEMORY-SIZE-LIMIT)
    if [[ "$DRY_RUN" == false ]]; then
        local size_status
        size_status="$(skalling_check_bundle_size "$CONTEXT_DIR")"
        log "Bundle size: $size_status"
    fi

    ok "Bundle OKF generado"
}

# ──────────────────────────────────────────────────────────────────────────────
# PROJECT.YAML
# ──────────────────────────────────────────────────────────────────────────────

generate_project_yaml() {
    log "Generando .opencode/project.yaml"
    local yaml_path="$OPENCODE_DIR/project.yaml"
    local ts; ts="$(date +%Y-%m-%dT%H:%M:%S%z)"

    if [[ -f "$yaml_path" && "$FORCE" == false ]]; then
        warn "project.yaml ya existe (usá --force para sobrescribir)"
        return 0
    fi

    run cp "$TEMPLATES_DIR/project.yaml.template" "$yaml_path"

    if [[ "$DRY_RUN" == false ]]; then
        skalling_sed_inplace "$yaml_path" "s|detected_at: YYYY-MM-DDTHH:MM:SSZ|detected_at: ${ts}|g"

        local key val
        for key in language runtime framework package_manager test_runner linter formatter; do
            val="$(get_detected "$key")"
            if [[ -n "$val" ]]; then
                # Replace pattern "[key: ...]" with actual value
                skalling_sed_inplace "$yaml_path" "s|${key}: \[.*\]|${key}: ${val}|g"
            fi
        done

        # Frontend
        local has_ui; has_ui="$(get_detected has_ui)"
        skalling_sed_inplace "$yaml_path" "s|^  has_ui: false$|  has_ui: ${has_ui}|g"
        local framework; framework="$(get_detected framework)"
        skalling_sed_inplace "$yaml_path" "s|^  ui_framework: \"\"$|  ui_framework: ${framework:-}|g"
    fi

    ok "project.yaml generado"
}

# ──────────────────────────────────────────────────────────────────────────────
# REGLA #13 — design-system.md
# ──────────────────────────────────────────────────────────────────────────────

check_design_md() {
    local has_ui; has_ui="$(get_detected has_ui)"
    if [[ "$has_ui" != "true" ]]; then
        return 0
    fi

    if [[ -f "$CONTEXT_DIR/proyecto/design-system.md" ]]; then
        ok "design-system.md presente (REGLA #13 OK)"
        return 0
    fi

    warn "REGLA #13: Frontend detectado pero falta design-system.md en bundle OKF"
    log "  Sugerencia: correr /impeccable document o crear manualmente."
}

# ──────────────────────────────────────────────────────────────────────────────
# R10 — TEAMDB (libSQL)
# ──────────────────────────────────────────────────────────────────────────────

init_teamdb() {
    local project="$1"
    if command -v sqlite3 >/dev/null 2>&1; then
        if [[ -f "$SCRIPT_DIR/scripts/teamdb-init.sh" ]]; then
            if bash "$SCRIPT_DIR/scripts/teamdb-init.sh" "$project" 2>/dev/null; then
                ok "teamdb inicializado"
            else
                warn "teamdb no se pudo inicializar"
            fi
        else
            warn "scripts/teamdb-init.sh no encontrado, skip teamdb"
        fi
    else
        warn "sqlite3 no disponible, teamdb no se inicializó"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    log "Iniciando bootstrap de Skalling"
    log "Target: $PROJECT_DIR"
    if [[ "$DRY_RUN" == true ]]; then
        warn "Modo dry-run — no se modifica nada"
    fi
    echo ""

    detect_stack

    if [[ "$ONLY_DETECTION" == true ]]; then
        exit 0
    fi

    generate_bundle
    generate_project_yaml
    init_teamdb "$PROJECT_DIR"
    check_design_md

    echo ""
    ok "Bootstrap completo"
    echo ""
    cat <<EOF
  Bundle OKF: $CONTEXT_DIR
  Project YAML: $OPENCODE_DIR/project.yaml
  design-system.md: $([[ -f "$CONTEXT_DIR/proyecto/design-system.md" ]] && echo "✓ presente" || echo "⚠ frontend requiere uno")

  Próximo paso: abrí opencode y empezá a trabajar.
EOF
}

main
