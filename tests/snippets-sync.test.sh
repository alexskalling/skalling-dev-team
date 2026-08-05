#!/usr/bin/env bash
# tests/snippets-sync.test.sh — T-3.1: agentes con markers, sin bodies duplicados (DC-2)
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1"; FAIL=$((FAIL+1)); }

AGENTS=0
for agent in "$ROOT"/agents-base/*.md; do
  [ -f "$agent" ] || continue
  base="$(basename "$agent" .md)"
  AGENTS=$((AGENTS+1))

  if grep -q "<!-- @include-snippet code-intelligence -->" "$agent"; then
    assert_pass "$base: marker code-intelligence"
  else
    assert_fail "$base: sin marker code-intelligence"
  fi

  if grep -q "<!-- @include-snippet memory-protocol -->" "$agent"; then
    assert_pass "$base: marker memory-protocol"
  else
    assert_fail "$base: sin marker memory-protocol"
  fi

  if grep -q "## 🔍 Code Intelligence" "$agent"; then
    assert_fail "$base: tiene body Code Intelligence embebido"
  else
    assert_pass "$base: sin body Code Intelligence embebido"
  fi

  if grep -q "## 🧠 Memory Protocol" "$agent"; then
    assert_fail "$base: tiene body Memory Protocol embebido"
  else
    assert_pass "$base: sin body Memory Protocol embebido"
  fi

  if grep -q "SINCRONIZADO CON" "$agent"; then
    assert_fail "$base: mantiene comment SINCRONIZADO CON"
  else
    assert_pass "$base: sin comment SINCRONIZADO CON"
  fi
done

[ "$AGENTS" -eq 8 ] || assert_fail "se esperaban 8 agentes (encontrados=$AGENTS)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
