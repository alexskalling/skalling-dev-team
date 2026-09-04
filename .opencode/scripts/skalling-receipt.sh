#!/usr/bin/env bash
# skalling-receipt.sh — Emite un receipt inmutable
#
# Uso:
#   bash skalling-receipt.sh ROUTE TASK VERDICT [ARTIFACT]
#
# Ejemplo:
#   bash skalling-receipt.sh INLINE fix-typo OK src/foo.ts
#
# El receipt es JSON inmutable. Si algo cambia, se emite uno nuevo.

set -euo pipefail

ROUTE="${1:?Falta ROUTE}"
TASK="${2:?Falta TASK}"
VERDICT="${3:-OK}"
ARTIFACT="${4:-}"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RECEIPT_ID="${ROUTE}-${STAMP}"

SLUG="${SKALLING_ACTIVE_CYCLE_SLUG:-no-slug}"
RECEIPTS_DIR=".opencode/changes/${SLUG}/receipts"

mkdir -p "$RECEIPTS_DIR"
RECEIPT_FILE="${RECEIPTS_DIR}/receipt_${TASK}_${STAMP}.json"

# Escape básico para JSON (suficiente para metadatos; no es JSON-parser-grade)
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

cat > "$RECEIPT_FILE" <<EOF
{
  "receipt_id": "$(esc "$RECEIPT_ID")",
  "ts": "$TS",
  "route": "$(esc "$ROUTE")",
  "task": "$(esc "$TASK")",
  "verdict": "$(esc "$VERDICT")",
  "artifact": "$(esc "$ARTIFACT")"
}
EOF

printf 'Receipt emitido: %s\n' "$RECEIPT_FILE"