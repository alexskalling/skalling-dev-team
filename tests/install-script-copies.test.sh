#!/usr/bin/env bash
# tests/install-script-copies.test.sh — Validación de install-global --dry-run (T-1.5)
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

# HOME aislado
FAKE_HOME="$(mktemp -d)"
export HOME="$FAKE_HOME"
mkdir -p "$HOME/.config"

OUT="$(bash "$ROOT/install-global.sh" --dry-run 2>&1)"
RC=$?
export HOME="$HOME_BAK"

if [ "$RC" -eq 0 ]; then
  assert_pass "install-global --dry-run retorna exit 0"
else
  assert_fail "install-global --dry-run retorna exit 0" "rc=$RC out=$OUT"
fi

# Debe mencionar CADA script teamdb-* del repo
for s in teamdb-init teamdb-migrate teamdb-export teamdb-import \
         teamdb-search teamdb-related teamdb-graph \
         teamdb-plan teamdb-status teamdb-amend teamdb-resume \
         teamdb-execute-plan wip-tree; do
  if echo "$OUT" | grep -q "$s.sh"; then
    assert_pass "dry-run menciona $s.sh"
  else
    assert_fail "dry-run menciona $s.sh" "no aparece"
  fi
done

# Debe mencionar lib-teamdb.sh
if echo "$OUT" | grep -q "lib-teamdb.sh"; then
  assert_pass "dry-run menciona lib-teamdb.sh"
else
  assert_fail "dry-run menciona lib-teamdb.sh" "no aparece"
fi

# Hooks
if echo "$OUT" | grep -qE "hooks/(pre-commit|post-merge)"; then
  assert_pass "dry-run menciona hooks/pre-commit o hooks/post-merge"
else
  assert_fail "dry-run menciona hooks/pre-commit o hooks/post-merge" "no aparece"
fi

# Verificar que NO hay `|| true` silenciador cerca de hooks
if grep -nE "hooks/.*2>/dev/null \|\| true" "$ROOT/install-global.sh" >/dev/null 2>&1; then
  assert_fail "NO hay || true silenciador en sección hooks"
else
  assert_pass "NO hay || true silenciador en sección hooks"
fi

# Verificar que install_teamdb_hooks hace chmod +x sobre los hooks copiados
if grep -nE 'chmod \+x[[:space:]]+"\$\{?hook' "$ROOT/install-global.sh" >/dev/null 2>&1 \
   || grep -nE "chmod \\+x[[:space:]]+\"\\\$hook" "$ROOT/install-global.sh" >/dev/null 2>&1; then
  assert_pass "install_teamdb_hooks hace chmod +x sobre hooks"
else
  assert_fail "install_teamdb_hooks hace chmod +x sobre hooks" "no aparece"
fi

# Verificar que los hooks actuales NO usan SCRIPT_DIR/.. (paths fragiles) — T-1.6 lo arregla.
# Skipped: este assert es de T-1.6, no T-1.5.

rm -rf "$FAKE_HOME"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
