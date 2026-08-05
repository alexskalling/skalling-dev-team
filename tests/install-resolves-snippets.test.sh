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

# ─────────────────────────────────────────────────────────────────────────────
# H1 (Luz): resolve_snippets no debe colgarse con marker faltante ni ciclos.
# Se extrae la función real de install-global.sh y se prueba en aislamiento.
# ─────────────────────────────────────────────────────────────────────────────
UNIT="$(mktemp -d)"
mkdir -p "$UNIT/templates/agents/snippets"
echo "body ok" > "$UNIT/templates/agents/snippets/ci.md"
echo "<!-- @include-snippet self -->" > "$UNIT/templates/agents/snippets/self.md"

cat > "$UNIT/agent.md" <<'MDEOF'
<!-- @include-snippet ci -->
<!-- @include-snippet no-existe -->
MDEOF

cat > "$UNIT/agent-self.md" <<'MDEOF'
<!-- @include-snippet self -->
MDEOF

cat > "$UNIT/t.sh" <<EOF
SCRIPT_DIR="$UNIT"
log() { return 0; }
$(awk '/^resolve_snippets\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$ROOT/install-global.sh")

# Caso 1: marker faltante se elimina y no cuelga
out="\$(resolve_snippets "$UNIT/agent.md")" || { echo "resolve no-terminó"; exit 1; }
grep -q "body ok" <<< "\$out" || { echo "snippet no resuelto"; exit 1; }
grep -q "@include-snippet" <<< "\$out" && { echo "marker no eliminado"; exit 1; } || true

# Caso 2: auto-inclusión aborta con error (no infinito)
resolve_snippets "$UNIT/agent-self.md" >/dev/null 2>&1
[ "\$?" -ne 0 ] || { echo "ciclo no abortó"; exit 1; }
EOF

if bash "$UNIT/t.sh"; then
  assert_pass "resolve_snippets: marker faltante se elimina y no cuelga"
  assert_pass "resolve_snippets: ciclo aborta con error"
else
  assert_fail "resolve_snippets: no-terminación controlada" "unit test falló"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
