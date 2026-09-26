#!/usr/bin/env bash
# tests/doctor-stale-agents-md.test.sh — el doctor avisa cuando el proyecto
# tiene un AGENTS.md de una versión vieja de Skalling con el "fast-track" que
# le permitía a Alex saltarse a Teo y a Jhon; no avisa por un AGENTS.md propio.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap '[ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"' EXIT

mkdir -p "$TMP/viejo/.opencode" "$TMP/propio/.opencode"
cat > "$TMP/viejo/AGENTS.md" <<'MD'
### Fast-track (sin Pol ni Sol)
En estos casos voy directo a **Teo** y lo notifico: "Fast-track activo. No hay plan de Sol, ejecuta bajo tu criterio."
MD
printf '# Convenciones\nUsamos pnpm y tests con vitest.\n' > "$TMP/propio/AGENTS.md"

OUT="$(bash "$ROOT/setup-team-doctor.sh" --project "$TMP/viejo" 2>&1 || true)"
if grep -q "AGENTS.md trae reglas viejas" <<< "$OUT"; then
  assert_pass "avisa por el fast-track viejo"
else
  assert_fail "avisa por el fast-track viejo"
fi

OUT="$(bash "$ROOT/setup-team-doctor.sh" --project "$TMP/propio" 2>&1 || true)"
if ! grep -q "AGENTS.md trae reglas viejas" <<< "$OUT"; then
  assert_pass "no avisa por un AGENTS.md propio del proyecto"
else
  assert_fail "no avisa por un AGENTS.md propio del proyecto"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
