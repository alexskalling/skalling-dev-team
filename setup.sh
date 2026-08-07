#!/usr/bin/env bash
# setup.sh — Instala Skalling en un proyecto específico (modo per-project / team-sharing).
#
# Diferencia con install-global.sh:
#   - install-global.sh: copia a ~/.config/opencode/ (todos tus proyectos).
#   - setup.sh:          copia a <proyecto>/.opencode/ (commiteable en git, team sharing).
#
# Uso:
#   bash setup.sh                          # instala en directorio padre (default legacy)
#   bash setup.sh --target /path/to/proj   # instala en proyecto específico
#   bash setup.sh --dry-run                # ver qué haría sin tocar
#   bash setup.sh --skip-backup            # no crear backup antes
#   bash setup.sh --force                  # sobrescribir todo sin preguntar

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# LIBRERÍA COMPARTIDA
# ──────────────────────────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/lib-os.sh
source "$(dirname "$0")/scripts/lib/lib-os.sh"

skalling_log_os

# ──────────────────────────────────────────────────────────────────────────────
# CONSTANTES Y RUTAS
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_VERSION="0.8.3"

DRY_RUN=false
FORCE=false
SKIP_BACKUP=false
UNINSTALL=false
TARGET_DIR=""

# ──────────────────────────────────────────────────────────────────────────────
# PARSEO DE ARGUMENTOS
# ──────────────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --skip-backup) SKIP_BACKUP=true; shift ;;
        --uninstall) UNINSTALL=true; shift ;;
        --help|-h)
            sed -n '2,15p' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "Argumento desconocido: $1. Usá --help."; exit 1 ;;
    esac
done

# Default target = directorio actual (cwd)
# El comportamiento legacy (target = directorio padre del installer) está deprecado.
if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$(pwd)"
    warn "No se especificó --target. Usando directorio actual: $TARGET_DIR"
    warn "Esto instalará Skalling en $TARGET_DIR/.opencode/"
    if [[ "$TARGET_DIR" == "$SCRIPT_DIR" || "$TARGET_DIR" == "$SCRIPT_DIR/"* ]]; then
        err "Estás ejecutando setup.sh desde dentro del installer ($SCRIPT_DIR)."
        err "Esto modificaría el installer mismo. Usá --target /path/to/your/project."
        exit 1
    fi
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "✗ El directorio target no existe: $TARGET_DIR"
    exit 1
fi

# Rutas derivadas del target
OPENCODE_DIR="$TARGET_DIR/.opencode"
AGENTS_DEST_DIR="$OPENCODE_DIR/agents"
SKILLS_DEST_DIR="$OPENCODE_DIR/skills"
CHANGES_DEST_DIR="$OPENCODE_DIR/changes"
CONTEXT_DIR="$OPENCODE_DIR/context"
STATE_DIR="$OPENCODE_DIR/state"
DOCS_DIR="$TARGET_DIR/docs"
TARGET_AGENTS_FILE="$TARGET_DIR/AGENTS.md"
BACKUP_DIR="$TARGET_DIR/.skalling-backups"
INSTALL_LOG="$BACKUP_DIR/setup.log"

AGENTS_BASE_DIR="$SCRIPT_DIR/agents-base"
SKILLS_BASE_DIR="$SCRIPT_DIR/skills-base"
CONSTITUTION_SRC="$SCRIPT_DIR/constitution/constitucion.md"
GITATTRIBUTES_TEMPLATE="$SCRIPT_DIR/templates/gitattributes.template"

# ──────────────────────────────────────────────────────────────────────────────
# FUNCIONES AUXILIARES
# ──────────────────────────────────────────────────────────────────────────────

log() {
    local level="$1"; shift
    local ts; ts="$(date +%H:%M:%S)"
    case "$level" in
        INFO)  printf '  \033[36mℹ\033[0m  %s | %s\n' "$ts" "$*" ;;
        OK)    printf '  \033[32m✓\033[0m  %s | %s\n' "$ts" "$*" ;;
        WARN)  printf '  \033[33m⚠\033[0m  %s | %s\n' "$ts" "$*" >&2 ;;
        ERROR) printf '  \033[31m✗\033[0m  %s | %s\n' "$ts" "$*" >&2 ;;
    esac
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    if [[ "$FORCE" == true ]]; then
        return 0  # siempre sí
    fi
    local reply
    read -rp "$prompt [$default]: " reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[sSyY]$ ]]
}

