#!/usr/bin/env bash
# Validate before lazy initialization, then query the explicit project root.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(python3 "$SCRIPT_DIR/skalling-project-root.py" "${1:-$PWD}" --codegraph)"
if ! command -v codegraph >/dev/null 2>&1; then
    echo 'ERROR: CodeGraph no está instalado; usa lectura directa.' >&2
    exit 1
fi
if [ ! -d "$PROJECT/.codegraph" ]; then
    if [ "$(python3 "$SCRIPT_DIR/skalling_privacy.py" mode "$PROJECT")" = external ]; then
        echo 'Proyecto externo: inicialización automática de CodeGraph desactivada para preservar archivos compartidos. Usa lectura directa.' >&2
        exit 1
    fi
    if command -v gentle-ai >/dev/null 2>&1; then
        gentle-ai codegraph init --cwd "$PROJECT"
    else
        codegraph init "$PROJECT"
    fi
fi
codegraph status "$PROJECT"
