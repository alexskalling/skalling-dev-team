#!/usr/bin/env bash
# lib-os.sh — Funciones compartidas de detección de OS y rutas.
#
# Sourcear desde otros scripts bash:
#   source "$(dirname "$0")/lib/lib-os.sh"
#
# Define:
#   skalling_os                — "macos" | "linux" | "wsl" | "gitbash" | "windows" | "unknown"
#   skalling_opencode_dir      — ruta absoluta al directorio de config de opencode
#   skalling_home              — ruta al home del usuario
#   skalling_path_sep          — "/" en Unix, "\" en Windows
#   skalling_log_os            — log con info del OS detectado

# ──────────────────────────────────────────────────────────────────────────────
# DETECCIÓN DE OS
# ──────────────────────────────────────────────────────────────────────────────

skalling_detect_os() {
    local ostype="${OSTYPE:-unknown}"
    local wsl_marker=""

    # Detectar WSL (Windows Subsystem for Linux)
    if [[ -f /proc/version ]]; then
        if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
            wsl_marker="wsl"
        fi
    fi

    case "$ostype" in
        darwin*)
            if [[ -n "$wsl_marker" ]]; then
                echo "wsl"
            else
                echo "macos"
            fi
            ;;
        linux*)
            if [[ -n "$wsl_marker" ]]; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        msys*|mingw*|cygwin*)
            echo "gitbash"
            ;;
        win32*|windows*)
            echo "windows"
            ;;
        *)
            # Fallback: check uname
            local uname_s; uname_s="$(uname -s 2>/dev/null || echo unknown)"
            case "$uname_s" in
                Darwin) echo "macos" ;;
                Linux)
                    if [[ -n "$wsl_marker" ]]; then
                        echo "wsl"
                    else
                        echo "linux"
                    fi
                    ;;
                MINGW*|MSYS*|CYGWIN*) echo "gitbash" ;;
                *) echo "unknown" ;;
            esac
            ;;
    esac
}

SKALLING_OS="$(skalling_detect_os)"

# ──────────────────────────────────────────────────────────────────────────────
# RUTAS
# ──────────────────────────────────────────────────────────────────────────────

# Home del usuario (compatible con Git Bash, WSL, macOS, Linux)
if [[ -n "$HOME" ]]; then
    SKALLING_HOME="$HOME"
elif [[ -n "$USERPROFILE" ]]; then
    SKALLING_HOME="$USERPROFILE"
else
    SKALLING_HOME="$(cd ~ && pwd 2>/dev/null || echo "/tmp")"
fi

# OpenCode dir (skalling lo respeta en todas las plataformas)
# Permite override por env (tests/usuarios avanzados); solo default si no está seteado.
if [[ -z "${SKALLING_OPENCODE_DIR:-}" ]]; then
    SKALLING_OPENCODE_DIR="${SKALLING_HOME}/.config/opencode"
fi

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS DE LOGGING
# ──────────────────────────────────────────────────────────────────────────────

skalling_log_os() {
    local icon
    case "$SKALLING_OS" in
        macos)   icon="" ;;
        linux)   icon="🐧" ;;
        wsl)     icon="🐧" ;;
        gitbash) icon="" ;;
        windows) icon="🪟" ;;
        *)       icon="❓" ;;
    esac
    printf '  %s OS detectado: %s\n' "$icon" "$SKALLING_OS"
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDACIÓN DE BASH
# ──────────────────────────────────────────────────────────────────────────────