create_backup() {
    if [[ "$SKIP_BACKUP" == true ]]; then
        log WARN "Backup omitido por --skip-backup"
        return 0
    fi

    if [[ ! -d "$OPENCODE_DIR" && ! -f "$TARGET_AGENTS_FILE" ]]; then
        log INFO "No hay instalación previa en $TARGET_DIR, skip backup"
        return 0
    fi

    run mkdir -p "$BACKUP_DIR"
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local backup_file="${BACKUP_DIR}/skalling-${stamp}.tar.gz"

    log INFO "Creando backup en $backup_file"

    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] tar czf $backup_file $OPENCODE_DIR $TARGET_AGENTS_FILE"
    else
        local files_to_backup=()
        [[ -d "$OPENCODE_DIR" ]] && files_to_backup+=("$OPENCODE_DIR")
        [[ -f "$TARGET_AGENTS_FILE" ]] && files_to_backup+=("$TARGET_AGENTS_FILE")
        tar czf "$backup_file" "${files_to_backup[@]}" 2>/dev/null || {
            log WARN "Backup parcial (algunos archivos en uso)"
        }
    fi

    # Prune: mantener últimos 5
    if [[ "$DRY_RUN" == false ]]; then
        local keep=5
        local count; count="$(ls -1 "$BACKUP_DIR"/skalling-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$count" -gt "$keep" ]]; then
            local to_delete=$((count - keep))
            log INFO "Prune: borrando $to_delete backups viejos"
            ls -1t "$BACKUP_DIR"/skalling-*.tar.gz | tail -n "$to_delete" | xargs rm -f
        fi
    fi
}

