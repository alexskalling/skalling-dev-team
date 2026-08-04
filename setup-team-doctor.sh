#!/usr/bin/env bash
# setup-team-doctor.sh — Health check de la instalación de Skalling.
#
# Valida:
#   - Ambiente (bash, opencode, herramientas requeridas).
#   - Instalación global (~/.config/opencode/).
#   - Instalación per-project (.opencode/ en el directorio actual o target).
#   - Frontmatter de cada agente.
#   - Validez de constitución, templates, skills.
#
# Uso:
#   bash setup-team-doctor.sh                       # chequea global + cwd
#   bash setup-team-doctor.sh --project /path/proj  # chequea global + ese proyecto
#   bash setup-team-doctor.sh --global-only         # solo global
#   bash setup-team-doctor.sh --strict              # exit 1 si hay warnings

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# LIBRERÍA COMPARTIDA
# ──────────────────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/lib-os.sh
source "$(dirname "$0")/scripts/lib/lib-os.sh"

skalling_log_os

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_VERSION="0.6.1"

OPENCODE_DIR="$SKALLING_OPENCODE_DIR"
PROJECT_DIR="$(pwd)"
GLOBAL_ONLY=false
STRICT=false
WARN_COUNT=0
WARN_ENV_COUNT=0
ERROR_COUNT=0
OK_COUNT=0

# ──────────────────────────────────────────────────────────────────────────────
# PARSEO
# ──────────────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_DIR="$2"; shift 2 ;;
        --global-only) GLOBAL_ONLY=true; shift ;;
        --strict) STRICT=true; shift ;;
        --help|-h)
            sed -n '2,12p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────

c_green='\033[32m'
c_yellow='\033[33m'
c_red='\033[31m'
c_blue='\033[36m'
c_reset='\033[0m'

