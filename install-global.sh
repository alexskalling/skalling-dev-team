#!/usr/bin/env bash
# install-global.sh — Instala Skalling en ~/.config/opencode/ (una sola vez por máquina)
#
# Uso:
#   bash install-global.sh                    # install normal
#   bash install-global.sh --dry-run          # ver qué haría sin tocar nada
#   bash install-global.sh --force            # sobrescribir sin backup
#   bash install-global.sh --uninstall        # borrar Skalling de ~/.config/opencode/

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# LIBRERÍA COMPARTIDA
# ──────────────────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/lib-os.sh
source "$(dirname "$0")/scripts/lib/lib-os.sh"

# shellcheck source=scripts/lib/lib-stack-detect.sh
source "$(dirname "$0")/scripts/lib/lib-stack-detect.sh"

skalling_log_os

# ──────────────────────────────────────────────────────────────────────────────
# CONSTANTES Y RUTAS
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_VERSION="0.1.0"
INSTALL_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"

OPENCODE_DIR="$SKALLING_OPENCODE_DIR"
AGENTS_DIR="${OPENCODE_DIR}/agents"
SKILLS_DIR="${OPENCODE_DIR}/skills"
COMMAND_DIR="${OPENCODE_DIR}/command"
CONSTITUTION_FILE="${OPENCODE_DIR}/constitucion.md"
TEMPLATES_DIR="${OPENCODE_DIR}/templates"
DATA_DIR="${OPENCODE_DIR}/skalling-data"
BACKUP_DIR="${HOME}/.config/opencode/.skalling-backups"
INSTALL_LOG="${BACKUP_DIR}/install.log"

DRY_RUN=false
FORCE=false
UNINSTALL=false

# ──────────────────────────────────────────────────────────────────────────────
# PARSEO DE ARGUMENTOS
# ──────────────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --uninstall) UNINSTALL=true; shift ;;
        --help|-h)
            cat <<EOF
install-global.sh v${SKALLING_VERSION}

Instala Skalling en ~/.config/opencode/ (una vez por máquina).

Opciones:
  --dry-run       Muestra qué se haría sin modificar archivos
  --force         Sobrescribe sin pedir backup
  --uninstall     Borra Skalling de ~/.config/opencode/
  --help, -h      Esta ayuda

Después de instalar, Skalling funciona automáticamente en todos tus proyectos
cuando abras opencode. Para configurar un proyecto específico, usá /skalling-init.
EOF
            exit 0 ;;
        *) echo "Argumento desconocido: $1. Usá --help."; exit 1 ;;
    esac
done

# ──────────────────────────────────────────────────────────────────────────────
# FUNCIONES AUXILIARES
# ──────────────────────────────────────────────────────────────────────────────

log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts="$(date +%H:%M:%S)"
    case "$level" in
        INFO)  printf '  \033[36mℹ\033[0m  %s | %s\n' "$ts" "$msg" ;;
        OK)    printf '  \033[32m✓\033[0m  %s | %s\n' "$ts" "$msg" ;;
        WARN)  printf '  \033[33m⚠\033[0m  %s | %s\n' "$ts" "$msg" ;;
        ERROR) printf '  \033[31m✗\033[0m  %s | %s\n' "$ts" "$msg" >&2 ;;
    esac
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$BACKUP_DIR"
        printf '[%s] %s | %s\n' "$INSTALL_DATE" "$level" "$msg" >> "$INSTALL_LOG" 2>/dev/null || true
    fi
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

check_bash_version() {
    local major="${BASH_VERSINFO[0]}"
    if [[ "$major" -lt 4 ]]; then
        log WARN "bash $BASH_VERSION — bash 3.2 (default macOS) funciona pero bash >= 4 es recomendado"
    else
        log OK "bash $BASH_VERSION"
    fi
}

check_opencode() {
    if ! command -v opencode >/dev/null 2>&1; then
        log WARN "opencode no está en PATH. Skalling funcionará igual cuando lo instales."
        return 1
    fi
    local version; version="$(opencode --version 2>/dev/null || echo 'unknown')"
    log OK "opencode $version"
    return 0
}

