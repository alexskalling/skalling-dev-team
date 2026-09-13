#!/usr/bin/env bash
# build-local-snapshot.sh — Genera / verifica / simula el bundle local
# .opencode/scripts/ desde scripts/ siguiendo scripts/.bundle-manifest.
#
# Uso:
#   bash scripts/build-local-snapshot.sh --apply     # sincroniza dst desde src
#   bash scripts/build-local-snapshot.sh --check     # exit 0 si dst coincide byte-a-byte
#   bash scripts/build-local-snapshot.sh --dry-run   # imprime plan sin ejecutar
#
# Opciones adicionales (todas con --flag=valor):
#   --manifest=<path>   default: scripts/.bundle-manifest
#   --src=<path>        default: scripts/
#   --dst=<path>        default: .opencode/scripts/
#
# Tabla de exit codes:
#   0  éxito (apply, dry-run, o check sin drift)
#   1  drift detectado (check), src faltante, manifest malformado, etc.
#   2  argumentos inválidos
#
# Formato del manifest (TSV):
#   src_path<TAB>dst_path<TAB>sha256_src<TAB>sha256_dst
#   La cuarta columna (sha256_dst) es informativa; --check recomputa contra
#   archivos reales y no la usa para comparar.

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Defaults / parse
# ──────────────────────────────────────────────────────────────────────────────

MODE=""
MANIFEST=""
SRC_DIR=""
DST_DIR=""

usage() {
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) MODE="apply"; shift ;;
        --check) MODE="check"; shift ;;
        --dry-run) MODE="dry-run"; shift ;;
        --manifest=*) MANIFEST="${1#--manifest=}"; shift ;;
        --manifest) MANIFEST="${2:?--manifest requires value}"; shift 2 ;;
        --src=*) SRC_DIR="${1#--src=}"; shift ;;
        --src) SRC_DIR="${2:?--src requires value}"; shift 2 ;;
        --dst=*) DST_DIR="${1#--dst=}"; shift ;;
        --dst) DST_DIR="${2:?--dst requires value}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "ERROR: argumento desconocido: $1" >&2; usage 2 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "ERROR: debe especificar --apply | --check | --dry-run" >&2
    usage 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -n "$MANIFEST" ]] || MANIFEST="${REPO_ROOT}/scripts/.bundle-manifest"
[[ -n "$SRC_DIR" ]]   || SRC_DIR="${REPO_ROOT}/scripts"
[[ -n "$DST_DIR" ]]   || DST_DIR="${REPO_ROOT}/.opencode/scripts"

