#!/usr/bin/env bash
# build-schema.sh — Estampa la fila schema_meta.version desde VERSION (idempotente)
#
# Decisión AD-4 corregida: solo estampa la línea de versión en sql/*.sql.
# NO regenera el resto del schema. NO toca triggers, tablas cycle, ni nada del cuerpo.
#
# Uso:
#   bash scripts/build-schema.sh         # estampa version desde VERSION
#   bash scripts/build-schema.sh --check # exit 1 si drift entre VERSION y schemas
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

VERSION_FILE="$ROOT/VERSION"
TARGETS=(
  "$ROOT/sql/project-schema.sql"
  "$ROOT/sql/global-schema.sql"
)

extract_version() {
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$1" | head -1
}

VERSION="$(extract_version "$VERSION_FILE")"
[ -n "$VERSION" ] || { echo "[ERROR] No se pudo extraer version de $VERSION_FILE" >&2; exit 1; }

stamp_file() {
  local file="$1"
  [ -f "$file" ] || { echo "[WARN] no existe: $file, skip" >&2; return 0; }

  local current
  current="$(grep -E "^INSERT INTO schema_meta VALUES \('version', '[0-9.]+'\);" "$file" | head -1 || true)"
  local expected="INSERT INTO schema_meta VALUES ('version', '$VERSION');"

  if [ "$current" = "$expected" ]; then
    return 0
  fi

  if [ -z "$current" ]; then
    echo "[ERROR] No se encontro linea INSERT INTO schema_meta ('version', ...) en $file" >&2
    return 1
  fi

  tmp="$(mktemp)"
  awk -v old="$current" -v new="$expected" '
    {
      if (index($0, old) > 0) { print new; next }
      print
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"

  echo "[OK] $file: version estampada -> $VERSION"
}

case "${1:-}" in
  --check)
    DRIFT=0
    for f in "${TARGETS[@]}"; do
      [ -f "$f" ] || continue
      line="$(grep -E "^INSERT INTO schema_meta VALUES \('version', '[0-9.]+'\);" "$f" | head -1 || true)"
      expected="INSERT INTO schema_meta VALUES ('version', '$VERSION');"
      if [ "$line" != "$expected" ]; then
        echo "[DRIFT] $f: linea actual: $line"
        echo "        esperada:       $expected"
        DRIFT=1
      fi
    done
    exit "$DRIFT"
    ;;
  --help|-h)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "")
    for f in "${TARGETS[@]}"; do
      stamp_file "$f"
    done
    echo "[OK] build-schema completo: $VERSION"
    ;;
  *)
    echo "[ERROR] argumento desconocido: $1" >&2
    exit 1
    ;;
esac
