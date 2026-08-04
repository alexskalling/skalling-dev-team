#!/usr/bin/env bash
# scripts/lib/lib-memory-check.sh — Detección de issues en el bundle OKF (.opencode/context/).
#
# Sourcear desde otros scripts bash:
#   source "$(dirname "$0")/scripts/lib/lib-memory-check.sh"
#
# Funciones exportadas (todas exit 0; imprimen paths uno por línea o vacío):
#   skalling_parse_yaml_field <file> <field>
#                                   Extrae un campo simple del frontmatter YAML.
#   skalling_find_orphans [context_dir]
#                                   Concept docs no referenciados desde ningún index.md.
#   skalling_find_zombie_wip [context_dir] [días]
#                                   WIP en trabajo-en-curso/ sin cerrar hace > N días
#                                   con todas las tareas [x]. Default 30; override
#                                   por SKALLING_WIP_ZOMBIE_DAYS.
#   skalling_find_duplicates [context_dir]
#                                   Concept docs con título normalizado idéntico.
#                                   Salida: paths agrupados consecutivamente.
#   skalling_find_stale [context_dir] [meses]
#                                   Concept docs sin referenciar desde index.md
#                                   Y con mtime > N meses. Default 6; override por
#                                   SKALLING_STALE_MONTHS.
#   skalling_find_superseded [context_dir]
#                                   Concept docs con frontmatter `superseded: true`
#                                   o `status: superseded`.
#
# Notas:
#   - Funciones defensivas: si el bundle no existe o no hay matches, retorna vacío.
#   - Parser YAML sin yq: regex simple sobre el frontmatter. Si yq está disponible,
#     se podría usar como accelerator (no implementado por portabilidad).
#   - set -euo pipefail del archivo se propaga al sourcear (convenio del repo).

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS INTERNOS (prefijo _skalling_, no exportados)
# ──────────────────────────────────────────────────────────────────────────────

# _skalling_normalize_title <title>
# Lowercase + trim + sin acentos. Usado por find_duplicates.
_skalling_normalize_title() {
    local title="$1"
    echo "$title" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
        | sed -E 's/[áàäâã]/a/g; s/[éèëê]/e/g; s/[íìïî]/i/g; s/[óòöôõ]/o/g; s/[úùüû]/u/g; s/ñ/n/g; s/ç/c/g'
}

# _skalling_list_concept_files <context_dir>
# Lista archivos .md relevantes (excluye index/README/log). Imprime paths.
_skalling_list_concept_files() {
    local context_dir="$1"
    [[ -d "$context_dir" ]] || return 0
    find "$context_dir" -maxdepth 2 -name "*.md" \
        -not -name "index.md" \
        -not -name "README.md" \
        -not -name "log.md" 2>/dev/null || true
}

# _skalling_is_referenced <context_dir> <basename>
# Retorna 0 si basename aparece en algún index.md bajo context_dir.
_skalling_is_referenced() {
    local context_dir="$1"
    local basename="$2"

    local idx_files
    idx_files="$(find "$context_dir" -name "index.md" 2>/dev/null || true)"
    [[ -n "$idx_files" ]] || return 1

    local found="false"
    for idx_file in $idx_files; do
        if grep -qF "$basename" "$idx_file" 2>/dev/null; then
            found="true"
            break
        fi
    done

    [[ "$found" == "true" ]]
}

# _skalling_timestamp_to_epoch <ts>
# Convierte timestamp YAML (YYYY-MM-DDTHH:MM:SSZ) a epoch segundos.
# Compatible con BSD date (macOS) y GNU date (Linux).
_skalling_timestamp_to_epoch() {
    local ts="$1"
    [[ -n "$ts" ]] || { echo 0; return 0; }
    local epoch
    epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
        || date -d "$ts" +%s 2>/dev/null \
        || echo 0)"
    echo "$epoch"
}

# ──────────────────────────────────────────────────────────────────────────────
# API PÚBLICA
# ──────────────────────────────────────────────────────────────────────────────

# skalling_parse_yaml_field <file> <field>
# Lee el campo <field> del frontmatter YAML. Si no existe, retorna string vacío.
# Funciona con grep + sed (sin dependencia de yq).
skalling_parse_yaml_field() {
    local file="$1"
    local field="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 0
    fi

    local value
    value="$(
        grep -E "^${field}:" "$file" 2>/dev/null \
            | head -1 \
            | sed -E "s/^${field}:[[:space:]]*//" \
            | sed -E "s/^[\"']//; s/[\"']\$//" \
            || true
    )"
    echo "$value"
}

