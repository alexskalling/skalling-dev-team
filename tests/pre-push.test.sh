#!/usr/bin/env bash
# tests/pre-push.test.sh — Gate pre-push con tree_hash (v0.8.3)
set -euo pipefail

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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# helper: repo con DB teamdb inicializada + dir de export (guarda del hook)
new_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  mkdir -p "$repo/.opencode/context/teamdb"
  bash "$ROOT/scripts/teamdb-init.sh" "$repo" >/dev/null 2>&1
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\n' > "$repo/base.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
}

# helper: simula el stdin del hook pre-push
run_pre_push() {
  local repo="$1" local_sha="$2" remote_sha="$3"
  (cd "$repo" && printf '%s %s %s %s\n' "refs/heads/main" "$local_sha" "refs/heads/main" "$remote_sha" \
    | bash "$ROOT/scripts/hooks/pre-push" 2>&1)
  return $?
}

# ── 1. Guard: sin .opencode/context/teamdb → exit 0 ──
NODB_REPO="$TMP/nodb-repo"
mkdir -p "$NODB_REPO"
git -C "$NODB_REPO" init -q
git -C "$NODB_REPO" config user.email "test@test.com"
git -C "$NODB_REPO" config user.name "Test"
printf 'x\n' > "$NODB_REPO/a.txt"
git -C "$NODB_REPO" add -A
git -C "$NODB_REPO" commit -qm init
set +e
GUARD_OUT="$(cd "$NODB_REPO" && printf 'refs/heads/main %s refs/heads/main %s\n' "$(git -C "$NODB_REPO" rev-parse HEAD)" "0000000000000000000000000000000000000000" | bash "$ROOT/scripts/hooks/pre-push" 2>&1)"
GUARD_RC=$?
set -e
if [ "$GUARD_RC" = "0" ]; then
  assert_pass "pre-push: sin teamdb/ → exit 0 (guard post-merge)"
else
  assert_fail "pre-push: sin teamdb/ → exit 0 (guard post-merge)" "rc=$GUARD_RC out=$GUARD_OUT"
fi

# ── 2. Ref con local_sha todo-ceros (deleción) → skip, exit 0 ──
DEL_REPO="$TMP/del-repo"
new_repo "$DEL_REPO"
set +e
DEL_OUT="$(cd "$DEL_REPO" && printf 'refs/heads/main %s refs/heads/main %s\n' "0000000000000000000000000000000000000000" "0000000000000000000000000000000000000000" | bash "$ROOT/scripts/hooks/pre-push" 2>&1)"
DEL_RC=$?
set -e
if [ "$DEL_RC" = "0" ]; then
  assert_pass "pre-push: local_sha todo-ceros (deleción) → exit 0"
else
  assert_fail "pre-push: local_sha todo-ceros (deleción) → exit 0" "rc=$DEL_RC out=$DEL_OUT"
fi

# ── 3. Receipt fresco + refs válidos → exit 0 ──
OK_REPO="$TMP/ok-repo"
new_repo "$OK_REPO"
BASE_SHA="$(git -C "$OK_REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\necho "segunda linea"\n' > "$OK_REPO/base.sh"
git -C "$OK_REPO" add base.sh
# sellar el candidato ANTES de commitear (flujo real: review → commit → push)
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 9 teo "$OK_REPO" >/dev/null 2>&1
git -C "$OK_REPO" commit -qm "feat: candidato revisado"
LOCAL_SHA="$(git -C "$OK_REPO" rev-parse HEAD)"
set +e
OK_OUT="$(run_pre_push "$OK_REPO" "$LOCAL_SHA" "$BASE_SHA")"
OK_RC=$?
set -e
if [ "$OK_RC" = "0" ] && printf '%s' "$OK_OUT" | grep -q "coincide con el receipt sellado"; then
  assert_pass "pre-push: refs válidos + receipt fresco → exit 0"
