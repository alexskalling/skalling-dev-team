#!/usr/bin/env bash
# Contrato de la interfaz /skalling-* — comandos cortos y scripts canónicos.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name"
    FAIL=$((FAIL + 1))
  fi
}

expected=(
  skalling-codegraph skalling-dashboard skalling-doctor skalling-help
  skalling-init skalling-memory skalling-merge skalling-metrics
  skalling-recover skalling-refresh skalling-resume skalling-status
  skalling-update skalling-goal
)

for command in "${expected[@]}"; do
  file="$ROOT/command/$command.md"
  check "$command existe" test -f "$file"
  if [ -f "$file" ]; then
    check "$command tiene frontmatter" sh -c "head -1 '$file' | grep -qx -- '---'"
    check "$command tiene descripción" grep -q '^description:' "$file"
    check "$command es compacto (< 5 KiB)" sh -c "[ \$(wc -c < '$file') -lt 5120 ]"
  fi
done

for removed in skalling-forget skalling-graph skalling-graph-refresh skalling-models; do
  check "$removed fue consolidado o desactivado" test ! -e "$ROOT/command/$removed.md"
done

check "comandos no ejecutan SQL directo" sh -c \
  "! grep -R -E 'sqlite3|DELETE FROM|INSERT INTO|UPDATE [a-z_]+ SET' '$ROOT/command'/*.md"
check "comandos no usan rutas placeholder o del checkout" sh -c \
  "! grep -R -E '<path-to>|~/skalling-dev-team|bash scripts/' '$ROOT/command'/*.md"
check "comandos resuelven raíz instalada" sh -c \
  "grep -R -l 'SKALLING_ROOT:-.*SKALLING_OPENCODE_DIR' '$ROOT/command'/*.md | grep -q ."

for command in "${expected[@]}"; do
  check "README documenta /$command" grep -q "/$command" "$ROOT/README.md"
done

check "installer copia bootstrap global" grep -q 'entrypoint in bootstrap-context.sh setup-team-doctor.sh' "$ROOT/install-global.sh"
check "installer copia doctor global" grep -q 'entrypoint in bootstrap-context.sh setup-team-doctor.sh' "$ROOT/install-global.sh"
check "installer copia lib-stack-detect" grep -q 'lib-stack-detect.sh.*scripts/lib' "$ROOT/install-global.sh"
check "dashboard tiene ayuda" grep -q -- '--help' "$ROOT/scripts/teamdb-dashboard.sh"
check "dashboard abre en Linux" grep -q 'xdg-open' "$ROOT/scripts/teamdb-dashboard.sh"
check "dashboard abre en Windows" grep -Eq 'cmd\.exe|wslview' "$ROOT/scripts/teamdb-dashboard.sh"
check "update conserva backup" sh -c "! grep -q 'install-global.sh --force' '$ROOT/scripts/update.sh'"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