# Dependencias mínimas para que el modelo DB-first funcione de verdad.
# No se consideran opcionales: sin sqlite3 o Python los agentes pueden quedar
# instalados, pero no pueden consultar/escribir TeamDB de forma segura.
skalling_require_dependencies() {
    local missing=""
    local dependency
    for dependency in sqlite3 python3; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            missing="${missing}${missing:+ }${dependency}"
        fi
    done

    if [[ -z "$missing" ]]; then
        return 0
    fi

    printf 'ERROR: faltan dependencias requeridas: %s\n' "$missing" >&2
    case "$SKALLING_OS" in
        macos)
            printf 'Instalación sugerida: brew install sqlite3 python\n' >&2
            ;;
        linux|wsl)
            printf 'Debian/Ubuntu: sudo apt-get install sqlite3 python3\n' >&2
            printf 'Fedora/RHEL:   sudo dnf install sqlite python3\n' >&2
            printf 'Arch:          sudo pacman -S sqlite python\n' >&2
            ;;
        gitbash)
            printf 'En Windows se recomienda WSL2; dentro de WSL: sudo apt-get install sqlite3 python3\n' >&2
            ;;
        *)
            printf 'Instalá SQLite 3 y Python 3, y volvé a ejecutar el instalador.\n' >&2
            ;;
    esac
    return 1
}

# ──────────────────────────────────────────────────────────────────────────────
# WRAPPERS PORTABLES
# ──────────────────────────────────────────────────────────────────────────────

# Reemplazo portable para `sed -i ''` (macOS) vs `sed -i` (Linux/Git Bash)
skalling_sed_inplace() {
    local file="$1"
    shift
    if [[ "$SKALLING_OS" == "macos" ]]; then
        sed -i '' "$@" "$file"
    else
        sed -i "$@" "$file"
    fi
}

# SHA-256 portable: GNU/Linux y algunos macOS traen sha256sum; macOS estándar
# trae shasum; OpenSSL queda como último fallback.
skalling_sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 | awk '{print $NF}'
    else
        echo "ERROR: se requiere sha256sum, shasum u openssl para verificar backups" >&2
        return 1
    fi
}

skalling_sha256_file() {
    local file="$1"
    skalling_sha256_stream < "$file"
}

skalling_sha256_tree() {
    local root="$1"
    find "$root" -type f -not -path "*/.skalling-backups/*" -print 2>/dev/null \
        | LC_ALL=C sort \
        | while IFS= read -r file; do
            printf '%s  %s\n' "$(skalling_sha256_file "$file")" "$file"
          done \
        | skalling_sha256_stream
}

# ──────────────────────────────────────────────────────────────────────────────
# GIT HOOKS: instalar sin destruir hooks ajenos
# ──────────────────────────────────────────────────────────────────────────────
# Un hook que ya existía (del equipo: lint, secretos, husky viejo) NO se borra:
# se renombra a <hook>.skalling-prev y el hook de Skalling lo ejecuta primero.
# La ruta la resuelve Git (worktrees, GIT_DIR, core.hooksPath), no "$p/.git".
# Si el proyecto usa core.hooksPath (husky, carpeta versionada), no se toca esa
# carpeta: se avisa y se devuelve 2 para que el instalador lo informe.

