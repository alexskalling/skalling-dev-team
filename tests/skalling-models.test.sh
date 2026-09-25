#!/usr/bin/env bash
# tests/skalling-models.test.sh — skalling-models.sh asigna un modelo de
# OpenCode a cada agente vía el campo model: del frontmatter, sin depender
# del repo (opera solo sobre agentes ya instalados + model-overrides.json,
# para que funcione también en una instalación sin el checkout del repo).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/skalling-models.sh"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap '[ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"' EXIT
export SKALLING_OPENCODE_DIR="$TMP"
mkdir -p "$TMP/agents"
for a in Alex Jes Jhon Luz Pau Pol Sol Teo; do
  cat > "$TMP/agents/$a.md" <<EOF
---
description: agente $a
mode: primary
permission:
  bash: {}
---
Cuerpo de $a.
EOF
done

OUT_INITIAL="$(bash "$SCRIPT" show)"
if [ "$(printf '%s\n' "$OUT_INITIAL" | wc -l | tr -d ' ')" = "8" ] && \
   ! grep -q 'anthropic\|openai' <<< "$OUT_INITIAL"; then
  assert_pass "show inicial: 8 agentes, todos en default de sesión"
else
  assert_fail "show inicial: 8 agentes, todos en default de sesión" "out=$OUT_INITIAL"
fi

bash "$SCRIPT" set Alex anthropic/claude-opus-5 >/dev/null
bash "$SCRIPT" set Teo anthropic/claude-haiku-4-5-20251001 >/dev/null
OUT_SET="$(bash "$SCRIPT" show)"
if grep -q '^Alex.*anthropic/claude-opus-5' <<< "$OUT_SET" && \
   grep -q '^Teo.*anthropic/claude-haiku-4-5-20251001' <<< "$OUT_SET" && \
   grep -q '^Jes.*default' <<< "$OUT_SET"; then
  assert_pass "set: agentes asignados quedan reflejados, el resto sigue en default"
else
  assert_fail "set: agentes asignados quedan reflejados, el resto sigue en default" "out=$OUT_SET"
fi

if [ "$(grep -c '^model:' "$TMP/agents/Alex.md")" = "1" ]; then
  assert_pass "frontmatter de Alex.md tiene exactamente una línea model:"
else
  assert_fail "frontmatter de Alex.md tiene exactamente una línea model:" "$(cat "$TMP/agents/Alex.md")"
fi

bash "$SCRIPT" set Alex anthropic/claude-sonnet-5 >/dev/null
if [ "$(grep -c '^model:' "$TMP/agents/Alex.md")" = "1" ] && \
   grep -q '^model: anthropic/claude-sonnet-5$' "$TMP/agents/Alex.md"; then
  assert_pass "set sobre un agente ya asignado reemplaza, no duplica la línea model:"
else
  assert_fail "set sobre un agente ya asignado reemplaza, no duplica la línea model:" "$(cat "$TMP/agents/Alex.md")"
fi

bash "$SCRIPT" reset Alex >/dev/null
if ! grep -q '^model:' "$TMP/agents/Alex.md" && grep -q '"Teo": "anthropic' "$TMP/model-overrides.json"; then
  assert_pass "reset de un agente lo quita del frontmatter y del override, deja el resto intacto"
else
  assert_fail "reset de un agente lo quita del frontmatter y del override, deja el resto intacto" \
    "$(cat "$TMP/model-overrides.json")"
fi

# apply reaplica lo que YA está en model-overrides.json sin tocar el JSON.
BEFORE_JSON="$(cat "$TMP/model-overrides.json")"
sed -i.bak '/^model:/d' "$TMP/agents/Teo.md" && rm -f "$TMP/agents/Teo.md.bak"
bash "$SCRIPT" apply >/dev/null
AFTER_JSON="$(cat "$TMP/model-overrides.json")"
if grep -q '^model: anthropic/claude-haiku-4-5-20251001$' "$TMP/agents/Teo.md" && \
   [ "$BEFORE_JSON" = "$AFTER_JSON" ]; then
  assert_pass "apply reaplica el override existente sin modificar model-overrides.json"
else
  assert_fail "apply reaplica el override existente sin modificar model-overrides.json" \
    "teo=$(cat "$TMP/agents/Teo.md")"
fi

bash "$SCRIPT" reset >/dev/null
OUT_RESET_ALL="$(bash "$SCRIPT" show)"
if ! grep -q 'anthropic' <<< "$OUT_RESET_ALL" && [ "$(cat "$TMP/model-overrides.json")" = "{}" ]; then
  assert_pass "reset sin argumento vuelve los 8 agentes al default y vacía el override"
else
  assert_fail "reset sin argumento vuelve los 8 agentes al default y vacía el override" "out=$OUT_RESET_ALL"
fi

if bash "$SCRIPT" set Foo anthropic/x >/dev/null 2>&1; then
  assert_fail "agente desconocido en set es rechazado"
else
  assert_pass "agente desconocido en set es rechazado"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$SCRIPT" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "skalling-models.sh shellcheck 0 errores"
  else
    assert_fail "skalling-models.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
