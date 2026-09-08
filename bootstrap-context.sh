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
[ -d "$DATA_DIR" ] || DATA_DIR="$SCRIPT_DIR/skalling-data"
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

c_green='\033[32m'
c_yellow='\033[33m'
c_blue='\033[36m'
c_red='\033[31m'
c_reset='\033[0m'

log() { printf "  ${c_blue}ℹ${c_reset} %s\n" "$*"; }
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
    run mkdir -p "$CONTEXT_DIR"
    ok "Directorio de TeamDB preparado (sin plantillas Markdown)"
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
            # Reemplazar también cuando no hay detección. Dejar el catálogo del
            # template hace que consumidores lo confundan con valores reales.
            skalling_sed_inplace "$yaml_path" "s|${key}: \[.*\]|${key}: ${val}|g"
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
    [[ "$DRY_RUN" == true ]] && return 0
    if [[ "$(get_detected has_ui)" == "true" ]]; then
        local found
        found="$(sqlite3 "$CONTEXT_DIR/team.db" "SELECT count(*) FROM concepts WHERE slug='design-system' AND length(body_md)>0")"
        [[ "$found" -gt 0 ]] || { err "Falta concepto design-system en TeamDB"; return 1; }
        ok "Evidencia de diseño disponible en TeamDB; validar contra el código para cada pedido"
    fi
}

CODEGRAPH_STATUS="unavailable"
init_codegraph() {
    if [[ -d "$PROJECT_DIR/.codegraph" ]]; then
        ok "CodeGraph presente"
        CODEGRAPH_STATUS="ready"
        return 0
    fi
    if command -v gentle-ai >/dev/null 2>&1 && gentle-ai codegraph init --cwd "$PROJECT_DIR" >/dev/null 2>&1; then
        ok "CodeGraph inicializado"
        CODEGRAPH_STATUS="ready"
        return 0
    fi
    if command -v codegraph >/dev/null 2>&1 && codegraph init "$PROJECT_DIR" >/dev/null 2>&1; then
        ok "CodeGraph inicializado con CLI"
        CODEGRAPH_STATUS="ready"
        return 0
    fi
    if ! command -v gentle-ai >/dev/null 2>&1 && ! command -v codegraph >/dev/null 2>&1; then
        warn "CodeGraph no disponible; los agentes deberán usar lectura directa"
        CODEGRAPH_STATUS="unavailable"
        return 0
    fi
    warn "CodeGraph no pudo inicializarse; el proyecto queda sin inteligencia estructural"
    CODEGRAPH_STATUS="failed"
}

hydrate_project_context() {
    local codegraph_status="$1"
    local hydrator="$SCRIPT_DIR/scripts/skalling-bootstrap-context.py"
    if [[ ! -f "$hydrator" ]]; then
        err "Falta skalling-bootstrap-context.py; no se puede validar preparación"
        return 1
    fi
    local result
    if ! result="$(python3 "$hydrator" --project "$PROJECT_DIR" --codegraph "$codegraph_status")"; then
        err "Proyecto degradado: falta contexto real o evidencia visual"
        [[ -n "$result" ]] && printf '  %s\n' "$result" >&2
        return 1
    fi
    ok "Contexto real guardado en TeamDB"
    printf '  %s\n' "$result"
}

# ──────────────────────────────────────────────────────────────────────────────
# R10 — TEAMDB (libSQL)
# ──────────────────────────────────────────────────────────────────────────────

init_teamdb() {
    local project="$1"
    if [[ "$DRY_RUN" == true ]]; then
        log "[dry-run] teamdb se inicializaría y validaría"
        return 0
    fi
    if command -v sqlite3 >/dev/null 2>&1; then
        if [[ -f "$SCRIPT_DIR/scripts/teamdb-init.sh" ]]; then
            # bootstrap es ejecutado por Alex → seteamos TEAMDB_ACTOR=alex
            # para que audit_log refleje el actor real (INV-AUDIT-1).
            if TEAMDB_ACTOR=alex bash "$SCRIPT_DIR/scripts/teamdb-init.sh" "$project" 2>/dev/null; then
                ok "teamdb inicializado"
                if [[ -f "$SCRIPT_DIR/scripts/teamdb-link.sh" ]]; then
                    TEAMDB_ACTOR=alex bash "$SCRIPT_DIR/scripts/teamdb-link.sh" "$project" --quiet >/dev/null
                    ok "grafo de memoria actualizado"
                fi
            else
                err "teamdb no se pudo inicializar"
                return 1
            fi
        else
            err "scripts/teamdb-init.sh no encontrado"
            return 1
        fi
    else
        err "sqlite3 no disponible"
        return 1
    fi
}

activate_teamdb_hooks() {
    local project="$1"
    if [[ ! -d "$project/.git" ]]; then
        return 0
    fi
    local hooks_src="$SCRIPT_DIR/scripts/hooks"
    [[ -d "$hooks_src" ]] || hooks_src="$SCRIPT_DIR/hooks"
    local hooks_dst="$project/.git/hooks"
    if [[ ! -d "$hooks_src" ]]; then
        return 0
    fi
    local installed=0
    # Loop explícito: pre-commit (seal+inmutabilidad), post-merge (import),
    # pre-push (gate de push). Agregar un hook nuevo acá.
    for hook in pre-commit post-merge pre-push; do
        if [[ -f "$hooks_src/$hook" ]]; then
            run cp "$hooks_src/$hook" "$hooks_dst/$hook"
            run chmod +x "$hooks_dst/$hook"
            installed=$((installed + 1))
        fi
    done
    if [[ "$installed" -gt 0 ]]; then
        ok "teamdb hooks activados ($installed)"
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

    if [[ -f "$CONTEXT_DIR/team.db" && "$FORCE" == false && "$DRY_RUN" == false && "$ONLY_DETECTION" == false ]]; then
        err "El proyecto ya está inicializado. Usá --force solo para una reparación consciente."
        return 4
    fi

    detect_stack

    if [[ "$ONLY_DETECTION" == true ]]; then
        exit 0
    fi

    skalling_require_dependencies
    generate_bundle
    generate_project_yaml
    init_teamdb "$PROJECT_DIR"
    if [[ "$DRY_RUN" == false ]]; then
        init_codegraph
        if ! hydrate_project_context "$CODEGRAPH_STATUS"; then
            err "Bootstrap incompleto: Skalling no habilitará implementación"
            return 3
        fi
    fi
    activate_teamdb_hooks "$PROJECT_DIR"
    check_design_md

    echo ""
    ok "Bootstrap completo — memoria inicializada; comprensión del pedido pendiente"
    echo ""
    cat <<EOF
  Bundle OKF: $CONTEXT_DIR
  Project YAML: $OPENCODE_DIR/project.yaml
  Diseño: concepto design-system en TeamDB (cuando hay UI)

  Próximo paso: abrí opencode y empezá a trabajar.
EOF
}

main