create_backup() {
    if [[ ! -d "$OPENCODE_DIR" ]]; then
        log INFO "No hay instalación previa en $OPENCODE_DIR, skip backup"
        return 0
    fi

    if [[ "$FORCE" == true ]]; then
        log WARN "Backup omitido por --force"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local backup="${BACKUP_DIR}/opencode-${stamp}.tar.gz"
    local sha_file="${backup}.sha256"

    if [[ -f "${BACKUP_DIR}/last-sha256" ]]; then
        local current_sha; current_sha="$(find "$OPENCODE_DIR" -type f -not -path "*/.skalling-backups/*" -exec sha256sum {} \; 2>/dev/null | sha256sum | cut -d' ' -f1)"
        local last_sha; last_sha="$(cat "${BACKUP_DIR}/last-sha256")"
        if [[ "$current_sha" == "$last_sha" ]]; then
            log INFO "Backup omitido: estado idéntico al último backup (sha256 match)"
            return 0
        fi
    fi

    log INFO "Creando backup en $backup"
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] tar czf $backup $OPENCODE_DIR (excluyendo .skalling-backups)"
    else
        tar --exclude='.skalling-backups' -czf "$backup" -C "$(dirname "$OPENCODE_DIR")" "$(basename "$OPENCODE_DIR")" 2>/dev/null || {
            log WARN "Backup parcial (puede haber archivos en uso). Continuando."
        }
        find "$OPENCODE_DIR" -type f -not -path "*/.skalling-backups/*" -exec sha256sum {} \; 2>/dev/null | sha256sum > "${BACKUP_DIR}/last-sha256"
        sha256sum "$backup" | cut -d' ' -f1 > "$sha_file"
    fi

    prune_old_backups
}

prune_old_backups() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    local keep=5
    local count; count="$(ls -1 "${BACKUP_DIR}"/opencode-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$count" -gt "$keep" ]]; then
        local to_delete=$((count - keep))
        log INFO "Prune: borrando $to_delete backups viejos (mantener últimos $keep)"
        ls -1t "${BACKUP_DIR}"/opencode-*.tar.gz | tail -n "$to_delete" | while read -r f; do
            rm -f "$f" "${f}.sha256"
        done
    fi
}

install_agents() {
    log INFO "Instalando 8 agentes en $AGENTS_DIR"
    run mkdir -p "$AGENTS_DIR"

    local agent_count=0
    for agent_file in "$SCRIPT_DIR"/agents-base/*.md; do
        [[ -e "$agent_file" ]] || continue
        local name; name="$(basename "$agent_file")"
        run cp "$agent_file" "$AGENTS_DIR/$name"
        agent_count=$((agent_count + 1))
    done
    log OK "$agent_count agentes instalados"
}

install_skills_core() {
    log INFO "Instalando skills core en $SKILLS_DIR"
    run mkdir -p "$SKILLS_DIR"

    # Las skills core son las listadas en data/skills-by-stack.yaml bajo "core:".
    # Stack-specific NO se instalan acá — se instalan on-demand.
    local skills_by_stack="$SCRIPT_DIR/data/skills-by-stack.yaml"
    local core_skills
    core_skills="$(skalling_core_skills "$skills_by_stack" 2>/dev/null || true)"

    local skill_count=0
    local name
    for name in $core_skills; do
        local skill_dir="$SCRIPT_DIR/skills-base/$name"
        if [[ -d "$skill_dir" ]]; then
            run cp -r "$skill_dir" "$SKILLS_DIR/$name"
            skill_count=$((skill_count + 1))
        else
            log WARN "Core skill declarada en YAML pero no existe: $name"
        fi
    done
    log OK "$skill_count skills core instaladas (data-driven desde skills-by-stack.yaml)"
}

install_commands() {
    log INFO "Instalando comandos /skalling-* en $COMMAND_DIR"
    run mkdir -p "$COMMAND_DIR"

    local cmd_count=0
    for cmd_file in "$SCRIPT_DIR"/command/*.md; do
        [[ -e "$cmd_file" ]] || continue
        local name; name="$(basename "$cmd_file")"
        if [[ "$name" == "README.md" ]]; then continue; fi
        run cp "$cmd_file" "$COMMAND_DIR/$name"
        cmd_count=$((cmd_count + 1))
    done
    log OK "$cmd_count comandos instalados"
}

install_constitution() {
    log INFO "Instalando constitución en $CONSTITUTION_FILE"
    if [[ -f "$CONSTITUTION_FILE" && "$FORCE" == false ]]; then
        log WARN "Constitución existente preservada (usá --force para sobrescribir)"
        return 0
    fi
    run cp "$SCRIPT_DIR/constitution/constitucion.md" "$CONSTITUTION_FILE"
    log OK "Constitución instalada"
}

install_templates() {
    log INFO "Instalando templates en $TEMPLATES_DIR"
    if [[ -d "$SCRIPT_DIR/templates" ]]; then
        run mkdir -p "$TEMPLATES_DIR"
        run cp -r "$SCRIPT_DIR/templates"/. "$TEMPLATES_DIR/"
        log OK "Templates instalados"
    else
        log WARN "Directorio templates/ no encontrado"
    fi
}

install_merge_helper() {
    log INFO "Instalando merge-helper script en $OPENCODE_DIR"
    if [[ -f "$SCRIPT_DIR/scripts/merge-helper.sh" ]]; then
        run mkdir -p "$OPENCODE_DIR/scripts"
        run cp "$SCRIPT_DIR/scripts/merge-helper.sh" "$OPENCODE_DIR/scripts/merge-helper.sh"
        run chmod +x "$OPENCODE_DIR/scripts/merge-helper.sh"
        log OK "merge-helper instalado"
    fi
}

install_data_files() {
    log INFO "Instalando data files (stack-detectors, skills-by-stack) en $DATA_DIR"
    run mkdir -p "$DATA_DIR"
    # Por ahora se crean vacíos; Fase 11 los llena
    for f in stack-detectors.yaml skills-by-stack.yaml; do
        if [[ ! -f "$DATA_DIR/$f" ]]; then
            if [[ -f "$SCRIPT_DIR/data/$f" ]]; then
                run cp "$SCRIPT_DIR/data/$f" "$DATA_DIR/$f"
            fi
        fi
    done
    log OK "Data files listos"
}

install_gitattributes_template() {
    # El .gitattributes es per-project, pero el template vive global
    # para que bootstrap-context.sh pueda copiarlo cuando se inicialice un proyecto.
    log INFO "Instalando template gitattributes en $TEMPLATES_DIR"
    if [[ -f "$SCRIPT_DIR/templates/gitattributes.template" ]]; then
        run cp "$SCRIPT_DIR/templates/gitattributes.template" "$TEMPLATES_DIR/gitattributes.template"
        log OK "gitattributes template disponible"
    else
        log WARN "Template gitattributes.template no encontrado, skip"
    fi
}

print_summary() {
    cat <<EOF

  ╭──────────────────────────────────────────────────────────────╮
  │  Skalling v${SKALLING_VERSION} instalado correctamente     │
  ╰──────────────────────────────────────────────────────────────╯

  📂 Instalado en: $OPENCODE_DIR
     ├── agents/          (8 agentes)
     ├── skills/          (skills core)
     ├── command/         (comandos /skalling-*)
     ├── templates/       (templates OKF y SDD)
     ├── constitucion.md  (reglas universales)
     └── skalling-data/   (stack-detectors, skills-by-stack)

  🚀 Próximos pasos:

  1. Abrí cualquier proyecto en opencode.
  2. Alex detectará automáticamente si necesita bootstrap.
  3. Para inicializar manualmente:    /skalling-init
  4. Para ver el estado del bundle:  /skalling-status
  5. Para validar la instalación:     /skalling-doctor

  📦 Backups automáticos: $BACKUP_DIR
  📋 Log de instalación:  $INSTALL_LOG

EOF
}

do_install() {
    log INFO "Iniciando instalación de Skalling v${SKALLING_VERSION}"
    check_bash_version
    check_opencode || true

    create_backup
    install_agents
    install_skills_core
    install_commands
    install_constitution
    install_templates
    install_merge_helper
    install_gitattributes_template
    install_data_files

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Dry-run completo. Nada fue modificado."
    else
        print_summary
    fi
}

do_uninstall() {
    log INFO "Desinstalando Skalling de $OPENCODE_DIR"
    if [[ ! -d "$OPENCODE_DIR" ]]; then
        log WARN "No hay instalación en $OPENCODE_DIR"
        exit 0
    fi

    # Backup antes de borrar
    create_backup

    # Borrar solo lo que es nuestro (preservar otros agents/skills del usuario)
    local removed=0
    for f in "$AGENTS_DIR"/*.md; do
        [[ -e "$f" ]] || continue
        local basename; basename="$(basename "$f")"
        # Solo borrar si es nuestro (matchea con agents-base)
        if [[ -f "$SCRIPT_DIR/agents-base/$basename" ]]; then
            run rm -f "$f"
            removed=$((removed + 1))
        fi
    done
    log OK "$removed agentes removidos"

    for d in "$SKILLS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local basename; basename="$(basename "$d")"
        if [[ -d "$SCRIPT_DIR/skills-base/$basename" ]]; then
            run rm -rf "$d"
            removed=$((removed + 1))
        fi
    done

    for f in "$COMMAND_DIR"/skalling-*.md; do
        [[ -e "$f" ]] || continue
        run rm -f "$f"
        removed=$((removed + 1))
    done

    if [[ -f "$CONSTITUTION_FILE" ]]; then
        run rm -f "$CONSTITUTION_FILE"
    fi

    if [[ -d "$TEMPLATES_DIR" ]]; then
        run rm -rf "$TEMPLATES_DIR"
    fi

    if [[ -d "$DATA_DIR" ]]; then
        run rm -rf "$DATA_DIR"
    fi

    log OK "Desinstalación completa. $removed elementos removidos."
    log INFO "Backups preservados en $BACKUP_DIR"
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

if [[ "$UNINSTALL" == true ]]; then
    do_uninstall
else
    do_install
fi