# skalling_find_orphans [context_dir]
# Imprime paths a concept docs no referenciados desde ningún index.md.
# Default context_dir: ".opencode/context" (relativo a cwd).
skalling_find_orphans() {
    local context_dir="${1:-.opencode/context}"
    [[ -d "$context_dir" ]] || return 0

    local orphans=()
    local md_files
    md_files="$(_skalling_list_concept_files "$context_dir")"

    for md_file in $md_files; do
        local basename; basename="$(basename "$md_file" .md)"
        if ! _skalling_is_referenced "$context_dir" "$basename"; then
            orphans+=("$md_file")
        fi
    done

    if [[ ${#orphans[@]} -gt 0 ]]; then
        printf "%s\n" "${orphans[@]}"
    fi
    return 0
}

# skalling_find_zombie_wip [context_dir] [días]
# Imprime paths en trabajo-en-curso/ con timestamp > N días Y todas las tareas [x].
skalling_find_zombie_wip() {
    local context_dir="${1:-.opencode/context}"
    local days="${2:-${SKALLING_WIP_ZOMBIE_DAYS:-30}}"

    local wip_dir="$context_dir/trabajo-en-curso"
    [[ -d "$wip_dir" ]] || return 0

    local now_epoch; now_epoch="$(date +%s)"
    local zombies=()
    local wip_files
    wip_files="$(find "$wip_dir" -maxdepth 1 -name "*.md" 2>/dev/null || true)"

    for md_file in $wip_files; do
        local ts; ts="$(skalling_parse_yaml_field "$md_file" timestamp)"
        [[ -n "$ts" ]] || continue

        local ts_epoch
        ts_epoch="$(_skalling_timestamp_to_epoch "$ts")"
        [[ "$ts_epoch" -gt 0 ]] || continue

        local age_days=$(( (now_epoch - ts_epoch) / 86400 ))
        [[ "$age_days" -gt "$days" ]] || continue

        if grep -qE '^[[:space:]]*-[[:space:]]*\[ \]' "$md_file" 2>/dev/null; then
            continue
        fi

        zombies+=("$md_file")
    done

    if [[ ${#zombies[@]} -gt 0 ]]; then
        printf "%s\n" "${zombies[@]}"
    fi
    return 0
}

# skalling_find_duplicates [context_dir]
# Imprime paths agrupados consecutivamente: misma línea vacía entre grupos.
# Cada grupo corresponde a un título normalizado idéntico.
# Implementación portable: usa sort+awk en lugar de declare -A (incompatible con
# bash 3.2 que es el default en macOS hasta la fecha).
skalling_find_duplicates() {
    local context_dir="${1:-.opencode/context}"
    [[ -d "$context_dir" ]] || return 0

    local md_files
    md_files="$(_skalling_list_concept_files "$context_dir")"

    local pairs=""
    for md_file in $md_files; do
        local title; title="$(skalling_parse_yaml_field "$md_file" title)"
        [[ -n "$title" ]] || continue

        local normalized
        normalized="$(_skalling_normalize_title "$title")"
        [[ -n "$normalized" ]] || continue

        if [[ -z "$pairs" ]]; then
            pairs="${normalized}"$'\t'"${md_file}"
        else
            pairs+=$'\n'"${normalized}"$'\t'"${md_file}"
        fi
    done

    [[ -z "$pairs" ]] && return 0

    # Agrupar por título normalizado; emitir solo grupos con count > 1.
    # Cada grupo: paths en líneas consecutivas, seguido de línea vacía.
    printf "%s\n" "$pairs" | sort | awk -F'\t' '
        NF < 2 { next }
        {
            if ($1 == prev_key) {
                paths = paths "\n" $2
                count++
            } else {
                if (count > 1) {
                    printf "%s\n\n", paths
                }
                prev_key = $1
                paths = $2
                count = 1
            }
        }
        END {
            if (count > 1) printf "%s\n", paths
        }
    '
    return 0
}

# skalling_find_stale [context_dir] [meses]
# Imprime paths a concept docs no referenciados desde index.md Y con mtime > N meses.
skalling_find_stale() {
    local context_dir="${1:-.opencode/context}"
    local months="${2:-${SKALLING_STALE_MONTHS:-6}}"

    [[ -d "$context_dir" ]] || return 0

    local threshold_days=$((months * 30))
    local now_epoch; now_epoch="$(date +%s)"
    local stale=()
    local md_files
    md_files="$(_skalling_list_concept_files "$context_dir")"

    for md_file in $md_files; do
        local basename; basename="$(basename "$md_file" .md)"
        if _skalling_is_referenced "$context_dir" "$basename"; then
            continue
        fi

        local mtime_epoch
        mtime_epoch="$(stat -f %m "$md_file" 2>/dev/null || stat -c %Y "$md_file" 2>/dev/null || echo 0)"
        [[ "$mtime_epoch" -gt 0 ]] || continue

        local age_days=$(( (now_epoch - mtime_epoch) / 86400 ))
        [[ "$age_days" -gt "$threshold_days" ]] || continue

        stale+=("$md_file")
    done

    if [[ ${#stale[@]} -gt 0 ]]; then
        printf "%s\n" "${stale[@]}"
    fi
    return 0
}

# skalling_find_superseded [context_dir]
# Imprime paths a concept docs con `superseded: true` o `status: superseded`.
skalling_find_superseded() {
    local context_dir="${1:-.opencode/context}"
    [[ -d "$context_dir" ]] || return 0

    local md_files
    md_files="$(_skalling_list_concept_files "$context_dir")"

    local superseded=()
    for md_file in $md_files; do
        if grep -qE "^(superseded|status):[[:space:]]*(true|superseded)" "$md_file" 2>/dev/null; then
            superseded+=("$md_file")
        fi
    done

    if [[ ${#superseded[@]} -gt 0 ]]; then
        printf "%s\n" "${superseded[@]}"
    fi
    return 0
}
