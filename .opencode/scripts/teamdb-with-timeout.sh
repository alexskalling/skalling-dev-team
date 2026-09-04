#!/usr/bin/env bash
# teamdb-with-timeout.sh — wrapper con timeout (compatible macOS/Linux)
set -euo pipefail
TIMEOUT="${1:-10}"  # default 10s
shift

# Detectar binario timeout disponible
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

if [ -z "$TIMEOUT_BIN" ]; then
  echo "WARN: timeout/gtimeout no disponible, ejecutando sin límite" >&2
  exec "$@"
fi

exec "$TIMEOUT_BIN" "$TIMEOUT" "$@"