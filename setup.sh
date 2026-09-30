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
#   bash setup.sh --with-ci                # además: workflow de CI y CODEOWNERS (.github/)

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
SKALLING_VERSION="$(grep '__version__' "$SCRIPT_DIR/VERSION" | sed 's/.*"\(.*\)".*/\1/')"

DRY_RUN=false
FORCE=false
SKIP_BACKUP=false
UNINSTALL=false
WITH_CI=false
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
        --with-ci) WITH_CI=true; shift ;;
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
DOCS_DIR="$TARGET_DIR/docs"
TARGET_AGENTS_FILE="$TARGET_DIR/AGENTS.md"
BACKUP_DIR="$TARGET_DIR/.skalling-backups"
INSTALL_LOG="$BACKUP_DIR/setup.log"

AGENTS_BASE_DIR="$SCRIPT_DIR/agents-base"
SKILLS_BASE_DIR="$SCRIPT_DIR/skills-base"
GITATTRIBUTES_TEMPLATE="$SCRIPT_DIR/templates/gitattributes.template"
SCRIPTS_SRC_DIR="$SCRIPT_DIR/scripts"
HOOKS_SRC_DIR="$SCRIPT_DIR/scripts/hooks"
SCRIPTS_DEST_DIR="$OPENCODE_DIR/scripts"
HOOKS_DEST_DIR="$OPENCODE_DIR/hooks"

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
    for path in "$AGENTS_DEST_DIR" "$SKILLS_DEST_DIR" "$CHANGES_DEST_DIR" "$CONTEXT_DIR"; do
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
    run mkdir -p "$SCRIPTS_DEST_DIR"
    run mkdir -p "$HOOKS_DEST_DIR"

    if [[ ! -d "$DOCS_DIR" ]]; then
        run mkdir -p "$DOCS_DIR"
        log OK "docs/ creado (documentación pública)"
    else
        log INFO "docs/ ya existe"
    fi

}