else
  assert_fail "pre-push: refs válidos + receipt fresco → exit 0" "rc=$OK_RC out=$OK_OUT"
fi

# ── 4. Cambio post-seal → exit 1 ──
POST_REPO="$TMP/post-repo"
new_repo "$POST_REPO"
BASE_SHA="$(git -C "$POST_REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v1\n' > "$POST_REPO/base.sh"
git -C "$POST_REPO" add base.sh
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 10 teo "$POST_REPO" >/dev/null 2>&1
git -C "$POST_REPO" commit -qm "feat: v1 revisado"
# cambiar una línea DESPUÉS del seal y commitear el cambio no revisado
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v2-tocado\n' > "$POST_REPO/base.sh"
git -C "$POST_REPO" add base.sh
git -C "$POST_REPO" commit -qm "feat: cambio post-seal"
LOCAL_SHA="$(git -C "$POST_REPO" rev-parse HEAD)"
set +e
POST_OUT="$(run_pre_push "$POST_REPO" "$LOCAL_SHA" "$BASE_SHA")"
POST_RC=$?
set -e
if [ "$POST_RC" = "1" ] && printf '%s' "$POST_OUT" | grep -q "no coincide con el último receipt sellado"; then
  assert_pass "pre-push: cambio post-seal → exit 1"
else
  assert_fail "pre-push: cambio post-seal → exit 1" "rc=$POST_RC out=$POST_OUT"
fi

# ── 5. Sin receipt sellado → exit 1 (fail-closed) ──
NOREC_REPO="$TMP/norec-repo"
new_repo "$NOREC_REPO"
BASE_SHA="$(git -C "$NOREC_REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v1\n' > "$NOREC_REPO/base.sh"
git -C "$NOREC_REPO" add base.sh
git -C "$NOREC_REPO" commit -qm "feat: sin sellar"
LOCAL_SHA="$(git -C "$NOREC_REPO" rev-parse HEAD)"
set +e
NOREC_OUT="$(run_pre_push "$NOREC_REPO" "$LOCAL_SHA" "$BASE_SHA")"
NOREC_RC=$?
set -e
if [ "$NOREC_RC" = "1" ] && printf '%s' "$NOREC_OUT" | grep -q "no hay receipt sellado"; then
  assert_pass "pre-push: sin receipt → exit 1 (fail-closed)"
else
  assert_fail "pre-push: sin receipt → exit 1 (fail-closed)" "rc=$NOREC_RC out=$NOREC_OUT"
fi

# ── 6. Branch nuevo sin upstream (remote_sha todo-ceros) → usa merge-base con HEAD ──
NEWBR_REPO="$TMP/newbr-repo"
new_repo "$NEWBR_REPO"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v1\n' > "$NEWBR_REPO/base.sh"
git -C "$NEWBR_REPO" add base.sh
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 11 teo "$NEWBR_REPO" >/dev/null 2>&1
git -C "$NEWBR_REPO" commit -qm "feat: candidato"
git -C "$NEWBR_REPO" branch -M main 2>/dev/null || true
LOCAL_SHA="$(git -C "$NEWBR_REPO" rev-parse HEAD)"
set +e
NEWBR_OUT="$(cd "$NEWBR_REPO" && printf 'refs/heads/main %s refs/heads/main %s\n' "$LOCAL_SHA" "0000000000000000000000000000000000000000" | bash "$ROOT/scripts/hooks/pre-push" 2>&1)"
NEWBR_RC=$?
set -e
# base = merge-base(local_sha, HEAD) = local_sha → diff vacío → skip (exit 0)
if [ "$NEWBR_RC" = "0" ]; then
  assert_pass "pre-push: branch nuevo (remote todo-ceros) → exit 0"
else
  assert_fail "pre-push: branch nuevo (remote todo-ceros) → exit 0" "rc=$NEWBR_RC out=$NEWBR_OUT"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
