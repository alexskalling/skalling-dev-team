#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/setup-team-doctor.sh"
FIXTURE="$(mktemp -d)"
GLOBAL="$(mktemp -d)"
trap 'rm -rf "$FIXTURE" "$GLOBAL"' EXIT
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }
assert_output() { if [[ "$OUTPUT" == *"$1"* ]]; then pass "$2"; else fail "$2"; fi; }

mkdir -p "$FIXTURE/.opencode/context/decisiones" "$FIXTURE/.opencode/context/trabajo-en-curso" "$GLOBAL/agents" "$GLOBAL/skills" "$GLOBAL/command" "$GLOBAL/templates" "$GLOBAL/skalling-data"
printf '%s\n' '- [a](a.md)' '- [b](b.md)' '- [super](super.md)' > "$FIXTURE/.opencode/context/decisiones/index.md"
printf '%s\n' '---' 'title: Duplicado' '---' > "$FIXTURE/.opencode/context/decisiones/a.md"
printf '%s\n' '---' 'title: duplicado' '---' > "$FIXTURE/.opencode/context/decisiones/b.md"
printf '%s\n' '---' 'title: Huérfano' '---' > "$FIXTURE/.opencode/context/decisiones/orphan.md"
printf '%s\n' '---' 'title: Stale' '---' > "$FIXTURE/.opencode/context/decisiones/stale.md"
touch -t 202001010000 "$FIXTURE/.opencode/context/decisiones/stale.md"
printf '%s\n' '---' 'title: Super' 'superseded: true' '---' > "$FIXTURE/.opencode/context/decisiones/super.md"
printf '%s\n' '---' 'title: Zombie' 'timestamp: 2020-01-01T00:00:00Z' '---' '- [x] hecho' > "$FIXTURE/.opencode/context/trabajo-en-curso/zombie.md"

set +e
OUTPUT="$(SKALLING_OPENCODE_DIR="$GLOBAL" bash "$DOCTOR" --strict --project "$FIXTURE" 2>&1)"
STATUS=$?
set -e
assert_output 'Memoria (bundle OKF)' 'header memoria'
assert_output 'Concept doc huérfano' 'detecta huérfanos'
assert_output 'Trabajo-en-curso zombie' 'detecta zombie'
assert_output 'Duplicado obvio por title' 'detecta duplicados'
assert_output 'Concept doc stale' 'detecta stale'
assert_output 'superseded pero vigente en index.md' 'detecta superseded vigente'
assert_output 'Sin log.md' 'chequea log ausente'
if [[ "$STATUS" -eq 1 ]]; then pass '--strict retorna 1'; else fail '--strict retorna 1'; fi
if [[ "$(grep -c 'check_memory_health' "$DOCTOR")" -eq 2 ]]; then pass 'definición e invocación únicas'; else fail 'definición e invocación únicas'; fi

printf 'RESULT: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