step_install_agents() {
    log INFO "Sincronizando agentes per-project (para team-sharing)"
    local count=0
    local renderer="$SCRIPT_DIR/scripts/render-agent.sh"
    if [[ ! -x "$renderer" ]]; then
        log ERROR "Renderer de agentes no disponible: $renderer"
        return 1
    fi
    for src in "$AGENTS_BASE_DIR"/*.md; do
        [[ -e "$src" ]] || continue
        local name; name="$(basename "$src")"
        local rendered; rendered="$(mktemp)"
        if ! bash "$renderer" "$src" > "$rendered"; then
            rm -f "$rendered"
            log ERROR "No se pudo renderizar agents/$name"
            return 1
        fi
        copy_with_diff_check "$rendered" "$AGENTS_DEST_DIR/$name" "agents/$name" >/dev/null && count=$((count+1)) || true
        rm -f "$rendered"
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

step_install_scripts() {
    log INFO "Instalando scripts teamdb en $SCRIPTS_DEST_DIR"

    run mkdir -p "$SCRIPTS_DEST_DIR"
    if [[ -e "$SCRIPTS_DEST_DIR/skalling-models.sh" ]]; then
        run rm -f "$SCRIPTS_DEST_DIR/skalling-models.sh"
    fi

    local count=0

    for script in "$SCRIPTS_SRC_DIR"/teamdb-*.sh; do
        [[ -f "$script" ]] || continue
        run cp "$script" "$SCRIPTS_DEST_DIR/"
        run chmod +x "$SCRIPTS_DEST_DIR/$(basename "$script")"
        count=$((count+1))
    done

    for script in "$SCRIPTS_SRC_DIR"/skalling-*.sh; do
        [[ -f "$script" ]] || continue
        run cp "$script" "$SCRIPTS_DEST_DIR/"
        run chmod +x "$SCRIPTS_DEST_DIR/$(basename "$script")"
        count=$((count+1))
    done
    for script in "$SCRIPTS_SRC_DIR"/skalling-*.py; do
        [[ -f "$script" ]] || continue
        run cp "$script" "$SCRIPTS_DEST_DIR/"
        run chmod +x "$SCRIPTS_DEST_DIR/$(basename "$script")"
        count=$((count+1))
    done

    if [[ -f "$SCRIPTS_SRC_DIR"/lib/lib-teamdb.sh ]]; then
        run cp "$SCRIPTS_SRC_DIR"/lib/lib-teamdb.sh "$SCRIPTS_DEST_DIR/lib-teamdb.sh"
        run chmod +x "$SCRIPTS_DEST_DIR/lib-teamdb.sh"
        count=$((count+1))
    fi
    if [[ -f "$SCRIPTS_SRC_DIR"/lib/lib-os.sh ]]; then
        run cp "$SCRIPTS_SRC_DIR"/lib/lib-os.sh "$SCRIPTS_DEST_DIR/lib-os.sh"
        run chmod +x "$SCRIPTS_DEST_DIR/lib-os.sh"
        count=$((count+1))
    fi
    if [[ -f "$SCRIPTS_SRC_DIR"/lib/lib-stack-detect.sh ]]; then
        run cp "$SCRIPTS_SRC_DIR"/lib/lib-stack-detect.sh "$SCRIPTS_DEST_DIR/lib-stack-detect.sh"
        run chmod +x "$SCRIPTS_DEST_DIR/lib-stack-detect.sh"
        count=$((count+1))
    fi
    if [[ -f "$SCRIPTS_SRC_DIR"/teamdb_exec.py ]]; then
        run cp "$SCRIPTS_SRC_DIR"/teamdb_exec.py "$SCRIPTS_DEST_DIR/"
        run cp "$SCRIPTS_SRC_DIR"/teamdb_guard.py "$SCRIPTS_DEST_DIR/"
        run cp "$SCRIPTS_SRC_DIR"/skalling_classify.py "$SCRIPTS_DEST_DIR/"
        run cp "$SCRIPTS_SRC_DIR"/teamdb_dump.py "$SCRIPTS_DEST_DIR/"
        run cp "$SCRIPTS_SRC_DIR"/skalling_config.py "$SCRIPTS_DEST_DIR/"
        run cp "$SCRIPTS_SRC_DIR"/skalling_context.py "$SCRIPTS_DEST_DIR/"
        run cp "$SCRIPTS_SRC_DIR"/teamdb-destructive.py "$SCRIPTS_DEST_DIR/"
        run chmod +x "$SCRIPTS_DEST_DIR/teamdb_exec.py"
        count=$((count+1))
    fi

    if [[ $count -gt 0 ]]; then
        log OK "$count scripts instalados"
    else
        log WARN "No se encontraron scripts para copiar"
    fi
}

# Plugins que forman el control del equipo. Van SIEMPRE juntos, en modo
# global y en modo proyecto: sin skalling-git-guard no hay identidad del
# runtime ni bloqueo de ediciones por rol, y los helpers caen al actor que
# declare el comando (pensado para la CLI humana).
SKALLING_PLUGINS=(skalling-model-fallback.js skalling-goal.js skalling-data-safety.js skalling-workflow.js skalling-git-guard.js)
SKALLING_PLUGIN_LIBS=(model-fallback.mjs data-safety.mjs workflow.mjs git-guard.mjs)
SKALLING_GIT_HOOKS=(pre-commit pre-push post-merge post-rewrite)

step_install_hooks() {
    run mkdir -p "$TARGET_DIR/.opencode/plugins/lib" "$TARGET_DIR/.opencode/command"
    local plugin
    for plugin in "${SKALLING_PLUGINS[@]}"; do
        run cp "$SCRIPT_DIR/plugins/$plugin" "$TARGET_DIR/.opencode/plugins/$plugin"
    done
    for plugin in "${SKALLING_PLUGIN_LIBS[@]}"; do
        run cp "$SCRIPT_DIR/plugins/lib/$plugin" "$TARGET_DIR/.opencode/plugins/lib/$plugin"
    done
    run cp "$SCRIPT_DIR/scripts/skalling-workflow.py" "$TARGET_DIR/.opencode/scripts/skalling-workflow.py"
    run cp "$SCRIPT_DIR/command/skalling-goal.md" "$TARGET_DIR/.opencode/command/skalling-goal.md"
    if [[ "$DRY_RUN" == false ]]; then
        for plugin in "${SKALLING_PLUGINS[@]}"; do
            [[ -f "$TARGET_DIR/.opencode/plugins/$plugin" ]] || { log ERROR "Falta plugin obligatorio: $plugin"; return 1; }
        done
        log OK "Plugins instalados: ${SKALLING_PLUGINS[*]}"
    fi

    if [[ ! -d "$HOOKS_SRC_DIR" ]]; then
        log WARN "No hay hooks en $HOOKS_SRC_DIR, skip"
        return 0
    fi
    run mkdir -p "$HOOKS_DEST_DIR"
    run cp "$HOOKS_SRC_DIR"/pre-commit "$HOOKS_DEST_DIR/"
    run cp "$HOOKS_SRC_DIR"/pre-push "$HOOKS_DEST_DIR/"
    run cp "$HOOKS_SRC_DIR"/post-merge "$HOOKS_DEST_DIR/"
    run cp "$HOOKS_SRC_DIR"/post-rewrite "$HOOKS_DEST_DIR/"
    run cp "$HOOKS_SRC_DIR"/git-gate.py "$HOOKS_DEST_DIR/"
    run chmod +x "$HOOKS_DEST_DIR"/pre-commit "$HOOKS_DEST_DIR"/pre-push "$HOOKS_DEST_DIR"/post-merge "$HOOKS_DEST_DIR"/post-rewrite

    # Repo, worktree o GIT_DIR: lo decide Git, no la existencia de .git/.
    if ! git -C "$TARGET_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        log WARN "No hay repositorio git en $TARGET_DIR. Ejecutá git init y volvé a correr setup para activar los hooks."
        return 0
    fi
    log INFO "Activando git hooks (los hooks previos del proyecto se conservan y encadenan)"
    local hook rc hooks_dir
    hooks_dir="$(cd "$HOOKS_DEST_DIR" 2>/dev/null && pwd || echo "$HOOKS_DEST_DIR")"
    for hook in "${SKALLING_GIT_HOOKS[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            echo "    [dry-run] enlazar hook $hook -> $hooks_dir/$hook (conservando uno previo como $hook.skalling-prev)"
            continue
        fi
        rc=0
        skalling_install_git_hook "$TARGET_DIR" "$hook" "$hooks_dir/$hook" || rc=$?
        case "$rc" in
            0) log OK "Hook $hook -> $hooks_dir/$hook" ;;
            2) log WARN "core.hooksPath está configurado ($(git -C "$TARGET_DIR" config --get core.hooksPath)); no se toca esa carpeta."
               log WARN "  Para activar el gate agregá al final de tu $hook: bash \"\$(git rev-parse --show-toplevel)/.opencode/hooks/$hook\" \"\$@\""
               ;;
            *) log ERROR "No se pudo instalar el hook $hook sin pisar uno existente"; return 1 ;;
        esac
    done
}

step_install_project_config() {
    # Config de OpenCode del proyecto: Alex por defecto, agentes nativos que
    # editan sin flujo deshabilitados y la política de permisos vigente.
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] python3 scripts/skalling-project-config.py $TARGET_DIR"
        return 0
    fi
    if python3 "$SCRIPT_DIR/scripts/skalling-project-config.py" "$TARGET_DIR" >/dev/null; then
        log OK "Config de OpenCode del proyecto: Alex por defecto; build/plan/general deshabilitados"
    else
        log ERROR "No se pudo escribir .opencode/opencode.json del proyecto"
        return 1
    fi
}

step_init_teamdb() {
    log INFO "Inicializando teamdb en el proyecto"

    if ! command -v sqlite3 >/dev/null 2>&1; then
        log WARN "sqlite3 no disponible, teamdb no se inicializó"
        log INFO "  Installalo: brew install sqlite3 (macOS) o apt install sqlite3 (linux)"
        return 0
    fi

    local init_script="$SCRIPTS_SRC_DIR/teamdb-init.sh"
    if [[ -x "$init_script" ]]; then
        if bash "$init_script" "$TARGET_DIR"; then
            log OK "teamdb inicializado y migrado: $CONTEXT_DIR/team.db"
        else
            log ERROR "No se pudo inicializar o migrar TeamDB"
            return 1
        fi
    else
        log ERROR "Inicializador TeamDB no encontrado: $init_script"
        return 1
    fi
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
    install_root_gitattributes_block
    install_root_gitignore_block
}

SKALLING_BLOCK_END="# --- fin Skalling (setup) ---"
SKALLING_ATTR_START="# --- Skalling: merge de memoria (gestionado por setup.sh, no editar a mano) ---"
SKALLING_IGNORE_START="# --- Skalling: artefactos locales (gestionado por setup.sh, no editar a mano) ---"

# upsert_managed_block <archivo> <marca-inicio> <línea>...: escribe (o
# reemplaza) un bloque marcado que solo toca Skalling. Idempotente; nunca
# modifica líneas del proyecto fuera del bloque.
upsert_managed_block() {
    local file="$1" start="$2"
    shift 2
    local block
    block="$(printf '%s\n' "$start" "$@" "$SKALLING_BLOCK_END")"
    if [[ -f "$file" ]] && grep -qxF "$start" "$file"; then
        local current
        current="$(awk -v s="$start" -v e="$SKALLING_BLOCK_END" '$0==s{on=1} on{print} $0==e{on=0}' "$file")"
        [[ "$current" == "$block" ]] && return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        echo "    [dry-run] escribir bloque Skalling en $file"
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    if [[ -f "$file" ]]; then
        awk -v s="$start" -v e="$SKALLING_BLOCK_END" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$file" > "$tmp"
    fi
    printf '%s\n' "$block" >> "$tmp"
    mv "$tmp" "$file"
}

remove_managed_block() {
    local file="$1" start="$2"
    [[ -f "$file" ]] && grep -qxF "$start" "$file" || return 0
    [[ "$DRY_RUN" == true ]] && { echo "    [dry-run] quitar bloque Skalling de $file"; return 0; }
    local tmp
    tmp="$(mktemp)"
    awk -v s="$start" -v e="$SKALLING_BLOCK_END" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$file" > "$tmp"
    mv "$tmp" "$file"
}

# El dump de TeamDB vive fuera de .opencode/, así que su estrategia de merge
# va en el .gitattributes raíz. El dump escribe una fila por línea: union
# conserva las filas de ambas ramas y teamdb-merge elige la más reciente.
install_root_gitattributes_block() {
    upsert_managed_block "$TARGET_DIR/.gitattributes" "$SKALLING_ATTR_START" \
        "db/teamdb/team.dump.sql merge=union" "/AGENTS.md merge=union"
    log OK ".gitattributes raíz: merge por fila del dump de TeamDB"
}

# La DB cruda es local: git guarda su fotografía (db/teamdb/team.dump.sql).
# Sin esto, un "git add ." versionaba team.db y sus backups, y el checkout de
# un pull/rebase pisaba la base local de cada persona con la de otra.
install_root_gitignore_block() {
    upsert_managed_block "$TARGET_DIR/.gitignore" "$SKALLING_IGNORE_START" \
        ".opencode/context/team.db" ".opencode/context/team.db-*" ".opencode/context/team.db.pre-migration-*" \
        ".opencode/context/.pre-migration-*" ".opencode/context/.backup-*" ".opencode/context/.backups/" \
        ".opencode/context/.legacy-backup-*" ".opencode/context/.locks/" ".opencode/context/*.lock" \
        ".opencode/context/teamdb/" ".opencode/context/review/" ".skalling-backups/" ".codegraph/" \
        ".opencode/**/__pycache__/"
    log OK ".gitignore raíz: la DB local y sus respaldos no se versionan"
    # Bytecode ya versionado: cada verificación lo reescribe y la aprobación
    # del commit fallaba para siempre por "cambios sin stagear".
    if git -C "$TARGET_DIR" ls-files -- '.opencode/**/__pycache__/*' | grep -q .; then
        warn "Hay __pycache__ de .opencode versionado; sacarlo del índice (conserva los archivos): git rm -r --cached -- '.opencode/**/__pycache__' && git commit"
    fi
    if git -C "$TARGET_DIR" ls-files --error-unmatch .opencode/context/team.db >/dev/null 2>&1; then
        warn "team.db ya está versionado: cada pull pisa la base local de otra persona. Sacarlo del índice (conserva el archivo): git rm --cached .opencode/context/team.db && git commit"
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
- `/skalling-memory` — buscar, relacionar y revisar memoria
- `/skalling-resume` — retomar trabajo con contexto mínimo
- `/skalling-recover` — recuperar TeamDB con backup

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
      │   ├── agents/      (8 agentes, commiteable)
      │   ├── skills/      (skills core)
      │   ├── scripts/     (teamdb + skalling scripts)
      │   ├── hooks/       (pre-commit, pre-push, post-merge, post-rewrite)
      │   ├── changes/     (SDD artifacts)
      │   └── context/     (bundle OKF + team.db, listo para usar)
      ├── git hooks (los previos se conservan como <hook>.skalling-prev)
      │   ├── pre-commit   (receipt de Jhon/Luz sobre lo staged)
      │   ├── pre-push     (receipt por commit publicado)
      │   └── post-merge   (DB sync from .sql)
      └── docs/            (documentación pública)

   📦 Backups: $BACKUP_DIR (mantiene últimos 5)
   📋 Log:     $INSTALL_LOG

   🚀 Abrí opencode en este proyecto. Los hooks ya están activos.

   ✍️  Commits desde tu terminal o IDE: git add … y después
      bash .opencode/scripts/skalling-approve.sh   (corre los tests; si pasan, habilita el commit)

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
    # Quitar solo los bloques de Skalling de los archivos raíz.
    remove_managed_block "$TARGET_DIR/.gitattributes" "$SKALLING_ATTR_START"
    remove_managed_block "$TARGET_DIR/.gitignore" "$SKALLING_IGNORE_START"

    # Hooks de Git: quitar los de Skalling y restaurar los que había antes.
    # Sin esto quedaban activos exigiendo una base que se acaba de borrar.
    local hook
    for hook in "${SKALLING_GIT_HOOKS[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            echo "    [dry-run] quitar hook $hook y restaurar $hook.skalling-prev si existe"
        else
            skalling_uninstall_git_hook "$TARGET_DIR" "$hook"
        fi
    done
    log OK "Hooks de Git de Skalling retirados (hooks previos restaurados)"

    # Plugins, comandos, hooks y scripts distribuidos por Skalling.
    local plugin
    for plugin in "${SKALLING_PLUGINS[@]}"; do
        [[ -f "$OPENCODE_DIR/plugins/$plugin" ]] && run rm -f "$OPENCODE_DIR/plugins/$plugin"
    done
    for plugin in "${SKALLING_PLUGIN_LIBS[@]}"; do
        [[ -f "$OPENCODE_DIR/plugins/lib/$plugin" ]] && run rm -f "$OPENCODE_DIR/plugins/lib/$plugin"
    done
    rmdir "$OPENCODE_DIR/plugins/lib" "$OPENCODE_DIR/plugins" 2>/dev/null || true
    [[ -f "$OPENCODE_DIR/command/skalling-goal.md" ]] && run rm -f "$OPENCODE_DIR/command/skalling-goal.md"
    # Devolver a OpenCode su agente por defecto y los agentes nativos: sin
    # Alex instalado, default_agent=Alex dejaría el proyecto sin agente.
    if [[ -f "$OPENCODE_DIR/opencode.json" ]]; then
        run python3 "$SCRIPT_DIR/scripts/skalling-project-config.py" "$TARGET_DIR" --remove >/dev/null
    fi
    rmdir "$OPENCODE_DIR/command" 2>/dev/null || true
    [[ -d "$HOOKS_DEST_DIR" ]] && run rm -rf "$HOOKS_DEST_DIR"
    [[ -d "$SCRIPTS_DEST_DIR" ]] && run rm -rf "$SCRIPTS_DEST_DIR"
    if [[ -d "$SKILLS_DEST_DIR" ]]; then
        local skill_dir
        for skill_dir in "$SKILLS_BASE_DIR"/*/; do
            [[ -d "$skill_dir" ]] || continue
            [[ -d "$SKILLS_DEST_DIR/$(basename "$skill_dir")" ]] && run rm -rf "$SKILLS_DEST_DIR/$(basename "$skill_dir")"
        done
        rmdir "$SKILLS_DEST_DIR" 2>/dev/null || true
    fi
    rmdir "$AGENTS_DEST_DIR" 2>/dev/null || true
    log OK "Plugins, hooks, scripts y skills de Skalling retirados"

    # Preguntar antes de borrar bundle OKF (memoria es valiosa)
    if [[ -d "$CONTEXT_DIR" ]]; then
        if [[ "$FORCE" == true ]] || ask_yes_no "    ¿Borrar bundle OKF (.opencode/context/)? Tiene memoria del proyecto." "n"; then
            rm -rf "$CONTEXT_DIR"
            log INFO "Bundle OKF borrado"
        else
            log INFO "Bundle OKF preservado"
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

# La capa autoritativa (docs/security-model.md): CI que re-corre los tests
# del proyecto y CODEOWNERS para lo que se ejecuta en cada máquina. Solo crea
# archivos que no existen; nunca pisa un workflow o CODEOWNERS del proyecto.
step_install_ci() {
    log INFO "CI y CODEOWNERS (.github/)"
    run mkdir -p "$TARGET_DIR/.github/workflows"
    local workflow="$TARGET_DIR/.github/workflows/skalling-verify.yml"
    local owners="$TARGET_DIR/.github/CODEOWNERS"
    if [[ -f "$workflow" ]]; then
        log INFO "skalling-verify.yml ya existe, se preserva"
    else
        run cp "$SCRIPT_DIR/templates/ci/skalling-verify.yml" "$workflow"
        log OK "Workflow de CI instalado: .github/workflows/skalling-verify.yml"
    fi
    if [[ -f "$owners" || -f "$TARGET_DIR/CODEOWNERS" || -f "$TARGET_DIR/docs/CODEOWNERS" ]]; then
        log WARN "Ya hay un CODEOWNERS: agregá a mano las rutas de templates/ci/CODEOWNERS.template"
    else
        run cp "$SCRIPT_DIR/templates/ci/CODEOWNERS.template" "$owners"
        log WARN "CODEOWNERS instalado con @OWNER de ejemplo: reemplazalo por el responsable real"
    fi
    log INFO "Falta activarlo en GitHub: rama principal protegida, check 'Skalling / tests del proyecto' obligatorio y revisión de Code Owners"
}

main() {
    echo ""
    if [[ "$UNINSTALL" == true ]]; then
        do_uninstall
        exit 0
    fi

    log INFO "Iniciando setup per-project de Skalling v${SKALLING_VERSION}"
    log INFO "Target: $TARGET_DIR"
    echo ""

    skalling_require_dependencies
    if command -v opencode >/dev/null 2>&1; then
        local oc_version; oc_version="$(opencode --version 2>/dev/null || echo unknown)"
        if [[ "$(skalling_opencode_support "$oc_version")" == unsupported ]]; then
            log ERROR "opencode $oc_version no está soportado: mínimo $SKALLING_OPENCODE_MIN (antes no carga los plugins de control)."
            exit 1
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log WARN "Modo dry-run activo — no se modifica nada"
    fi

    create_backup
    step_create_directories
    step_install_agents
    step_install_skills
    step_install_gitattributes
    step_install_scripts
    step_install_hooks
    step_install_project_config
    step_init_teamdb
    step_install_agents_md
    if [[ "$WITH_CI" == true ]]; then step_install_ci; fi

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "Dry-run completo. Sin cambios."
    else
        step_summary
    fi
}

main
