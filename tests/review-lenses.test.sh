#!/usr/bin/env bash
# tests/review-lenses.test.sh — Review con 4 lenses + receipt sellado (v0.8.3)
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

new_repo() {
  # new_repo <dir>: repo git con commit inicial
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\n' > "$repo/base.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
}

# ── 1. Kill switch ──
set +e
KS_OUT="$(SKALLING_REVIEW_MODE=off bash "$ROOT/scripts/skalling-review.sh" 2>&1)"
KS_RC=$?
set -e
if [ "$KS_RC" = "0" ] && printf '%s' "$KS_OUT" | grep -q "desactivado"; then
  assert_pass "kill switch: SKALLING_REVIEW_MODE=off → exit 0"
else
  assert_fail "kill switch: SKALLING_REVIEW_MODE=off → exit 0" "rc=$KS_RC out=$KS_OUT"
fi

# ── 2. Lenses detectan patrones (risk → BLOCKER) ──
RISK_REPO="$TMP/risk-repo"
new_repo "$RISK_REPO"
cat > "$RISK_REPO/bad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
eval $USER_INPUT
rm -rf "$TARGET_DIR"
chmod 777 /tmp/x
api_key="secreto"
curl -k https://insecure.example.com
sqlite3 "$DB" "DELETE FROM users WHERE id='$USER_ID'"
EOF
git -C "$RISK_REPO" add bad.sh
set +e
RISK_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --lens risk --cwd "$RISK_REPO" 2>&1)"
RISK_RC=$?
set -e
if [ "$RISK_RC" = "1" ]; then
  assert_pass "risk lens: BLOCKERs → exit 1"
else
  assert_fail "risk lens: BLOCKERs → exit 1" "rc=$RISK_RC"
fi
if printf '%s' "$RISK_OUT" | grep -q "\[BLOCKER\]\[risk\]"; then
  assert_pass "risk lens: reporta [BLOCKER][risk]"
else
  assert_fail "risk lens: reporta [BLOCKER][risk]" "out=$RISK_OUT"
fi
RISK_BLOCKERS="$(printf '%s\n' "$RISK_OUT" | grep -c "\[BLOCKER\]\[risk\]" || true)"
if [ "$RISK_BLOCKERS" -ge 4 ]; then
  assert_pass "risk lens: ≥4 BLOCKERs (eval/rm -rf/chmod 777/secret/curl -k/sqli) — vistos: $RISK_BLOCKERS"
else
  assert_fail "risk lens: ≥4 BLOCKERs (eval/rm -rf/chmod 777/secret/curl -k/sqli)" "vistos: $RISK_BLOCKERS"
fi
if printf '%s' "$RISK_OUT" | grep -q "REVIEW: FAIL"; then
  assert_pass "risk lens: resume REVIEW: FAIL"
else
  assert_fail "risk lens: resume REVIEW: FAIL" "out=$RISK_OUT"
fi

# ── 2b. Falsos negativos históricos: eval con variable + secreto en mayúsculas ──
EVAL_REPO="$TMP/eval-repo"
new_repo "$EVAL_REPO"
cat > "$EVAL_REPO/bad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
eval "$USER_INPUT"
API_KEY="secreto123"
eval "literal_ok"
EOF
git -C "$EVAL_REPO" add bad.sh
set +e
EVAL_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --lens risk --cwd "$EVAL_REPO" 2>&1)"
EVAL_RC=$?
set -e
if [ "$EVAL_RC" = "1" ]; then
  assert_pass "risk: eval con variable + API_KEY mayúsculas → exit 1"
else
  assert_fail "risk: eval con variable + API_KEY mayúsculas → exit 1" "rc=$EVAL_RC out=$EVAL_OUT"
fi
if printf '%s' "$EVAL_OUT" | grep -q "eval con variable"; then
  assert_pass "risk: detecta eval con variable interpolada (eval \"\$x\")"
else
  assert_fail "risk: detecta eval con variable interpolada (eval \"\$x\")" "out=$EVAL_OUT"
fi
if printf '%s' "$EVAL_OUT" | grep -q "secreto hardcodeado"; then
  assert_pass "risk: detecta secreto en mayúsculas (API_KEY=...)"
else
  assert_fail "risk: detecta secreto en mayúsculas (API_KEY=...)" "out=$EVAL_OUT"
fi
EVAL_BLOCKERS="$(printf '%s\n' "$EVAL_OUT" | grep -c "\[BLOCKER\]\[risk\]" || true)"
if [ "$EVAL_BLOCKERS" = "2" ]; then
  assert_pass "risk: exactamente 2 BLOCKERs (eval var + secreto); eval literal NO cuenta"
else
  assert_fail "risk: exactamente 2 BLOCKERs (eval var + secreto); eval literal NO cuenta" "vistos: $EVAL_BLOCKERS out=$EVAL_OUT"
fi

# ── 3. Receipt sellado con tree_hash ──
SEAL_REPO="$TMP/seal-repo"
new_repo "$SEAL_REPO"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\necho "segunda linea"\n' > "$SEAL_REPO/base.sh"
git -C "$SEAL_REPO" add base.sh
mkdir -p "$SEAL_REPO/.opencode/context"
sqlite3 "$SEAL_REPO/.opencode/context/team.db" <<'SQL'
CREATE TABLE audit_log (id INTEGER PRIMARY KEY, ts TEXT NOT NULL, agent TEXT, action TEXT, table_name TEXT, row_id INTEGER, details TEXT, actor_source TEXT DEFAULT 'trigger');
CREATE TABLE receipts (
  id TEXT PRIMARY KEY, task_id TEXT NOT NULL, agent TEXT NOT NULL,
  command TEXT NOT NULL, exit_code INTEGER NOT NULL, output_summary TEXT,
  ts TEXT NOT NULL, tree_hash TEXT
);
SQL
set +e
SEAL_OUT="$(bash "$ROOT/scripts/teamdb-seal-receipt.sh" 42 luz "$SEAL_REPO" 2>&1)"
SEAL_RC=$?
set -e
if [ "$SEAL_RC" = "0" ]; then
  assert_pass "seal: exit 0"
