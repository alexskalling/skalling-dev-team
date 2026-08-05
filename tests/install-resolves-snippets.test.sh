#!/usr/bin/env bash
# tests/install-resolves-snippets.test.sh — Los snippets se resuelven build-time (T-3.2)
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() {
  local name="$1"
  echo "✓ $name"
  PASS=$((PASS+1))
}

assert_fail() {
  local name="$1"
  local detail="${2:-}"
  echo "✗ $name${detail:+ — $detail}"
  FAIL=$((FAIL+1))
}

# HOME aislado para correr el install real
HOME_BAK="$HOME"
FAKE_HOME="$(mktemp -d)"
export HOME="$FAKE_HOME"

OUT="$(bash "$ROOT/install-global.sh" 2>&1)"
RC=$?
export HOME="$HOME_BAK"

if [ "$RC" -eq 0 ]; then
  assert_pass "install-global.sh (real) retorna exit 0"
else
  assert_fail "install-global.sh (real) retorna exit 0" "rc=$RC out=$OUT"
fi

AGENTS_DIR="$FAKE_HOME/.config/opencode/agents"

# Debe instalar 8 agentes
COUNT="$(ls -1 "$AGENTS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "$COUNT" -eq 8 ]; then
  assert_pass "instala 8 agentes"
else
  assert_fail "instala 8 agentes" "hay $COUNT"
fi

for agent in "$AGENTS_DIR"/*.md; do
  base="$(basename "$agent" .md)"
  if grep -q "codebase-memory-mcp" "$agent"; then
    assert_pass "$base tiene snippet code-intelligence resuelto"
  else
    assert_fail "$base tiene snippet code-intelligence resuelto" "no aparece codebase-memory-mcp"
  fi

  if grep -q "Memory Protocol" "$agent"; then
    assert_pass "$base tiene snippet memory-protocol resuelto"
  else
    assert_fail "$base tiene snippet memory-protocol resuelto" "no aparece 'Memory Protocol'"
  fi

  if grep -q "@include-snippet" "$agent"; then
    assert_fail "$base no deja markers sin resolver" "quedó '@include-snippet'"
  else
    assert_pass "$base no deja markers sin resolver"
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
