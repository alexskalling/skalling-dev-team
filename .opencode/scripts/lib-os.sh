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
#   skalling_require_bash_3    — chequea que bash >= 3

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

skalling_log_paths() {
    printf '  HOME:    %s\n' "$SKALLING_HOME"
    printf '  Config:  %s\n' "$SKALLING_OPENCODE_DIR"
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDACIÓN DE BASH
# ──────────────────────────────────────────────────────────────────────────────

skalling_require_bash_3() {
    local major="${BASH_VERSINFO[0]:-0}"
    if [[ "$major" -lt 3 ]]; then
        echo "ERROR: bash >= 3 requerido. Tenés: ${BASH_VERSION:-unknown}" >&2
        return 1
    fi
    if [[ "$major" -lt 4 ]]; then
        # bash 3.2 (default macOS) funciona pero no tenemos arrays asociativos
        return 0
    fi
    return 0
}

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

# Reemplazo portable para `realpath`
skalling_realpath() {
    local path="$1"
    if [[ "$SKALLING_OS" == "macos" ]]; then
        [[ -d "$path" ]] && cd "$path" && pwd || echo "$path"
    else
        realpath "$path" 2>/dev/null || readlink -f "$path" 2>/dev/null || echo "$path"
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

# Detecta si hay bash disponible para wrappers PowerShell
skalling_has_bash() {
    command -v bash >/dev/null 2>&1 || return 1
    command -v git >/dev/null 2>&1 || return 1
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# ESCRITURA ATÓMICA
# ──────────────────────────────────────────────────────────────────────────────

# Escribe contenido a un archivo de forma atómica (write-then-rename).
# Evita archivos corruptos si el proceso crashea mid-write.
#
# Uso: skalling_atomic_write "path/al/archivo" "contenido"
skalling_atomic_write() {
    local file_path="$1"
    local content="$2"
    local dir; dir="$(dirname "$file_path")"
    local tmp_file; tmp_file="${file_path}.tmp.$$"

    # Asegurar que el directorio existe
    [[ -d "$dir" ]] || mkdir -p "$dir"

    # Escribir a archivo temporal
    printf '%s' "$content" > "$tmp_file" || return 1

    # Atomic rename (POSIX garantiza atomicidad en mismo filesystem)
    mv -f "$tmp_file" "$file_path" || {
        rm -f "$tmp_file" 2>/dev/null
        return 1
    }

    return 0
}

# Append atómico a un archivo (usa flock si está disponible, fallback a tmp+cat).
# Uso: skalling_atomic_append "path/al/archivo" "línea a appendear"
skalling_atomic_append() {
    local file_path="$1"
    local line="$2"
    local dir; dir="$(dirname "$file_path")"

    [[ -d "$dir" ]] || mkdir -p "$dir"
    [[ -f "$file_path" ]] || touch "$file_path"

    if command -v flock >/dev/null 2>&1; then
        # Con flock (Linux): append bajo lock
        (
            flock -x 200
            printf '%s\n' "$line" >> "$file_path"
        ) 200>"${file_path}.lock"
        rm -f "${file_path}.lock"
    else
        # Sin flock (macOS sin coreutils): leer todo + append + write atómico
        local current; current="$(cat "$file_path" 2>/dev/null || true)"
        local new_content="${current}${line}
"
        skalling_atomic_write "$file_path" "$new_content"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MEMORY SIZE LIMITS
# ──────────────────────────────────────────────────────────────────────────────

# Verifica si el bundle OKF excede el size limit (default 5MB).
# Output: "OK" | "WARN: size=X KB" | "ERROR: size=X KB"
skalling_check_bundle_size() {
    local bundle_dir="$1"
    local max_kb="${2:-5120}"  # 5MB default

    [[ ! -d "$bundle_dir" ]] && { echo "ERROR: bundle no existe"; return 1; }

    local size_kb
    size_kb="$(du -sk "$bundle_dir" 2>/dev/null | awk '{print $1}')"

    if [[ -z "$size_kb" ]]; then
        echo "WARN: no se pudo medir tamaño"
        return 0
    fi

    if [[ "$size_kb" -gt "$max_kb" ]]; then
        echo "ERROR: size=${size_kb} KB excede max=${max_kb} KB"
        return 2
    elif [[ "$size_kb" -gt $((max_kb / 2)) ]]; then
        echo "WARN: size=${size_kb} KB (>50% del max=${max_kb} KB)"
        return 0
    else
        echo "OK: size=${size_kb} KB"
        return 0
    fi
}

# Cuenta concept docs (excluyendo README, index, log) por tipo.
# Output: "Concept:N Decision:N Preference:N ..."
skalling_count_concept_docs() {
    local bundle_dir="$1"

    [[ ! -d "$bundle_dir" ]] && return 1

    # Buscar en subdirs: decisiones/, preferencias/, etc.
    # Más simple: contar archivos con frontmatter type: X
    local counts
    counts="$(find "$bundle_dir" -type f -name "*.md" \
        -not -name "README.md" -not -name "index.md" -not -name "log.md" \
        -exec awk '/^type:/ { print; exit }' {} \; 2>/dev/null \
        | awk '{gsub(/^type:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); print}' \
        | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')"

    echo "${counts% }"
}
