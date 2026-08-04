#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND="$ROOT/command/skalling-forget.md"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }
contains() { if grep -qE "$1" "$COMMAND"; then pass "$2"; else fail "$2"; fi; }

contains 'PASO 1.*mem-review|mem-review.*primero' 'mem-review es el primer paso'
CONTENT="$(tr '\n' ' ' < "$COMMAND")"
if [[ "$CONTENT" == *'Duplicados'*'WIP zombie'*'Stale'*'Superseded'* ]]; then pass 'lista las cuatro categorías'; else fail 'lista las cuatro categorías'; fi
contains 'A\).*Archivar' 'opción A presente'
contains 'B\).*superseded' 'opción B presente'
contains 'C\).*Consolidar' 'opción C presente'
contains 'D\).*Mantener' 'opción D presente'
contains '\[YYYY-MM-DD\] forget action: A on path1\.md' 'formato de log correcto'
contains 'setup-team-doctor\.sh --strict' 'doctor post-decisión presente'
contains 'si.*doctor.*detecta|exit.*condicional|advertir' 'cierre condicional ante findings'

printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
