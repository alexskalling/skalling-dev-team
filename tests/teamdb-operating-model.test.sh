#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

check() {
  local description="$1"
  shift
  if "$@"; then
    echo "✓ $description"
    PASS=$((PASS + 1))
  else
    echo "✗ $description" >&2
    FAIL=$((FAIL + 1))
  fi
}

for agent in Alex Jes Jhon Luz Pau Pol Sol Teo; do
  check "$agent autoriza lectura normal de TeamDB" \
    grep -q '"bash \*teamdb-read\*": allow' "$ROOT/agents-base/$agent.md"
done

check "Pau autoriza escritura tipada de memoria" \
  grep -q '"bash \*teamdb-memory\*": allow' "$ROOT/agents-base/Pau.md"

check "los prompts no enseñan INSERT mediante teamdb_query_project" \
  sh -c "! grep -R -n 'teamdb_query_project \"INSERT' '$ROOT/agents-base'"

check "los prompts no enseñan mutaciones sqlite3 directas" \
  sh -c "! grep -R -nE 'sqlite3 .*\"(INSERT|UPDATE|DELETE|DROP)' '$ROOT/agents-base'"

check "session-start prioriza automáticamente la DB del proyecto" \
  grep -q 'DB_ACTIVE="$DB_PROJECT"' "$ROOT/scripts/skalling-session-start.sh"

check "teamdb-plan instala cleanup al salir" \
  grep -q "trap 'cleanup' EXIT" "$ROOT/scripts/teamdb-plan.sh"
check "teamdb-plan cleanup elimina todos los temporales" \
  grep -q 'rm -rf "$dir"' "$ROOT/scripts/teamdb-plan.sh"

check "heal global toma la versión declarada, no la versión antigua" \
  grep -q 'target_version=' "$ROOT/scripts/lib/lib-teamdb.sh"

check "lector TeamDB instalado como script" test -x "$ROOT/scripts/teamdb-read.sh"
check "escritor de memoria instalado como script" test -x "$ROOT/scripts/teamdb-memory.sh"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
