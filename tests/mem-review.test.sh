#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/mem-review.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }
assert_contains() { if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3"; fi; }

mkdir -p "$FIXTURE/.opencode/context/decisiones" "$FIXTURE/.opencode/context/trabajo-en-curso"
printf '%s\n' '- [a](a.md)' '- [b](b.md)' > "$FIXTURE/.opencode/context/decisiones/index.md"
printf '%s\n' '---' 'title: Repetido' 'timestamp: 2026-07-01T00:00:00Z' '---' > "$FIXTURE/.opencode/context/decisiones/a.md"
printf '%s\n' '---' 'title: repetido' 'timestamp: 2026-07-01T00:00:00Z' '---' > "$FIXTURE/.opencode/context/decisiones/b.md"
printf '%s\n' '---' 'title: Zombie' 'timestamp: 2020-01-01T00:00:00Z' '---' '- [x] listo' > "$FIXTURE/.opencode/context/trabajo-en-curso/zombie.md"
printf '%s\n' '---' 'title: Stale' 'timestamp: 2020-01-01T00:00:00Z' '---' > "$FIXTURE/.opencode/context/decisiones/stale.md"
touch -t 202001010000 "$FIXTURE/.opencode/context/decisiones/stale.md"
printf '%s\n' '---' 'title: Viejo' 'superseded: true' 'superseded_by: nuevo.md' '---' > "$FIXTURE/.opencode/context/decisiones/old.md"

if [[ -x "$SCRIPT" ]]; then pass 'mem-review es ejecutable'; else fail 'mem-review es ejecutable'; fi
if bash -n "$SCRIPT" 2>/dev/null; then pass 'sintaxis válida'; else fail 'sintaxis válida'; fi
OUTPUT="$(bash "$SCRIPT" --target "$FIXTURE")"
assert_contains "$OUTPUT" '=== Duplicados ===' 'header duplicados'
assert_contains "$OUTPUT" 'a.md' 'detecta primer duplicado'
assert_contains "$OUTPUT" 'b.md' 'detecta segundo duplicado'
assert_contains "$OUTPUT" '=== WIP zombie (>30 días) ===' 'header zombie'
assert_contains "$OUTPUT" 'zombie.md' 'detecta zombie'
assert_contains "$OUTPUT" '=== Stale (>6 meses sin referencia) ===' 'header stale'
assert_contains "$OUTPUT" 'stale.md' 'detecta stale huérfano'
assert_contains "$OUTPUT" '=== Superseded ===' 'header superseded'
assert_contains "$OUTPUT" 'old.md' 'detecta superseded'
ORDER="$(printf '%s\n' "$OUTPUT" | grep '^===' | tr '\n' '|')"
if [[ "$ORDER" == '=== Duplicados ===|=== WIP zombie (>30 días) ===|=== Stale (>6 meses sin referencia) ===|=== Superseded ===|' ]]; then pass 'orden fijo'; else fail 'orden fijo'; fi
EMPTY="$(bash "$SCRIPT" --target "$(mktemp -d)")"
if [[ "$(printf '%s\n' "$EMPTY" | grep -c '^===')" -eq 4 ]]; then pass 'bundle vacío muestra cuatro headers'; else fail 'bundle vacío muestra cuatro headers'; fi

printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
