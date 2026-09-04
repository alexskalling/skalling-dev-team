#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS=(Alex Pol Jes Sol Teo Jhon Luz Pau)
PASS=0
FAIL=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name" >&2
    FAIL=$((FAIL + 1))
  fi
}

check "renderer canónico existe" test -x "$ROOT/scripts/render-agent.sh"
check "instalación global usa renderer canónico" grep -q 'scripts/render-agent.sh' "$ROOT/install-global.sh"
check "instalación por proyecto usa renderer canónico" grep -q 'scripts/render-agent.sh' "$ROOT/setup.sh"

for agent in "${AGENTS[@]}"; do
  file="$ROOT/agents-base/$agent.md"
  check "$agent conserva frontmatter" sh -c "[ \"\$(head -1 '$file')\" = '---' ]"
  check "$agent no tiene permission mal indentado" sh -c "! grep -q '^  permission:' '$file'"
  check "$agent usa lector seguro" grep -q 'teamdb-read.sh' "$file"
done

check "Jhon protege description con dos puntos" \
  grep -q '^description: "[^"]*:.*"$' "$ROOT/agents-base/Jhon.md"

check "ningún agente enseña helper antiguo" \
  sh -c "! grep -R -n 'teamdb_query_project' '$ROOT/agents-base'"
check "ningún agente enseña sqlite3 directo" \
  sh -c "! grep -R -n 'sqlite3' '$ROOT/agents-base' | grep -v '\"sqlite3 \\*\": deny'"
check "ningún agente enseña borrar TeamDB" \
  sh -c "! grep -R -nE 'rm .*team\.db|git checkout --union' '$ROOT/agents-base' | grep -v '\"rm \\*team.db\\*\": deny'"

check "Pol es read-only y Sol persiste" \
  sh -c "grep -q 'Pol no persiste' '$ROOT/agents-base/Pol.md' && grep -q 'Sol persiste' '$ROOT/agents-base/Sol.md'"
check "Jes consulta DB solo cuando aplica al proyecto" \
  grep -q 'solo si la pregunta depende del proyecto' "$ROOT/agents-base/Jes.md"
check "Teo limita comandos peligrosos" \
  sh -c "grep -q '\"rm \*team.db\*\": deny' '$ROOT/agents-base/Teo.md' && grep -q '\"sqlite3 \*\": deny' '$ROOT/agents-base/Teo.md'"
check "Jhon resuelve contradicción de regresión" \
  grep -q 'Suite completa únicamente' "$ROOT/agents-base/Jhon.md"
check "Luz clasifica severidad" \
  grep -q 'Crítico.*Alto.*Medio.*Bajo' "$ROOT/agents-base/Luz.md"
check "Pau acepta cierre proporcional" \
  grep -q 'evidencia exigida por la ruta' "$ROOT/agents-base/Pau.md"

if [ -x "$ROOT/scripts/render-agent.sh" ]; then
  rendered_dir="$(mktemp -d)"
  trap 'rm -rf "$rendered_dir"' EXIT
  total=0
  for agent in "${AGENTS[@]}"; do
    bash "$ROOT/scripts/render-agent.sh" "$ROOT/agents-base/$agent.md" > "$rendered_dir/$agent.md"
    check "$agent renderizado no conserva markers" sh -c "! grep -q '@include-snippet' '$rendered_dir/$agent.md'"
    check "$agent renderizado no conserva bloque legacy" sh -c "! grep -q 'LEGACY-SNIPPET-COPY' '$rendered_dir/$agent.md'"
    bytes="$(wc -c < "$rendered_dir/$agent.md" | tr -d ' ')"
    total=$((total + bytes))
    check "$agent renderizado no supera 14 KB" test "$bytes" -le 14336
  done
  check "prompts renderizados no superan 72 KB" test "$total" -le 73728
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
