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

    # Detectar Git Bash en Windows
    local git_bash=false
    if [[ -n "${MSYSTEM:-}" ]] || uname -s 2>/dev/null | grep -qiE "mingw|msys"; then
        git_bash=true
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

# Path separator según OS
case "$SKALLING_OS" in
    windows) SKALLING_PATH_SEP="\\" ;;
    *) SKALLING_PATH_SEP="/" ;;
esac

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
        -exec grep -l "^type:" {} \; 2>/dev/null \
        | xargs -I {} grep -h "^type:" {} 2>/dev/null \
        | awk '{gsub(/^type:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); print}' \
        | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')"

    echo "${counts% }"
}
