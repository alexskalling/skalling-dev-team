#!/usr/bin/env bash
# skalling-snapshot.sh — Vuelca DB → archivos .md SOLO cuando VOS lo corrés
# Uso: skalling-snapshot [change-slug]
#   Sin args: exporta todos los changes activos
#   Con slug: exporta solo ese change

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$(pwd)}"
PLAN_FILTER="${2:-}"

if [ -n "$PLAN_FILTER" ]; then
    bash "$SCRIPT_DIR/teamdb-export-md.sh" "$PROJECT" --plan="$PLAN_FILTER"
else
    bash "$SCRIPT_DIR/teamdb-export-md.sh" "$PROJECT"
fi