#!/usr/bin/env bash
# tests/portability-bash32.test.sh — Validación bash 3.2 portable (T-2.7)
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

# 1. BASH_VERSINFO[0] >= 3 (todos los bash 3.2+ lo cumplen)
if [ "${BASH_VERSINFO[0]}" -ge 3 ]; then
  assert_pass "BASH_VERSINFO[0] >= 3 (=$BASH_VERSION)"
else
  assert_fail "BASH_VERSINFO[0] >= 3" "=$BASH_VERSION"
fi

# 2. Sin declare -A (asociative arrays son bash 4+)
for f in scripts/teamdb-*.sh scripts/hooks/*; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if grep -E '^[[:space:]]*declare -A' "$f" >/dev/null 2>&1; then
      assert_fail "sin declare -A en $(basename "$f")"
    fi
  fi
done
assert_pass "sin declare -A (asociative arrays bash 4+)"

# 3. Sin readarray/mapfile (bash 4+)
for f in scripts/teamdb-*.sh scripts/hooks/*; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if grep -E 'readarray|mapfile' "$f" >/dev/null 2>&1; then
      assert_fail "sin readarray/mapfile en $(basename "$f")"
    fi
  fi
done
assert_pass "sin readarray/mapfile (bash 4+)"

# 4. Sin ${var,,} ${var^^} (case modification bash 4+)
for f in scripts/teamdb-*.sh scripts/hooks/* scripts/lib/*.sh; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if grep -E '\$\{[a-zA-Z_]+,,?\}|\$\{[a-zA-Z_]+\^\^?\}' "$f" >/dev/null 2>&1; then
      assert_fail "sin \${var,,} \${var^^} en $(basename "$f")"
    fi
  fi
done
assert_pass 'sin ${var,,} ${var^^} (bash 4+)'

# 5. Sin [[ -v ]] (bash 4+)
for f in scripts/teamdb-*.sh scripts/hooks/* scripts/lib/*.sh; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if grep -E '\[\[ -v [a-zA-Z_]' "$f" >/dev/null 2>&1; then
      assert_fail "sin [[ -v ]] en $(basename "$f")"
    fi
  fi
done
assert_pass "sin [[ -v ]] (bash 4+)"

# 6. Sin local -n (namerefs bash 4+)
for f in scripts/teamdb-*.sh scripts/hooks/* scripts/lib/*.sh; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if grep -E 'local -n' "$f" >/dev/null 2>&1; then
      assert_fail "sin local -n en $(basename "$f")"
    fi
  fi
done
assert_pass "sin local -n (namerefs bash 4+)"

# 7. shellcheck 0 errores en todos los tocados
FILES_OK=0
FILES_FAIL=0
for f in scripts/lib/lib-teamdb.sh scripts/teamdb-*.sh scripts/hooks/*; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if shellcheck "$f" >/dev/null 2>&1; then
      FILES_OK=$((FILES_OK + 1))
    else
      FILES_FAIL=$((FILES_FAIL + 1))
      assert_fail "shellcheck OK: $f"
    fi
  fi
done
if [ "$FILES_FAIL" = "0" ]; then
  assert_pass "shellcheck 0 errores en $FILES_OK archivos tocados"
fi

# 8. bash -n todos
for f in scripts/lib/lib-teamdb.sh scripts/teamdb-*.sh scripts/hooks/*; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if ! bash -n "$f" >/dev/null 2>&1; then
      assert_fail "bash -n: $f"
    fi
  fi
done
assert_pass "bash -n 0 errores en todos los scripts"

# 9. Python AST parsea teamdb_exec.py
if python3 -c "import ast; ast.parse(open('$ROOT/scripts/teamdb_exec.py').read())" 2>/dev/null; then
  assert_pass "teamdb_exec.py parsea como AST"
else
  assert_fail "teamdb_exec.py parsea como AST"
fi

# 10. Patrones comunes incompatibles con bash 3.2
BASH32_PATTERNS='(BASH_XTRACEFD|\\$\\([^)]*\\<\\>\\))'
for f in scripts/teamdb-*.sh scripts/lib/*.sh; do
  if [ -f "$f" ] && [[ "$f" != *.md ]]; then
    if grep -E "$BASH32_PATTERNS" "$f" >/dev/null 2>&1; then
      assert_fail "sin patrones bash 4+ en $(basename "$f")"
    fi
  fi
done
assert_pass "sin patrones bash 4+ raros"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
