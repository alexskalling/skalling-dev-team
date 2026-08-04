#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/lib-memory-check.sh"

TARGET="$(pwd)"
DRY_RUN=false

usage() {
    printf 'Uso: %s [--target <project_dir>] [--dry-run]\n' "$(basename "$0")"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            TARGET="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

CONTEXT_DIR="$TARGET/.opencode/context"
ZOMBIE_DAYS="${SKALLING_WIP_ZOMBIE_DAYS:-30}"
STALE_MONTHS="${SKALLING_STALE_MONTHS:-6}"

print_group() {
    local header="$1"
    local findings="$2"
    printf '=== %s ===\n' "$header"
    if [[ -n "$findings" ]]; then
        printf '%s\n' "$findings"
    fi
    printf '\n'
}

DUPLICATES="$(skalling_find_duplicates "$CONTEXT_DIR")"
ZOMBIES="$(skalling_find_zombie_wip "$CONTEXT_DIR" "$ZOMBIE_DAYS")"
STALE="$(skalling_find_stale "$CONTEXT_DIR" "$STALE_MONTHS")"
SUPERSEDED="$(skalling_find_superseded "$CONTEXT_DIR")"

print_group 'Duplicados' "$DUPLICATES"
print_group "WIP zombie (>${ZOMBIE_DAYS} días)" "$ZOMBIES"
print_group "Stale (>${STALE_MONTHS} meses sin referencia)" "$STALE"
print_group 'Superseded' "$SUPERSEDED"

exit 0
