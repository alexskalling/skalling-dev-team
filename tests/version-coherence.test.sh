#!/usr/bin/env bash
# tests/version-coherence.test.sh — Validación de coherencia VERSION/schema/README (T-0.1)
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "✓ $name"
    PASS=$((PASS+1))
  else
    echo "✗ $name"
    FAIL=$((FAIL+1))
  fi
}

extract_version() {
  local file="$1"
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$file" | head -1
}

VERSION="$(extract_version "$ROOT/VERSION")"
[ -n "$VERSION" ] || { echo "VERSION no extraíble"; exit 1; }
echo "VERSION declarada: $VERSION"

assert "VERSION formato semver" "[ \"$VERSION\" = '0.7.2' ]"

PROJ_SCHEMA="$ROOT/sql/project-schema.sql"
GLOB_SCHEMA="$ROOT/sql/global-schema.sql"

PROJ_VERSION="$(extract_version "$PROJ_SCHEMA" | head -1)"
GLOB_VERSION="$(extract_version "$GLOB_SCHEMA" | head -1)"

PROJ_SCHEMA_VERSION="$(grep -oE "INSERT INTO schema_meta VALUES \('version', '[0-9.]+'\)" "$PROJ_SCHEMA" | head -1)"
GLOB_SCHEMA_VERSION="$(grep -oE "INSERT INTO schema_meta VALUES \('version', '[0-9.]+'\)" "$GLOB_SCHEMA" | head -1)"

assert "project-schema: schema_meta version coincide" \
  "echo \"$PROJ_SCHEMA_VERSION\" | grep -q \"'$VERSION'\""

assert "global-schema: schema_meta version coincide" \
  "echo \"$GLOB_SCHEMA_VERSION\" | grep -q \"'$VERSION'\""

assert "project-schema: sin lineas UPDATE schema_meta version (legacy)" \
  "! grep -E \"^UPDATE schema_meta SET value = '[0-9.]+' WHERE key = 'version'\" '$PROJ_SCHEMA'"

assert "README menciona VERSION" \
  "grep -qE \"Versi[oó]n actual:[[:space:]]*0\\.7\\.[0-9]+\" '$ROOT/README.md' || grep -q \"$VERSION\" '$ROOT/README.md'"

# Coherencia con DB real (round-trip)
TMP_DB="$(mktemp -d)/coherence.db"
sqlite3 "$TMP_DB" < "$PROJ_SCHEMA"
DB_VERSION="$(sqlite3 "$TMP_DB" "SELECT value FROM schema_meta WHERE key='version'")"
assert "DB real: schema_meta.version = VERSION" "[ \"$DB_VERSION\" = \"$VERSION\" ]"
rm -rf "$(dirname "$TMP_DB")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
