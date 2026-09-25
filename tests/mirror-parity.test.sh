#!/usr/bin/env bash
# tests/mirror-parity.test.sh — este repo mantiene VARIOS mecanismos de
# "espejo" de archivos (fuente -> copia local en .opencode/), y no todos
# tenían un test vigilándolos:
#   - scripts/.bundle-manifest -> .opencode/scripts/   (ya cubierto por
#     tests/scripts-parity.test.sh, no se duplica acá)
#   - agents-base/*.md -> .opencode/agents/*.md         (render-agent.sh)
#   - scripts/hooks/*  -> .opencode/hooks/*             (copia cruda, sin
#     ningún script que la aplique -- a mano)
# Encontrado en vivo: scripts/hooks/git-gate.py se editó (fail-closed) y
# .opencode/hooks/git-gate.py quedó con la versión vieja durante toda una
# sesión sin que nada lo señalara. Este test cierra exactamente ese hueco
# para los dos mecanismos que no tenían cobertura.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

# ── agents-base/*.md -> .opencode/agents/*.md ──
for src in "$ROOT"/agents-base/*.md; do
  [ -f "$src" ] || continue
  name="$(basename "$src")"
  mirror="$ROOT/.opencode/agents/$name"
  if [ ! -f "$mirror" ]; then
    assert_fail "$name: espejo en .opencode/agents/ existe" "falta $mirror"
    continue
  fi
  rendered="$(bash "$ROOT/scripts/render-agent.sh" "$src")"
  if [ "$rendered" = "$(cat "$mirror")" ]; then
    assert_pass "$name: .opencode/agents/$name coincide con el render de agents-base/$name"
  else
    assert_fail "$name: .opencode/agents/$name coincide con el render de agents-base/$name" \
      "difieren -- correr: diff <(bash scripts/render-agent.sh agents-base/$name) .opencode/agents/$name"
  fi
done

# ── scripts/hooks/* -> .opencode/hooks/* (copia cruda, sin render) ──
for src in "$ROOT"/scripts/hooks/*; do
  [ -f "$src" ] || continue
  name="$(basename "$src")"
  mirror="$ROOT/.opencode/hooks/$name"
  if [ ! -f "$mirror" ]; then
    assert_fail "$name: espejo en .opencode/hooks/ existe" "falta $mirror"
    continue
  fi
  if diff -q "$src" "$mirror" >/dev/null 2>&1; then
    assert_pass "$name: .opencode/hooks/$name es copia exacta de scripts/hooks/$name"
  else
    assert_fail "$name: .opencode/hooks/$name es copia exacta de scripts/hooks/$name" \
      "difieren -- correr: diff scripts/hooks/$name .opencode/hooks/$name"
  fi
done

# ── huérfanos: un archivo que quedó en el espejo después de borrarse en la
#    fuente no lo detecta el loop de arriba (solo recorre fuente -> espejo).
ORPHANS=""
for mirror in "$ROOT"/.opencode/agents/*.md; do
  [ -f "$mirror" ] || continue
  name="$(basename "$mirror")"
  [ -f "$ROOT/agents-base/$name" ] || ORPHANS="$ORPHANS .opencode/agents/$name"
done
for mirror in "$ROOT"/.opencode/hooks/*; do
  [ -f "$mirror" ] || continue
  name="$(basename "$mirror")"
  [ -f "$ROOT/scripts/hooks/$name" ] || ORPHANS="$ORPHANS .opencode/hooks/$name"
done
if [ -z "$ORPHANS" ]; then
  assert_pass "sin huérfanos en .opencode/agents/ ni .opencode/hooks/"
else
  assert_fail "sin huérfanos en .opencode/agents/ ni .opencode/hooks/" "huérfanos:$ORPHANS"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
