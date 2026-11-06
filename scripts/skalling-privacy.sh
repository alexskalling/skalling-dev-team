#!/usr/bin/env bash
# Local Git exclusions for external projects; never edits shared ignore rules.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-status}"
PROJECT="${2:-$PWD}"
case "$MODE" in
  externo) MODE=external ;;
  interno) MODE=internal ;;
  verify-internal) exec python3 "$SCRIPT_DIR/skalling-privacy-check.py" "$PROJECT" ;;
  status|external|internal) ;;
  *) echo 'Uso: skalling-privacy.sh status|external|internal|verify-internal [proyecto]' >&2; exit 2 ;;
esac
exec python3 "$SCRIPT_DIR/skalling_privacy.py" "$MODE" "$PROJECT"