skalling_git_hooks_dir() {
  local project="$1" dir
  dir="$(git -C "$project" rev-parse --git-path hooks 2>/dev/null)" || return 1
  case "$dir" in
    /*) printf '%s\n' "$dir" ;;
    *) printf '%s\n' "$project/$dir" ;;
  esac
}

# Devuelve 0 si el archivo es un hook de Skalling (actual o de versiones
# anteriores, instalado como copia o como symlink).
skalling_is_skalling_hook() {
  local path="$1"
  [ -e "$path" ] || return 1
  grep -qE 'skalling-hook|Read-only gate: never repairs DB|post-merge hook: mergea el dump versionado' "$path" 2>/dev/null
}

# skalling_install_git_hook <project> <hook> <script_propio> [--copy]
# 0 = instalado/ya estaba, 1 = error, 2 = omitido por core.hooksPath
skalling_install_git_hook() {
  local project="$1" hook="$2" ours="$3" mode="${4:-}" dir dst prev
  git -C "$project" rev-parse --git-dir >/dev/null 2>&1 || return 1
  if [ -n "$(git -C "$project" config --get core.hooksPath 2>/dev/null || true)" ]; then
    return 2
  fi
  dir="$(skalling_git_hooks_dir "$project")" || return 1
  mkdir -p "$dir"
  dst="$dir/$hook"
  prev="$dst.skalling-prev"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$ours" ]; then
    return 0
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if ! skalling_is_skalling_hook "$dst"; then
      if [ -e "$prev" ] || [ -L "$prev" ]; then
        echo "ERROR: $dst no es de Skalling y ya existe $prev; no se sobrescribe ninguno. Resolver a mano." >&2
        return 1
      fi
      mv "$dst" "$prev"
      echo "INFO: hook previo conservado como $prev (Skalling lo ejecuta primero)" >&2
    else
      rm -f "$dst"  # lens:ok: dst es .git/hooks/<hook> y skalling_is_skalling_hook confirmó que es nuestro
    fi
  fi
  if [ "$mode" = "--copy" ]; then
    cp "$ours" "$dst" && chmod +x "$dst"
  else
    ln -s "$ours" "$dst"
  fi
}

# skalling_uninstall_git_hook <project> <hook>: quita el hook de Skalling y
# restaura el que había antes de instalar.
skalling_uninstall_git_hook() {
  local project="$1" hook="$2" dir dst prev
  dir="$(skalling_git_hooks_dir "$project")" || return 0
  dst="$dir/$hook"
  prev="$dst.skalling-prev"
  if { [ -e "$dst" ] || [ -L "$dst" ]; } && { skalling_is_skalling_hook "$dst" || { [ -L "$dst" ] && [ ! -e "$dst" ] && case "$(readlink "$dst")" in *opencode*/hooks/"$hook") true ;; *) false ;; esac; }; }; then
    rm -f "$dst"  # lens:ok: dst es .git/hooks/<hook>; la condición de arriba exige que sea hook de Skalling
  fi
  if { [ -e "$prev" ] || [ -L "$prev" ]; } && [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$prev" "$dst"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# COMPATIBILIDAD CON OPENCODE (matriz de soporte, ver README)
# ──────────────────────────────────────────────────────────────────────────────
# Solo OpenCode 2. El bundle incluye plugins de directorio verificados en 2.0.21.
export SKALLING_OPENCODE_MIN="2.0.21"

# skalling_opencode_support "<salida de opencode --version>"
# imprime unsupported | v2 | unknown. No promete soporte de majors futuros.
skalling_opencode_support() {
  local raw="$1" ver major minor patch
  ver="$(printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [ -n "$ver" ] || { echo unknown; return 0; }
  IFS=. read -r major minor patch <<EOF_VER
$ver
EOF_VER
  if [ "$major" -eq 2 ] && { [ "$minor" -gt 0 ] || [ "$patch" -ge 21 ]; }; then
    echo v2; return 0
  fi
  echo unsupported
}

# Retira únicamente artefactos propios de versiones anteriores. El caller ya
# respaldó la instalación (salvo su opción explícita de omitir backup).
# Usa run para respetar --dry-run; conserva bases y plugins del usuario.
skalling_remove_retired_artifacts() {
  local dir="$1" artifact
  for artifact in plugins/skalling-goal.js scripts/skalling-goal.sh scripts/skalling-goal.py command/skalling-goal.md \
      plugins/skalling-execution-efficiency.js \
      scripts/test-teamdb-safe.sh scripts/test-teamdb-git-sync.sh \
      templates/okf/README.template.md \
      templates/okf/concept.template.md \
      templates/okf/context.template.md \
      templates/okf/decision.template.md \
      templates/okf/decisiones-index.template.md \
      templates/okf/index.template.md \
      templates/okf/log.template.md \
      templates/okf/preference.template.md \
      templates/okf/preferencias-index.template.md \
      templates/okf/problemas-conocidos-index.template.md \
      templates/okf/proyecto-index.template.md \
      templates/okf/proyecto-que-es.template.md \
      templates/okf/stack-concept.template.md \
      templates/okf/stack-index.template.md \
      templates/okf/trabajo-en-curso-index.template.md \
      templates/okf/work-in-progress.template.md \
      templates/okf/workaround.template.md \
      templates/changes/design.template.md \
      templates/changes/proposal.template.md \
      templates/changes/spec.template.md \
      templates/changes/tasks.template.md; do
    if [ -f "$dir/$artifact" ]; then run rm -f "$dir/$artifact"; fi
  done
}
