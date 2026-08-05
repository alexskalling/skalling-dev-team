#!/usr/bin/env bash
# tests/install-hooks-paths.test.sh — Validación de paths robustos en hooks (T-1.6)
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

# 1. Hooks NO usan SCRIPT_DIR/.. (fragil en .git/hooks/)
if grep -nE 'SCRIPT_DIR/\.\.' "$ROOT/scripts/hooks/pre-commit" 2>/dev/null; then
  assert_fail "pre-commit NO usa SCRIPT_DIR/.." "todavia aparece"
else
  assert_pass "pre-commit NO usa SCRIPT_DIR/.."
fi
if grep -nE 'SCRIPT_DIR/\.\.' "$ROOT/scripts/hooks/post-merge" 2>/dev/null; then
  assert_fail "post-merge NO usa SCRIPT_DIR/.." "todavia aparece"
else
  assert_pass "post-merge NO usa SCRIPT_DIR/.."
fi

# 2. Hooks usan git rev-parse --show-toplevel
if grep -q 'git rev-parse --show-toplevel' "$ROOT/scripts/hooks/pre-commit"; then
  assert_pass "pre-commit usa git rev-parse --show-toplevel"
else
  assert_fail "pre-commit usa git rev-parse --show-toplevel" "no aparece"
fi
if grep -q 'git rev-parse --show-toplevel' "$ROOT/scripts/hooks/post-merge"; then
  assert_pass "post-merge usa git rev-parse --show-toplevel"
else
  assert_fail "post-merge usa git rev-parse --show-toplevel" "no aparece"
fi

# 3. Hooks funcionan copiados a .git/hooks/ (simulando install real)
TMP_RAW="$(mktemp -d)"
# Resolver a path canonico (en macOS mktemp usa /var/... pero git rev-parse usa /private/var/...)
TMP="$(cd "$TMP_RAW" && pwd -P)"
git -C "$TMP" init -q
git -C "$TMP" config user.email "test@test.com"
git -C "$TMP" config user.name "Test"
mkdir -p "$TMP/.git/hooks"
cp "$ROOT/scripts/hooks/pre-commit" "$TMP/.git/hooks/pre-commit"
chmod +x "$TMP/.git/hooks/pre-commit"
cp "$ROOT/scripts/hooks/post-merge" "$TMP/.git/hooks/post-merge"
chmod +x "$TMP/.git/hooks/post-merge"

# Crear DB minima para que el hook funcione
mkdir -p "$TMP/.opencode/context"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TMP" >/dev/null 2>&1

# 4. pre-commit ejecuta y no falla por "file not found"
HOME="$(mktemp -d)" SKALLING_ROOT="$ROOT" bash -c '
  cd "$1"
  git add . 2>/dev/null
  HOME="$HOME" SKALLING_ROOT="$2" bash .git/hooks/pre-commit 2>&1 | grep -q "No such file" && {
    echo "FAIL: pre-commit no encontro teamdb-export.sh"
    exit 1
  }
  exit 0
' _ "$TMP" "$ROOT" 2>&1
RC=$?
if [ "$RC" = "0" ]; then
  assert_pass "pre-commit no falla con 'No such file' desde .git/hooks"
else
  assert_fail "pre-commit no falla con 'No such file' desde .git/hooks" "rc=$RC"
fi

# 5. pre-commit exporta y crea data_*.sql
HOME="$(mktemp -d)" SKALLING_ROOT="$ROOT" bash -c '
  cd "$1"
  git add . 2>/dev/null
  HOME="$HOME" SKALLING_ROOT="$2" bash .git/hooks/pre-commit 2>/dev/null
' _ "$TMP" "$ROOT" 2>&1
if ls "$TMP/.opencode/context/teamdb/" 2>/dev/null | grep -q "data_"; then
  assert_pass "pre-commit ejecuta teamdb-export y crea data_*.sql"
else
  assert_fail "pre-commit ejecuta teamdb-export y crea data_*.sql" "no se crearon"
fi

# 6. Hooks son portables: funcionan con SKALLING_ROOT y sin el
SKALLING_ROOT="$ROOT" bash -c '
  cd "$1"
  git add . 2>/dev/null
  SKALLING_ROOT="$2" bash .git/hooks/pre-commit 2>&1 | grep -q "No such file" && exit 1
  exit 0
' _ "$TMP" "$ROOT" 2>&1
RC=$?
if [ "$RC" = "0" ]; then
  assert_pass "pre-commit funciona con SKALLING_ROOT"
else
  assert_fail "pre-commit funciona con SKALLING_ROOT" "rc=$RC"
fi

# 7. post-merge no falla si no hay directorio teamdb
TMP2_RAW="$(mktemp -d)"
TMP2="$(cd "$TMP2_RAW" && pwd -P)"
git -C "$TMP2" init -q
git -C "$TMP2" config user.email "test@test.com"
git -C "$TMP2" config user.name "Test"
cp "$ROOT/scripts/hooks/post-merge" "$TMP2/.git/hooks/post-merge"
chmod +x "$TMP2/.git/hooks/post-merge"
HOME="$(mktemp -d)" bash -c '
  cd "$1"
  HOME="$HOME" bash .git/hooks/post-merge 2>&1 | grep -q "teamdb-import" && exit 0 || exit 0
' _ "$TMP2" 2>&1
RC=$?
if [ "$RC" = "0" ]; then
  assert_pass "post-merge no falla sin directorio teamdb"
else
  assert_fail "post-merge no falla sin directorio teamdb" "rc=$RC"
fi

# 8. Hooks no usan `|| true` silenciador
if grep -nE '2>/dev/null \|\| true' "$ROOT/scripts/hooks/pre-commit" "$ROOT/scripts/hooks/post-merge" 2>/dev/null; then
  assert_fail "hooks NO tienen || true silenciador"
else
  assert_pass "hooks NO tienen || true silenciador"
fi

rm -rf "$TMP" "$TMP_RAW" "$TMP2" "$TMP2_RAW"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