# Normalizar a absolutos si hace falta
[[ "$MANIFEST" = /* ]] || MANIFEST="${REPO_ROOT}/${MANIFEST}"
[[ "$SRC_DIR" = /* ]]   || SRC_DIR="${REPO_ROOT}/${SRC_DIR}"
[[ "$DST_DIR" = /* ]]   || DST_DIR="${REPO_ROOT}/${DST_DIR}"

if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: manifest no existe: $MANIFEST" >&2
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────────────────────────────────────

c_red=$'\033[31m'
c_green=$'\033[32m'
c_yellow=$'\033[33m'
c_blue=$'\033[34m'
c_reset=$'\033[0m'

info()  { printf "%s[i]%s %s\n" "$c_blue" "$c_reset" "$*" >&2; }
ok()    { printf "%s[✓]%s %s\n" "$c_green" "$c_reset" "$*" >&2; }
warn()  { printf "%s[!]%s %s\n" "$c_yellow" "$c_reset" "$*" >&2; }
err()   { printf "%s[✗]%s %s\n" "$c_red" "$c_reset" "$*" >&2; }

# ──────────────────────────────────────────────────────────────────────────────
# Manifest loader: emite pares "src_rel<TAB>dst_rel" en stdout
# ──────────────────────────────────────────────────────────────────────────────

load_pairs() {
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        # Saltar comentarios y líneas vacías
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
        # Saltar header (línea que comienza con "src_path")
        if [[ "$line_num" == "1" && "${line%%	*}" == "src_path" ]]; then
            continue
        fi
        # Formato: src<TAB>dst<TAB>src_sha<TAB>dst_sha
        local IFS=$'\t'
        read -r src_rel dst_rel _src_sha _dst_sha <<< "$line" || {
            err "manifest línea $line_num malformada: $line"
            return 1
        }
        if [[ -z "$src_rel" || -z "$dst_rel" ]]; then
            err "manifest línea $line_num incompleta: $line"
            return 1
        fi
        printf '%s\t%s\n' "$src_rel" "$dst_rel"
    done < "$MANIFEST"
}

# ──────────────────────────────────────────────────────────────────────────────
# Acción: --apply (atómico, preserva permisos, idempotente)
# ──────────────────────────────────────────────────────────────────────────────

apply_one() {
    local src="$1" dst="$2"
    if [[ ! -f "$src" ]]; then
        err "src faltante: $src"
        return 1
    fi
    mkdir -p "$(dirname "$dst")"
    local tmp
    tmp="$(mktemp "$(dirname "$dst")/.${RANDOM}.tmp.XXXXXX")"
    # cp -p preserva modo/timestamps; atrapa fallo para no dejar tmp huérfano
    if ! cp -p "$src" "$tmp"; then
        rm -f "$tmp"
        err "falló cp -p $src → $tmp"
        return 1
    fi
    if ! mv -f "$tmp" "$dst"; then
        rm -f "$tmp"
        err "falló rename atómico $tmp → $dst"
        return 1
    fi
    printf "%s\n" "$dst"
}

# ──────────────────────────────────────────────────────────────────────────────
# Acción: --check (compara byte-a-byte vía sha256)
# ──────────────────────────────────────────────────────────────────────────────

check_one() {
    local src="$1" dst="$2"
    local src_sha="" dst_sha="" status=0
    if [[ ! -f "$src" ]]; then
        err "drift: src falta: $src (manifest referencia rota)"
        status=1
    fi
    if [[ ! -f "$dst" ]]; then
        err "drift: dst falta: $dst"
        status=1
    fi
    if [[ -f "$src" && -f "$dst" ]]; then
        src_sha="$(sha256sum < "$src" | awk '{print $1}')"
        dst_sha="$(sha256sum < "$dst" | awk '{print $1}')"
        if [[ "$src_sha" != "$dst_sha" ]]; then
            err "drift: $src -> $dst"
            err "      src_sha=$src_sha"
            err "      dst_sha=$dst_sha"
            status=1
        fi
    fi
    return "$status"
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────────────────

case "$MODE" in
    dry-run)
        info "dry-run · manifest=$MANIFEST src=$SRC_DIR dst=$DST_DIR"
        local_rc=0
        while IFS=$'\t' read -r src_rel dst_rel; do
            [[ -z "$src_rel" ]] && continue
            src="${SRC_DIR}/${src_rel}"
            dst="${DST_DIR}/${dst_rel}"
            if [[ -f "$src" ]]; then
                printf '  COPY %s -> %s\n' "$src_rel" "$dst_rel"
            else
                printf '  MISSING %s\n' "$src_rel" >&2
                local_rc=1
            fi
        done < <(load_pairs) || local_rc=1
        if [[ "$local_rc" == "0" ]]; then
            ok "plan ready (sin ejecutar)"
            exit 0
        else
            err "plan con archivos faltantes"
            exit 1
        fi
        ;;

    apply)
        info "apply · manifest=$MANIFEST src=$SRC_DIR dst=$DST_DIR"
        local_rc=0
        applied=0
        while IFS=$'\t' read -r src_rel dst_rel; do
            [[ -z "$src_rel" ]] && continue
            src="${SRC_DIR}/${src_rel}"
            dst="${DST_DIR}/${dst_rel}"
            if apply_one "$src" "$dst"; then
                applied=$((applied+1))
            else
                local_rc=1
            fi
        done < <(load_pairs) || local_rc=1
        ok "apply copiados=$applied rc=$local_rc"
        exit "$local_rc"
        ;;

    check)
        # No imprimir "info" grande — quiero silencio para uso en CI
        local_rc=0
        while IFS=$'\t' read -r src_rel dst_rel; do
            [[ -z "$src_rel" ]] && continue
            src="${SRC_DIR}/${src_rel}"
            dst="${DST_DIR}/${dst_rel}"
            if ! check_one "$src" "$dst"; then
                local_rc=1
            fi
        done < <(load_pairs) || local_rc=1

        # Huérfanos: archivos en DST_DIR que no están listados en el manifest
        # (whitelist = columna dst_path). Antes esto solo lo detectaba el test;
        # el doctor y CI llaman a este script, no al test, así que sin esto un
        # archivo copiado a mano en .opencode/scripts/ pasaba inadvertido.
        if [[ -d "$DST_DIR" ]]; then
            whitelist="$(load_pairs | awk -F'\t' '{print $2}' | sort -u)"
            actual="$(find "$DST_DIR" -maxdepth 1 -type f ! -name '*.tmp*' -exec basename {} \; 2>/dev/null | sort)"
            orphans="$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$whitelist") 2>/dev/null || true)"
            if [[ -n "$orphans" ]]; then
                while IFS= read -r orphan; do
                    [[ -z "$orphan" ]] && continue
                    err "huérfano: ${DST_DIR}/${orphan} (no está en el manifest)"
                done <<< "$orphans"
                local_rc=1
            fi
        fi

        if [[ "$local_rc" == "0" ]]; then
            exit 0
        fi
        err "drift detectado"
        exit 1
        ;;

    *)
        echo "ERROR: modo inválido: $MODE" >&2
        exit 2
        ;;
esac