else
  assert_fail "seal: exit 0" "rc=$SEAL_RC out=$SEAL_OUT"
fi
SEALED_HASH="$(sqlite3 "$SEAL_REPO/.opencode/context/team.db" "SELECT tree_hash FROM receipts WHERE tree_hash IS NOT NULL AND tree_hash != '' ORDER BY ts DESC LIMIT 1" 2>/dev/null || true)"
if [ -n "$SEALED_HASH" ] && [ "${#SEALED_HASH}" = "16" ]; then
  assert_pass "seal: receipt con tree_hash de 16 chars ($SEALED_HASH)"
else
  assert_fail "seal: receipt con tree_hash de 16 chars" "hash='$SEALED_HASH' out=$SEAL_OUT"
fi

# ── 4. Script sin set -euo pipefail → resilience WARNING (no BLOCKER) ──
RES_REPO="$TMP/res-repo"
new_repo "$RES_REPO"
printf '#!/usr/bin/env bash\necho sin pipefail\n' > "$RES_REPO/no-pipefail.sh"
git -C "$RES_REPO" add no-pipefail.sh
set +e
RES_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --lens resilience --cwd "$RES_REPO" 2>&1)"
RES_RC=$?
set -e
if [ "$RES_RC" = "0" ]; then
  assert_pass "resilience: sin set -euo pipefail → WARNING, exit 0"
else
  assert_fail "resilience: sin set -euo pipefail → WARNING, exit 0" "rc=$RES_RC"
fi
if printf '%s' "$RES_OUT" | grep -q "\[WARNING\]\[resilience\].*set -euo pipefail"; then
  assert_pass "resilience: reporta WARNING por set -euo pipefail ausente"
else
  assert_fail "resilience: reporta WARNING por set -euo pipefail ausente" "out=$RES_OUT"
fi
if ! printf '%s' "$RES_OUT" | grep -q "\[BLOCKER\]\[resilience\]"; then
  assert_pass "resilience: sin BLOCKER (consistente con diseño)"
else
  assert_fail "resilience: sin BLOCKER (consistente con diseño)" "out=$RES_OUT"
fi

# ── 5. Exit 0 cuando no hay blockers ──
GOOD_REPO="$TMP/good-repo"
new_repo "$GOOD_REPO"
printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "hola\\n"\n' > "$GOOD_REPO/good.sh"
git -C "$GOOD_REPO" add good.sh
set +e
GOOD_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --lens risk --cwd "$GOOD_REPO" 2>&1)"
GOOD_RC=$?
set -e
if [ "$GOOD_RC" = "0" ]; then
  assert_pass "sin blockers → exit 0"
else
  assert_fail "sin blockers → exit 0" "rc=$GOOD_RC out=$GOOD_OUT"
fi
if printf '%s' "$GOOD_OUT" | grep -q "REVIEW: PASS"; then
  assert_pass "sin blockers → REVIEW: PASS"
else
  assert_fail "sin blockers → REVIEW: PASS" "out=$GOOD_OUT"
fi

# ── 6. Gate pre-commit: árbol cambiado post-seal → bloquea; re-seal → pasa ──
GATE_REPO="$TMP/gate-repo"
new_repo "$GATE_REPO"
mkdir -p "$GATE_REPO/.opencode/context"
bash "$ROOT/scripts/teamdb-init.sh" "$GATE_REPO" >/dev/null 2>&1 || true
printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "v1\\n"\n' > "$GATE_REPO/app.sh"
git -C "$GATE_REPO" add app.sh
git -C "$GATE_REPO" commit -qm "base con codigo"

# seal del estado actual (v1)
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 7 luz "$GATE_REPO" >/dev/null 2>&1

# tocar el código después del seal → el hook debe bloquear
printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "v2\\n"\n' > "$GATE_REPO/app.sh"
git -C "$GATE_REPO" add app.sh
set +e
HOOK_OUT="$(cd "$GATE_REPO" && SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/hooks/pre-commit" 2>&1)"
HOOK_RC=$?
set -e
if [ "$HOOK_RC" = "1" ] && printf '%s' "$HOOK_OUT" | grep -q "cambió desde el receipt"; then
  assert_pass "gate: pre-commit bloquea cambio post-seal"
else
  assert_fail "gate: pre-commit bloquea cambio post-seal" "rc=$HOOK_RC out=$HOOK_OUT"
fi

# re-sellar el nuevo estado → el hook pasa (y exporta data_*.sql)
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 7 luz "$GATE_REPO" >/dev/null 2>&1
set +e
HOOK_OUT2="$(cd "$GATE_REPO" && SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/hooks/pre-commit" 2>&1)"
HOOK_RC2=$?
set -e
if [ "$HOOK_RC2" = "0" ]; then
  assert_pass "gate: pre-commit pasa tras re-seal"
else
  assert_fail "gate: pre-commit pasa tras re-seal" "rc=$HOOK_RC2 out=$HOOK_OUT2"
fi
if ls "$GATE_REPO/.opencode/context/teamdb/" >/dev/null 2>&1 && ls "$GATE_REPO/.opencode/context/teamdb/" | grep -q "data_"; then
  assert_pass "gate: pre-commit sigue exportando data_*.sql"
else
  assert_fail "gate: pre-commit sigue exportando data_*.sql"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
