#!/usr/bin/env bash
# tests/git-gate-failclosed.test.sh — git-gate.py debe ser fail-closed: si se
# commitea código y team.db no existe, bloquear (no hay forma de saber si ese
# código ya se revisó). Antes, sin team.db, el chequeo de receipt se saltaba
# en silencio (`if not db or ...: return`) y el commit pasaba igual.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

new_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  printf 'texto\n' > "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
}

# ── 1. team.db no existe + se commitea código → bloqueado, mensaje explícito ──
REPO1="$TMP/repo1"
new_repo "$REPO1"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho hola\n' > "$REPO1/app.sh"
git -C "$REPO1" add app.sh
set +e
OUT1="$(cd "$REPO1" && SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/hooks/pre-commit" 2>&1)"
RC1=$?
set -e
if [ "$RC1" = "1" ] && grep -q "team.db no existe" <<< "$OUT1"; then
  assert_pass "sin team.db + código staged → bloquea con mensaje explícito"
else
  assert_fail "sin team.db + código staged → bloquea con mensaje explícito" "rc=$RC1 out=$OUT1"
fi

# ── 2. team.db no existe + solo se toca un .md (sin código) → no bloquea ──
REPO2="$TMP/repo2"
new_repo "$REPO2"
printf 'más texto\n' >> "$REPO2/README.md"
git -C "$REPO2" add README.md
set +e
OUT2="$(cd "$REPO2" && SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/hooks/pre-commit" 2>&1)"
RC2=$?
set -e
if [ "$RC2" = "0" ]; then
  assert_pass "sin team.db + solo .md staged (sin código) → no bloquea"
else
  assert_fail "sin team.db + solo .md staged (sin código) → no bloquea" "rc=$RC2 out=$OUT2"
fi

# ── 3. team.db existe pero sin receipt sellado → el mensaje sigue siendo el
#      de "falta revisión aprobada", NO el de "team.db no existe" (no hay que
#      confundir las dos causas de bloqueo) ──
REPO3="$TMP/repo3"
new_repo "$REPO3"
bash "$ROOT/scripts/teamdb-init.sh" "$REPO3" >/dev/null 2>&1
printf '#!/usr/bin/env bash\nset -euo pipefail\necho hola\n' > "$REPO3/app.sh"
git -C "$REPO3" add app.sh
set +e
OUT3="$(cd "$REPO3" && SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/hooks/pre-commit" 2>&1)"
RC3=$?
set -e
if [ "$RC3" = "1" ] && grep -q "falta revisión aprobada" <<< "$OUT3" && ! grep -q "team.db no existe" <<< "$OUT3"; then
  assert_pass "con team.db pero sin receipt → bloquea por revisión, no por DB faltante"
else
  assert_fail "con team.db pero sin receipt → bloquea por revisión, no por DB faltante" "rc=$RC3 out=$OUT3"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
