#!/usr/bin/env bash
# La TeamDB del proyecto se migra sola al iniciar sesión y después de un pull
# (auditoría 2026-09-27: tras actualizar, las bases quedaban en la versión vieja).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
check() { if eval "$2"; then echo "✓ $1"; PASS=$((PASS+1)); else echo "✗ $1" >&2; FAIL=$((FAIL+1)); fi; }
ver() { sqlite3 "$TMP/.opencode/context/team.db" "SELECT value FROM schema_meta WHERE key='version'"; }
EXPECTED="$(sed -n 's/^EXPECTED_VERSION="\(.*\)"$/\1/p' "$ROOT/scripts/teamdb-init.sh")"
LAST="$(ls "$ROOT/sql/migrations" | sort | tail -1)"; LAST="${LAST%.*}"

mkdir -p "$TMP/.opencode/context"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TMP" >/dev/null 2>&1
sqlite3 "$TMP/.opencode/context/team.db" "DELETE FROM applied_migrations WHERE name='$LAST'; UPDATE schema_meta SET value='0.0.1' WHERE key='version';"

out="$(bash "$ROOT/scripts/teamdb-ensure-current.sh" "$TMP")"
check "una base atrasada se migra a $EXPECTED" '[ "$(ver)" = "$EXPECTED" ]'
check "avisa que migró" '[[ "$out" == *"actualizada"* ]]'
check "al día: no hace nada ni imprime" '[ -z "$(bash "$ROOT/scripts/teamdb-ensure-current.sh" "$TMP")" ]'
sqlite3 "$TMP/.opencode/context/team.db" "UPDATE schema_meta SET value='99.0.0' WHERE key='version'"
bash "$ROOT/scripts/teamdb-ensure-current.sh" "$TMP"
check "una base más nueva que los scripts no se toca" '[ "$(ver)" = "99.0.0" ]'
check "sin team.db no crea nada" 'bash "$ROOT/scripts/teamdb-ensure-current.sh" "$TMP/nada" && [ ! -e "$TMP/nada" ]'
check "el inicio de sesión lo invoca" 'grep -q teamdb-ensure-current.sh "$ROOT/scripts/skalling-session-start.sh"'
check "el hook post-merge lo invoca" 'grep -q teamdb-ensure-current.sh "$ROOT/scripts/hooks/post-merge"'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
