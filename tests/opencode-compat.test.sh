#!/usr/bin/env bash
# Matriz de soporte de OpenCode (lib-os.sh) y timeout de los corredores.
# No prueba el binario real de OpenCode: solo la clasificación de versiones y
# el retiro acotado de artefactos antiguos.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local name="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then pass "$name"; else fail "$name (esperado '$want', obtenido '$got')"; fi
}

# shellcheck source=../scripts/lib/lib-os.sh
source "$ROOT/scripts/lib/lib-os.sh"
# shellcheck source=lib/with-timeout.sh
source "$ROOT/tests/lib/with-timeout.sh"

# Solo la serie 2, desde el mínimo verificado.
for version in 0.9.9 1.18.29 1.99.99 2.0.18 2.0.20 3.0.0; do
  assert_eq "$version no soportada" unsupported "$(skalling_opencode_support "$version")"
done
for version in 2.0.21 2.0.22 2.1.0; do
  assert_eq "$version soportada" v2 "$(skalling_opencode_support "opencode v$version")"
done
assert_eq "salida vacía es unknown" unknown "$(skalling_opencode_support "")"
assert_eq "salida ilegible es unknown" unknown "$(skalling_opencode_support "Error: EACCES log")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/plugins" "$tmp/scripts" "$tmp/command"
for file in plugins/skalling-goal.js scripts/skalling-goal.sh scripts/skalling-goal.py command/skalling-goal.md; do
  printf old > "$tmp/$file"
done
printf custom > "$tmp/plugins/custom.js"
printf memory > "$tmp/team.db"
run() { "$@"; }
skalling_remove_retired_artifacts "$tmp"
assert_eq "no quedan artefactos retirados" 0 "$(find "$tmp" -name 'skalling-goal*' | wc -l | tr -d ' ')"
assert_eq "conserva plugins ajenos" custom "$(cat "$tmp/plugins/custom.js")"
assert_eq "conserva memoria" memory "$(cat "$tmp/team.db")"

# ── Timeout portable ──
skalling_with_timeout 5 bash -c 'exit 7'
assert_eq "timeout propaga el código de salida" 7 "$?"
skalling_with_timeout 1 bash -c 'sleep 20' 2>/dev/null
assert_eq "timeout vencido sale con 124" 124 "$?"

printf '\nResults: %s passed, %s failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
