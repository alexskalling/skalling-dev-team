#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROJECT="$TMP/product"
BIN="$TMP/bin"
mkdir -p "$PROJECT/app" "$PROJECT/.open-next/assets" "$BIN"

printf '%s\n' '{"name":"product","description":"Portal de operaciones","dependencies":{"next":"15.0.0","react":"19.0.0"},"devDependencies":{"vitest":"2.0.0"},"scripts":{"test":"vitest"}}' > "$PROJECT/package.json"
printf '%s\n' ':root { --brand: #123456; --surface: #f8fafc; }' 'body { font-family: Inter, sans-serif; }' > "$PROJECT/app/globals.css"
printf '%s\n' ':root { --compiled-only: red; }' > "$PROJECT/.open-next/assets/generated.css"
printf '%s\n' '#!/usr/bin/env bash' 'target=""' 'while [ "$#" -gt 0 ]; do case "$1" in --cwd) target="$2"; shift 2 ;; *) shift ;; esac; done' 'mkdir -p "$target/.codegraph"' > "$BIN/gentle-ai"
chmod +x "$BIN/gentle-ai"

PATH="$BIN:$PATH" bash "$ROOT/bootstrap-context.sh" --target "$PROJECT" --force >/dev/null

DB="$PROJECT/.opencode/context/team.db"
YAML="$PROJECT/.opencode/project.yaml"
DESIGN="$PROJECT/.opencode/context/proyecto/design-system.md"
ABOUT="$PROJECT/.opencode/context/proyecto/que-es.md"

grep -q '^  design_system_required: true$' "$YAML"
grep -q '^  - app/$' "$YAML"
grep -q 'Portal de operaciones' "$ABOUT"
! grep -q '\[Resumen del proyecto\|\[Nombre del Proyecto\|YYYY-MM-DD' "$ABOUT"
! grep -R -q '\[Componente\|\[Framework\|YYYY-MM-DD' "$PROJECT/.opencode/context/stack"
grep -q -- '--brand: #123456' "$DESIGN"
grep -q 'Inter' "$DESIGN"
! grep -q 'compiled-only\|.open-next' "$DESIGN"
test -d "$PROJECT/.codegraph"
test "$(sqlite3 "$DB" "SELECT value FROM schema_meta WHERE key='project_readiness'")" = ready
test "$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts")" -ge 3
test "$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='design-system'")" = 1

ROUTE="$(bash "$ROOT/scripts/skalling-route.sh" classify --project "$PROJECT" --risk low --scope local --clarity clear --decision none --kind code)"
printf '%s' "$ROUTE" | grep -q '"implementation_allowed":true'

UNREADY="$TMP/unready"
mkdir -p "$UNREADY/.opencode/context"
sqlite3 "$UNREADY/.opencode/context/team.db" < "$ROOT/sql/project-schema.sql"
ROUTE="$(bash "$ROOT/scripts/skalling-route.sh" classify --project "$UNREADY" --risk low --scope local --clarity clear --decision none --kind code)"
printf '%s' "$ROUTE" | grep -q '"implementation_allowed":false'
printf '%s' "$ROUTE" | grep -q '"readiness":"missing"'

echo "PASS: bootstrap produce contexto útil y routing bloquea proyectos no listos"
