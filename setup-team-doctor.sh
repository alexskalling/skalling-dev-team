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
SKALLING_VERSION="0.1.0"

OPENCODE_DIR="$SKALLING_OPENCODE_DIR"
PROJECT_DIR="$(pwd)"
GLOBAL_ONLY=false
STRICT=false
WARN_COUNT=0
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

ok()   { OK_COUNT=$((OK_COUNT+1));   printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
warn() { WARN_COUNT=$((WARN_COUNT+1)); printf "  ${c_yellow}⚠${c_reset} %s\n" "$*" >&2; }
err()  { ERROR_COUNT=$((ERROR_COUNT+1)); printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
info() { printf "  ${c_blue}ℹ${c_reset} %s\n" "$*"; }

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
        warn "bash $BASH_VERSION — los scripts funcionan pero bash >= 4 es recomendado (algunas features avanzadas no disponibles)"
    fi

    if command -v opencode >/dev/null 2>&1; then
        local v; v="$(opencode --version 2>/dev/null || echo 'unknown')"
        ok "opencode $v"
    else
        warn "opencode no está en PATH (Skalling funcionará cuando lo instales)"
    fi

    if command -v node >/dev/null 2>&1; then
        local nv; nv="$(node --version 2>/dev/null || echo 'unknown')"
        if [[ "$nv" =~ v(2[2-9]|[3-9][0-9])\. ]]; then
            ok "node $nv (>= 22)"
        else
            warn "node $nv — Impeccable requiere >= 22"
        fi
    else
        warn "node no está en PATH (necesario para Impeccable)"
    fi

    if command -v git >/dev/null 2>&1; then
        ok "git $(git --version | awk '{print $3}')"
    else
        warn "git no está en PATH"
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
            ok "REGLA #13 (DESIGN.md) presente"
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

    # REGLA #13: DESIGN.md si frontend
    if [[ -f "$PROJECT_DIR/.opencode/project.yaml" ]] && grep -q "language:" "$PROJECT_DIR/.opencode/project.yaml" 2>/dev/null; then
        local is_frontend
        is_frontend="$(grep -E "(react|vue|svelte|nextjs|astro|nuxt|flutter|react-native|swift)" "$PROJECT_DIR/.opencode/project.yaml" 2>/dev/null || true)"
        if [[ -n "$is_frontend" ]]; then
            if [[ -f "$PROJECT_DIR/docs/design/DESIGN.md" ]]; then
                ok "DESIGN.md presente (REGLA #13 OK)"
            else
                err "Frontend detectado pero falta docs/design/DESIGN.md (REGLA #13)"
            fi
        fi
    fi

    # Changes (SDD)
    if [[ -d "$PROJECT_DIR/.opencode/changes" ]]; then
        local changes; changes="$(find "$PROJECT_DIR/.opencode/changes" -name "proposal.md" 2>/dev/null | wc -l | tr -d ' ')"
        ok "$changes SDD changes (proposal.md)"
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

    echo ""
    printf "${c_blue}━━━ Resumen ━━━${c_reset}\n"
    printf "  ${c_green}OK:${c_reset}       %d\n" "$OK_COUNT"
    printf "  ${c_yellow}Warnings:${c_reset} %d\n" "$WARN_COUNT"
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
        warn "Modo strict activo: warnings tratados como error."
        exit 1
    fi

    echo ""
    ok "Doctor completo. Skalling está ${c_green}saludable${c_reset}."
    exit 0
}

main