ok()        { OK_COUNT=$((OK_COUNT+1));        printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
warn()      { WARN_COUNT=$((WARN_COUNT+1));      printf "  ${c_yellow}⚠${c_reset} %s\n" "$*" >&2; }
warn_env()  { WARN_ENV_COUNT=$((WARN_ENV_COUNT+1)); printf "  ${c_yellow}⚠${c_reset} %s\n" "$*" >&2; }
err()       { ERROR_COUNT=$((ERROR_COUNT+1));    printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
info()      { printf "  ${c_blue}ℹ${c_reset} %s\n" "$*"; }

section() {
    echo ""
    printf "${c_blue}━━━ %s ━━━${c_reset}\n" "$*"
}

# ──────────────────────────────────────────────────────────────────────────────
# CHECKS
# ──────────────────────────────────────────────────────────────────────────────

check_ambiente() {
    section "Ambiente"

    local major="${BASH_VERSINFO[0]}"
    if [[ "$major" -ge 4 ]]; then
        ok "bash $BASH_VERSION"
    else
        warn_env "bash $BASH_VERSION — los scripts funcionan pero bash >= 4 es recomendado (algunas features avanzadas no disponibles)"
    fi

    if command -v opencode >/dev/null 2>&1; then
        local v; v="$(opencode --version 2>/dev/null || echo 'unknown')"
        ok "opencode $v"
    else
        warn_env "opencode no está en PATH (Skalling funcionará cuando lo instales)"
    fi

    if command -v node >/dev/null 2>&1; then
        local nv; nv="$(node --version 2>/dev/null || echo 'unknown')"
        if [[ "$nv" =~ v(2[2-9]|[3-9][0-9])\. ]]; then
            ok "node $nv (>= 22)"
        else
            warn_env "node $nv — Impeccable requiere >= 22"
        fi
    else
        warn_env "node no está en PATH (necesario para Impeccable)"
    fi

    if command -v git >/dev/null 2>&1; then
        ok "git $(git --version | awk '{print $3}')"
    else
        warn_env "git no está en PATH"
    fi
}

check_global_install() {
    section "Instalación Global ($OPENCODE_DIR)"

    if [[ ! -d "$OPENCODE_DIR" ]]; then
        err "Directorio global no existe. Corré install-global.sh."
        return
    fi
    ok "Directorio existe"

    # Constitución
    if [[ -f "$OPENCODE_DIR/constitucion.md" ]]; then
        local size; size="$(wc -l < "$OPENCODE_DIR/constitucion.md" | tr -d ' ')"
        ok "Constitución presente ($size líneas)"
        # Validar que tenga las reglas clave
        if grep -q "^## 🏛️ Reglas Base" "$OPENCODE_DIR/constitucion.md"; then
            ok "Sección Reglas Base presente"
        else
            err "Falta sección Reglas Base en constitución"
        fi
        if grep -q "R13" "$OPENCODE_DIR/constitucion.md"; then
            ok "REGLA #13 (design-system.md) presente"
        else
            warn "REGLA #13 no encontrada en constitución"
        fi
    else
        err "Falta constitución en $OPENCODE_DIR/constitucion.md"
    fi

    # Agentes
    if [[ -d "$OPENCODE_DIR/agents" ]]; then
        local count; count="$(ls -1 "$OPENCODE_DIR/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$count" -eq 8 ]]; then
            ok "8 agentes instalados"
        else
            warn "Esperados 8 agentes, encontré $count"
        fi

        # Validar frontmatter de cada agente
        local required_modes=("primary:Alex" "subagent:Pol" "subagent:Jes" "subagent:Sol"
                              "subagent:Teo" "subagent:Jhon" "subagent:Luz" "subagent:Pau")
        for f in "$OPENCODE_DIR/agents"/*.md; do
            local name; name="$(basename "$f" .md)"
            if ! head -1 "$f" | grep -q "^---$"; then
                err "$name: frontmatter no abre con ---"
            elif ! head -20 "$f" | grep -q "^---$"; then
                err "$name: frontmatter no cierra con ---"
            else
                if grep -q "^mode: primary" "$f" && [[ "$name" != "Alex" ]]; then
                    err "$name: marcado mode: primary pero debería ser subagent"
                fi
                if grep -q "^mode: subagent" "$f" && [[ "$name" == "Alex" ]]; then
                    err "Alex: marcado mode: subagent pero debería ser primary"
                fi
            fi
        done
        ok "Frontmatter de agentes validado"
    else
        err "Falta directorio $OPENCODE_DIR/agents"
    fi

    # Skills core
    if [[ -d "$OPENCODE_DIR/skills" ]]; then
        local count; count="$(ls -1d "$OPENCODE_DIR/skills"/*/ 2>/dev/null | wc -l | tr -d ' ')"
        ok "$count skills core instaladas"
    else
        warn "Falta directorio skills (no es crítico)"
    fi

    # Comandos
    if [[ -d "$OPENCODE_DIR/command" ]]; then
        local count; count="$(ls -1 "$OPENCODE_DIR/command"/skalling-*.md 2>/dev/null | wc -l | tr -d ' ')"
        ok "$count comandos /skalling-* instalados"
    else
        warn "Falta directorio command"
    fi

    # Templates
    if [[ -d "$OPENCODE_DIR/templates" ]]; then
        ok "Templates presentes"
    else
        warn "Falta directorio templates (se crea en Fase 4)"
    fi

    # Data files
    if [[ -d "$OPENCODE_DIR/skalling-data" ]]; then
        ok "Data files presentes"
    else
        warn "Falta skalling-data/ (se crea en Fase 11)"
    fi

    # Script update.sh
    if [[ -x "$SCRIPT_DIR/scripts/update.sh" ]]; then
        ok "update.sh disponible"
    else
        warn "update.sh no encontrado o no ejecutable"
    fi
}

check_memory_health() {
    section "Memoria (bundle OKF)"

    local context_dir="$PROJECT_DIR/.opencode/context"
    [[ -d "$context_dir" ]] || return 0

    source "$SCRIPT_DIR/scripts/lib/lib-memory-check.sh"

    local findings
    findings="$(skalling_find_orphans "$context_dir")"
    if [[ -n "$findings" ]]; then
        while IFS= read -r file; do
            warn "Concept doc huérfano: $file (no referenciado desde ningún index.md)"
        done <<< "$findings"
    else
        ok "Sin concept docs huérfanos"
    fi

    local zombie_days="${SKALLING_WIP_ZOMBIE_DAYS:-30}"
    findings="$(skalling_find_zombie_wip "$context_dir" "$zombie_days")"
    if [[ -n "$findings" ]]; then
        while IFS= read -r file; do
            warn "Trabajo-en-curso zombie (>${zombie_days} días): $file — corré /skalling-forget"
        done <<< "$findings"
    else
        ok "Sin trabajo-en-curso zombie"
    fi

    findings="$(skalling_find_duplicates "$context_dir")"
    if [[ -n "$findings" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && err "Duplicado obvio por title: $file"
        done <<< "$findings"
    else
        ok "Sin duplicados obvios"
    fi

    local stale_months="${SKALLING_STALE_MONTHS:-6}"
    findings="$(skalling_find_stale "$context_dir" "$stale_months")"
    if [[ -n "$findings" ]]; then
        while IFS= read -r file; do
            warn "Concept doc stale (>${stale_months} meses sin referenciar): $file"
        done <<< "$findings"
    else
        ok "Sin concept docs stale"
    fi

    findings="$(skalling_find_superseded "$context_dir")"
    local superseded_in_index=""
    if [[ -n "$findings" ]]; then
        while IFS= read -r file; do
            local name
            name="$(basename "$file")"
            if find "$context_dir" -name "index.md" -exec grep -lF "$name" {} + 2>/dev/null | grep -q .; then
                superseded_in_index+="${file}"$'\n'
            fi
        done <<< "$findings"
    fi
    if [[ -n "$superseded_in_index" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && warn "Concept doc superseded pero vigente en index.md: $file"
        done <<< "$superseded_in_index"
    else
        ok "Sin concept docs superseded vigentes en index.md"
    fi

    if [[ -f "$context_dir/log.md" ]]; then
        ok "log.md presente"
    else
        info "Sin log.md (se crea en próximo forget o consolidación)"
    fi
}

check_project_install() {
    section "Instalación Per-Project ($PROJECT_DIR)"

    if [[ ! -d "$PROJECT_DIR/.opencode" ]]; then
        info "No hay .opencode/ en este proyecto."
        info "  → Corré /skalling-init para bootstrappear."
        return
    fi
    ok ".opencode/ existe"

    # Agentes per-project (opcional)
    if [[ -d "$PROJECT_DIR/.opencode/agents" ]]; then
        local count; count="$(ls -1 "$PROJECT_DIR/.opencode/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')"
        ok "$count agentes per-project (override de global)"
    else
        info "Sin agentes per-project — usa los globales"
    fi

    # Bundle OKF
    if [[ -d "$PROJECT_DIR/.opencode/context" ]]; then
        local docs; docs="$(find "$PROJECT_DIR/.opencode/context" -name "*.md" -not -name "index.md" -not -name "log.md" -not -name "README.md" 2>/dev/null | wc -l | tr -d ' ')"
        ok "Bundle OKF presente ($docs concept docs)"
        if [[ -f "$PROJECT_DIR/.opencode/context/index.md" ]]; then
            ok "index.md presente"
        else
            warn "Falta index.md — bundle sin navegación"
        fi
        if [[ -f "$PROJECT_DIR/.opencode/context/log.md" ]]; then
            ok "log.md presente"
        else
            info "Sin log.md (se crea en próximo bootstrap)"
        fi
    else
        info "Sin bundle OKF todavía. Corré /skalling-init."
    fi

    # project.yaml
    if [[ -f "$PROJECT_DIR/.opencode/project.yaml" ]]; then
        ok "project.yaml presente"
        # Validar YAML básico
        if command -v yq >/dev/null 2>&1; then
            if yq eval '.schema' "$PROJECT_DIR/.opencode/project.yaml" >/dev/null 2>&1; then
                ok "project.yaml parseable"
            else
                err "project.yaml malformado"
            fi
        fi
    else
        info "Sin project.yaml (se crea en /skalling-init)"
    fi

    # REGLA #13: design-system.md si frontend
    if [[ -f "$PROJECT_DIR/.opencode/project.yaml" ]] && grep -q "language:" "$PROJECT_DIR/.opencode/project.yaml" 2>/dev/null; then
        local is_frontend
        is_frontend="$(grep -E "(react|vue|svelte|nextjs|astro|nuxt|flutter|react-native|swift)" "$PROJECT_DIR/.opencode/project.yaml" 2>/dev/null || true)"
        if [[ -n "$is_frontend" ]]; then
            if [[ -f "$PROJECT_DIR/.opencode/context/proyecto/design-system.md" ]]; then
                ok "design-system.md presente (REGLA #13 OK)"
            else
                err "Frontend detectado pero falta design-system.md en bundle OKF (REGLA #13)"
            fi
        fi
    fi

    if [[ -d "$PROJECT_DIR/.opencode/context" ]]; then
        check_memory_health
    fi

    # Changes (SDD)
    if [[ -d "$PROJECT_DIR/.opencode/changes" ]]; then
        local changes; changes="$(find "$PROJECT_DIR/.opencode/changes" -name "proposal.md" 2>/dev/null | wc -l | tr -d ' ')"
        ok "$changes SDD changes (proposal.md)"
    fi

    if [[ -f "$SCRIPT_DIR/scripts/skalling-drift.sh" ]]; then
        info "Drift detection disponible: bash scripts/skalling-drift.sh <plan-archivado>"
    else
        info "Drift detection no instalado"
    fi

    if [[ -f "$SCRIPT_DIR/scripts/spec-memory-link.sh" ]]; then
        info "Spec ↔ Memory link disponible: bash scripts/spec-memory-link.sh <origen> <destino>"
    else
        info "Spec ↔ Memory link NO instalado (feature pendiente, ver .opencode/changes/spec-memory-link/)"
    fi
}

check_inteligencia_codigo() {
    section "Code Intelligence (opt-in)"
    if command -v codebase-memory-mcp >/dev/null 2>&1; then
        info "codebase-memory-mcp instalado ($(codebase-memory-mcp --version 2>/dev/null || echo 'versión desconocida'))"
        if grep -q "codebase-memory-mcp" ~/.config/opencode/opencode.jsonc 2>/dev/null; then
            info "MCP server configurado en opencode.jsonc"
        else
            info "MCP server NO configurado — corré /skalling-init paso 4.7 o instalá manualmente"
        fi
    else
        info "codebase-memory-mcp NO instalado (opt-in — instalá con /skalling-init paso 4.7 si querés)"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    printf "${c_blue}╭──────────────────────────────────────────────────────────╮${c_reset}\n"
    printf "${c_blue}│  Skalling Doctor v${SKALLING_VERSION}                              │${c_reset}\n"
    printf "${c_blue}╰──────────────────────────────────────────────────────────╯${c_reset}\n"

    check_ambiente
    check_global_install
    if [[ "$GLOBAL_ONLY" == false ]]; then
        check_project_install
    fi
    check_inteligencia_codigo

    echo ""
    printf "${c_blue}━━━ Resumen ━━━${c_reset}\n"
    printf "  ${c_green}OK:${c_reset}       %d\n" "$OK_COUNT"
    printf "  ${c_yellow}Warnings:${c_reset} %d\n" "$WARN_COUNT"
    if [[ "$WARN_ENV_COUNT" -gt 0 ]]; then
        printf "  ${c_yellow}Env:${c_reset}      %d (no promovido por --strict)\n" "$WARN_ENV_COUNT"
    fi
    if [[ "$ERROR_COUNT" -gt 0 ]]; then
        printf "  ${c_red}Errors:${c_reset}   %d\n" "$ERROR_COUNT"
    fi

    if [[ "$ERROR_COUNT" -gt 0 ]]; then
        echo ""
        err "Hay errores que requieren atención."
        exit 1
    fi

    if [[ "$WARN_COUNT" -gt 0 && "$STRICT" == true ]]; then
        echo ""
        warn "Modo strict activo: warnings de proyecto promovidos a error."
        exit 1
    fi

    echo ""
    ok "Doctor completo. Skalling está ${c_green}saludable${c_reset}."
    exit 0
}

main