copy_with_diff_check() {
    # $1 = source, $2 = destino, $3 = descripción
    local src="$1" dst="$2" desc="$3"

    if [[ ! -e "$src" ]]; then
        log WARN "Source no existe, skip: $src"
        return 1
    fi

    if [[ -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
        log WARN "Diff detectado en $desc"
        if [[ "$DRY_RUN" == true ]]; then
            echo "    [dry-run] diff (skip prompt)"
            return 0
        fi
        if ask_yes_no "    ¿Sobrescribir $desc?" "n"; then
            cp "$src" "$dst"
            log OK "Sobrescrito: $desc"
        else
            log INFO "Preservado (customización del usuario): $desc"
        fi
    elif [[ -f "$dst" ]]; then
        log INFO "Idéntico, skip: $desc"
    else
        run cp "$src" "$dst"
        log OK "Creado: $desc"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# PASOS DEL SETUP
# ──────────────────────────────────────────────────────────────────────────────

step_create_directories() {
    log INFO "Creando estructura de directorios en $OPENCODE_DIR"

    # Detectar symlinks rotos en .opencode/ (heredados de instalaciones anteriores o apps externas)
    for path in "$AGENTS_DEST_DIR" "$SKILLS_DEST_DIR" "$CHANGES_DEST_DIR" "$CONTEXT_DIR" "$STATE_DIR"; do
        if [[ -L "$path" && ! -e "$path" ]]; then
            local target; target="$(readlink "$path" 2>/dev/null || echo '?')"
            log WARN "Symlink roto en $path -> $target. Eliminando."
            rm -f "$path"
        fi
    done

    run mkdir -p "$AGENTS_DEST_DIR"
    run mkdir -p "$SKILLS_DEST_DIR"
    run mkdir -p "$CHANGES_DEST_DIR"
    run mkdir -p "$CONTEXT_DIR"
    run mkdir -p "$STATE_DIR"

    if [[ ! -d "$DOCS_DIR" ]]; then
        run mkdir -p "$DOCS_DIR"
        log OK "docs/ creado (documentación pública)"
    else
        log INFO "docs/ ya existe"
    fi

    if [[ ! -f "$STATE_DIR/workflow.json" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "    [dry-run] crear workflow.json inicial"
        else
            printf '{"fase_actual":"INICIO","agente_activo":null,"tarea_actual":null,"iteracion":0,"historial":[]}\n' \
                > "$STATE_DIR/workflow.json"
            log OK "workflow.json inicializado"
        fi
    fi
}

step_install_agents() {
    log INFO "Sincronizando agentes per-project (para team-sharing)"
    local count=0
    for src in "$AGENTS_BASE_DIR"/*.md; do
        [[ -e "$src" ]] || continue
        local name; name="$(basename "$src")"
        copy_with_diff_check "$src" "$AGENTS_DEST_DIR/$name" "agents/$name" >/dev/null && count=$((count+1)) || true
    done
    log OK "Agentes sincronizados"
}

step_install_skills() {
    log INFO "Sincronizando skills core (stack-specific se instalan on-demand)"
    local count=0
    for skill_dir in "$SKILLS_BASE_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local name; name="$(basename "$skill_dir")"
        case "$name" in
            next-cache-components|shadcn-ui|tailwind-design-system|\
            vercel-composition-patterns|ui-ux-pro-max|firecrawl|\
            vitest|webapp-testing)
                continue
                ;;
        esac
        if [[ -d "$SKILLS_DEST_DIR/$name" ]]; then
            # Existe — sync solo si hay diff
            local diff_files
            diff_files="$(diff -rq "$skill_dir" "$SKILLS_DEST_DIR/$name" 2>/dev/null || true)"
            if [[ -n "$diff_files" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    echo "    [dry-run] sync $name (tiene diffs)"
                elif ask_yes_no "    ¿Actualizar skill $name?" "n"; then
                    cp -r "$skill_dir"/. "$SKILLS_DEST_DIR/$name/"
                    log OK "Skill actualizada: $name"
                fi
            else
                log INFO "Skill idéntica, skip: $name"
            fi
        else
            run cp -r "$skill_dir" "$SKILLS_DEST_DIR/$name"
            log OK "Skill instalada: $name"
        fi
        count=$((count+1))
    done
    log OK "Skills core sincronizadas"
}

step_install_gitattributes() {
    log INFO "Instalando .opencode/.gitattributes (estrategias de merge R16)"
    if [[ ! -f "$GITATTRIBUTES_TEMPLATE" ]]; then
        warn "Template gitattributes.template no encontrado, skip"
        return 0
    fi

    local dest="$OPENCODE_DIR/.gitattributes"
    local diff=false
    if [[ -f "$dest" ]] && ! cmp -s "$GITATTRIBUTES_TEMPLATE" "$dest"; then
        diff=true
    fi

    if [[ "$diff" == true ]]; then
        if ask_yes_no "    .opencode/.gitattributes difiere, ¿sobrescribir?" "n"; then
            cp "$GITATTRIBUTES_TEMPLATE" "$dest"
            log OK ".gitattributes actualizado"
        else
            log INFO ".gitattributes preservado (customización del usuario)"
        fi
    elif [[ -f "$dest" ]]; then
        log INFO ".gitattributes idéntico, skip"
    else
        run cp "$GITATTRIBUTES_TEMPLATE" "$dest"
        log OK ".gitattributes instalado"
    fi
}

step_install_agents_md() {
    # En modo per-project, AGENTS.md es opcional — opencode carga agents/ directamente.
    # Lo creamos solo si el usuario lo quiere para team clarity (commit visible).
    log INFO "Evaluando AGENTS.md raíz"
    if [[ -f "$TARGET_AGENTS_FILE" ]]; then
        log INFO "AGENTS.md ya existe en raíz, preservando"
        return 0
    fi

    if ask_yes_no "    ¿Crear AGENTS.md en raíz del proyecto (índice de skills para team)?" "n"; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "    [dry-run] crear AGENTS.md"
        else
            cat > "$TARGET_AGENTS_FILE" <<'AGENTS_MD_EOF'
# AGENTS.md — Índice de Skalling para este proyecto

Este proyecto usa [Skalling](https://github.com/tu-usuario/skalling-dev-team). El equipo agentico completo (Alex + 7 especialistas) vive en `.opencode/agents/`.

## Reglas Universales

Ver `.opencode/context/constitucion.md` (o `~/.config/opencode/constitucion.md`).

## Skills Disponibles

| Skill | Trigger |
|---|---|
| `skalling-tdd` | Implementar lógica con TDD (red-green-refactor) |
| `skalling-debug` | Debugging sistemático |
| `skalling-verify` | Antes de declarar completo, verificar |
| `skalling-planning` | Escribir planes de implementación |
| `skalling-code-review` | Code review excellence |
| `skalling-doc-coauthoring` | Co-escribir documentación |
| `skalling-brainstorming` | Lluvia de ideas estructurada |
| `skalling-find-skills` | Buscar skills adicionales |

## Comandos

- `/skalling-init` — bootstrap del proyecto
- `/skalling-status` — ver estado de memoria
- `/skalling-refresh` — re-detectar stack
- `/skalling-doctor` — health check
- `/skalling-forget` — purgar memoria obsoleta

## Memoria

Bundle OKF en `.opencode/context/`. Cada concept doc tiene frontmatter YAML.
AGENTS_MD_EOF
            log OK "AGENTS.md creado en raíz"
        fi
    else
        log INFO "AGENTS.md no creado (opcional)"
    fi
}

step_summary() {
    cat <<EOF

  ╭──────────────────────────────────────────────────────────────╮
  │  Skalling v${SKALLING_VERSION} configurado en el proyecto   │
  ╰──────────────────────────────────────────────────────────────╯

  📂 Target: $TARGET_DIR
     ├── .opencode/
     │   ├── agents/      (8 agentes per-project, commiteable)
     │   ├── skills/      (skills core, stack-specific on-demand)
     │   ├── changes/     (SDD artifacts, vacíos hasta el primer feature)
     │   ├── context/     (bundle OKF, se llena con /skalling-init)
     │   └── state/       (workflow.json del ciclo)
     └── docs/            (documentación pública)

  📦 Backups: $BACKUP_DIR (mantiene últimos 5)
  📋 Log:     $INSTALL_LOG

  🚀 Próximo paso: abrí opencode en este proyecto y corré /skalling-init.

EOF
}

do_uninstall() {
    log INFO "Desinstalando Skalling del proyecto en $TARGET_DIR"

    if [[ ! -d "$OPENCODE_DIR" ]]; then
        warn "No hay .opencode/ en $TARGET_DIR"
        exit 0
    fi

    if [[ "$FORCE" == false ]]; then
        if ! ask_yes_no "    ¿Confirmar desinstalación? (los archivos de .opencode/ se moverán a .skalling-backups/)" "n"; then
            log INFO "Cancelado por el usuario"
            exit 0
        fi
    fi

    create_backup

    local removed=0
    # Remover agents per-project
    if [[ -d "$AGENTS_DEST_DIR" ]]; then
        local f
        for f in "$AGENTS_DEST_DIR"/*.md; do
            [[ -e "$f" ]] || continue
            local basename; basename="$(basename "$f")"
            # Solo remover si matchea con nuestro agents-base
            if [[ -f "$AGENTS_BASE_DIR/$basename" ]]; then
                run rm -f "$f"
                removed=$((removed + 1))
            fi
        done
    fi

    # Remover .gitattributes
    [[ -f "$OPENCODE_DIR/.gitattributes" ]] && run rm -f "$OPENCODE_DIR/.gitattributes"

    # Preguntar antes de borrar bundle OKF (memoria es valiosa)
    if [[ -d "$CONTEXT_DIR" ]]; then
        if [[ "$FORCE" == true ]] || ask_yes_no "    ¿Borrar bundle OKF (.opencode/context/)? Tiene memoria del proyecto." "n"; then
            rm -rf "$CONTEXT_DIR"
            log INFO "Bundle OKF borrado"
        else
            log INFO "Bundle OKF preservado"
        fi
    fi

    # Preguntar antes de borrar state
    if [[ -d "$STATE_DIR" ]]; then
        if [[ "$FORCE" == true ]] || ask_yes_no "    ¿Borrar .opencode/state/ (workflow.json)?" "n"; then
            rm -rf "$STATE_DIR"
            log INFO "State borrado"
        fi
    fi

    # Cambios SDD: NO borrar (histórico)
    if [[ -d "$CHANGES_DEST_DIR" ]]; then
        log INFO "Cambios SDD preservados en $CHANGES_DEST_DIR (histórico del proyecto)"
    fi

    log OK "Desinstalación per-project completa. $removed archivos removidos."
    log INFO "Backups en $BACKUP_DIR (mantiene últimos 5)"
    log INFO "Para reinstalar: bash ~/skalling-dev-team/setup.sh"
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    if [[ "$UNINSTALL" == true ]]; then
        do_uninstall
        exit 0
    fi

    log INFO "Iniciando setup per-project de Skalling v${SKALLING_VERSION}"
    log INFO "Target: $TARGET_DIR"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log WARN "Modo dry-run activo — no se modifica nada"
    fi

    create_backup
    step_create_directories
    step_install_agents
    step_install_skills
    step_install_gitattributes
    step_install_agents_md

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Dry-run completo. Sin cambios."
    else
        step_summary
    fi
}

main
