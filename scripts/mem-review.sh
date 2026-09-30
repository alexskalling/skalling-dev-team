#!/usr/bin/env bash
# mem-review.sh siempre es de solo lectura (busca duplicados/zombies/stale/
# superseded, nunca escribe). --dry-run no cambia nada: se acepta solo por
# simetría con el resto de subcomandos de /skalling-memory (refresh sí tiene
# un modo real no-dry-run).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then source "$SCRIPT_DIR/lib-teamdb.sh"; else source "$SCRIPT_DIR/lib/lib-teamdb.sh"; fi

TARGET="$(pwd)"

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
            # No-op: este comando nunca escribe. Ver comentario de cabecera.
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

DB="$(teamdb_project_path "$TARGET")"
[ -f "$DB" ] || { echo "ERROR: falta TeamDB; revisión no realizada" >&2; exit 1; }
exec python3 "$SCRIPT_DIR/skalling-memory-review.py" "$DB"
