#!/usr/bin/env bash
# tests/review-lenses.test.sh — Review con 4 lenses + receipt sellado (v0.9.0)
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

# BUG D: sellar con el árbol LIMPIO (recién commiteado, sin cambios) → exit 1
# con mensaje claro. Antes sellaba el hash de HEAD y el pre-push jamás lo
# matcheaba con un diff de rango (push bloqueado con error confuso).
set +e
SEAL_CLEAN_OUT="$(bash "$ROOT/scripts/teamdb-seal-receipt.sh" 7 luz "$GATE_REPO" 2>&1)"
SEAL_CLEAN_RC=$?
set -e
if [ "$SEAL_CLEAN_RC" = "1" ] && printf '%s' "$SEAL_CLEAN_OUT" | grep -q "nada que sellar"; then
  assert_pass "seal: árbol limpio (sin cambios) → exit 1 con mensaje claro"
else
  assert_fail "seal: árbol limpio (sin cambios) → exit 1 con mensaje claro" "rc=$SEAL_CLEAN_RC out=$SEAL_CLEAN_OUT"
fi

# sellar con cambios staged → exit 0 (flujo correcto: staged → sellar → commitear)
printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf "v1\\n"\n' > "$GATE_REPO/app.sh"
git -C "$GATE_REPO" add app.sh
set +e
SEAL_STAGED_OUT="$(bash "$ROOT/scripts/teamdb-seal-receipt.sh" 7 luz "$GATE_REPO" 2>&1)"
SEAL_STAGED_RC=$?
set -e
if [ "$SEAL_STAGED_RC" = "0" ]; then
  assert_pass "seal: cambios staged → exit 0"
else
  assert_fail "seal: cambios staged → exit 0" "rc=$SEAL_STAGED_RC out=$SEAL_STAGED_OUT"
fi
git -C "$GATE_REPO" commit -qm "base con codigo"

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
if [ -f "$GATE_REPO/db/teamdb/team.dump.sql" ]; then
  assert_pass "gate: pre-commit genera el dump versionado (db/teamdb/team.dump.sql)"
else
  assert_fail "gate: pre-commit genera el dump versionado (db/teamdb/team.dump.sql)" "no se creo"
fi

# ── 7. --deep: congela bundle con candidate.diff + files.txt + 4 prompts ──
DEEP_REPO="$TMP/deep-repo"
new_repo "$DEEP_REPO"
printf '#!/usr/bin/env bash\nset -euo pipefail\nrm -rf "$TARGET"\n' > "$DEEP_REPO/bad.sh"
git -C "$DEEP_REPO" add bad.sh
set +e
DEEP_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --deep --cwd "$DEEP_REPO" 2>&1)"
DEEP_RC=$?
set -e
if [ "$DEEP_RC" = "0" ]; then
  assert_pass "deep: --deep → exit 0"
else
  assert_fail "deep: --deep → exit 0" "rc=$DEEP_RC out=$DEEP_OUT"
fi
DEEP_DIR="$(printf '%s\n' "$DEEP_OUT" | sed -n 's/^Bundle congelado: //p')"
if [ -n "$DEEP_DIR" ] \
   && [ -f "$DEEP_DIR/candidate.diff" ] \
   && [ -f "$DEEP_DIR/files.txt" ] \
   && [ -f "$DEEP_DIR/prompt-risk.md" ] \
   && [ -f "$DEEP_DIR/prompt-resilience.md" ] \
   && [ -f "$DEEP_DIR/prompt-readability.md" ] \
   && [ -f "$DEEP_DIR/prompt-reliability.md" ]; then
  assert_pass "deep: bundle con candidate.diff + files.txt + 4 prompts"
else
  assert_fail "deep: bundle con candidate.diff + files.txt + 4 prompts" "dir='$DEEP_DIR'"
fi
if grep -q "REVISÁ SOLO EL DIFF CONGELADO" "$DEEP_DIR/prompt-risk.md"; then
  assert_pass "deep: prompt dice REVISÁ SOLO EL DIFF CONGELADO"
else
  assert_fail "deep: prompt dice REVISÁ SOLO EL DIFF CONGELADO"
fi
if grep -q "agents-base/Luz.md" "$DEEP_DIR/prompt-risk.md" \
   && grep -q "agents-base/Jhon.md" "$DEEP_DIR/prompt-resilience.md" \
   && grep -q "agents-base/Pau.md" "$DEEP_DIR/prompt-readability.md" \
   && grep -q "agents-base/Jhon.md" "$DEEP_DIR/prompt-reliability.md"; then
  assert_pass "deep: mapping lens → agente (Luz/Jhon/Pau/Jhon)"
else
  assert_fail "deep: mapping lens → agente (Luz/Jhon/Pau/Jhon)"
fi

# ── 7b. --deep idempotente: no sobreescribe bundle existente ──
DEEP_OUT2="$(bash "$ROOT/scripts/skalling-review.sh" --deep --cwd "$DEEP_REPO" 2>&1)"
if printf '%s' "$DEEP_OUT2" | grep -q "bundle ya existe"; then
  assert_pass "deep: idempotente (2do run avisa, no sobreescribe)"
else
  assert_fail "deep: idempotente (2do run avisa, no sobreescribe)" "out=$DEEP_OUT2"
fi

# ── 8. --deep --lens risk → solo prompt-risk.md ──
DEEP1_REPO="$TMP/deep1-repo"
new_repo "$DEEP1_REPO"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\n' > "$DEEP1_REPO/a.sh"
git -C "$DEEP1_REPO" add a.sh
DEEP1_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --deep --lens risk --cwd "$DEEP1_REPO" 2>&1)"
DEEP1_DIR="$(printf '%s\n' "$DEEP1_OUT" | sed -n 's/^Bundle congelado: //p')"
if [ -f "$DEEP1_DIR/prompt-risk.md" ] && [ ! -f "$DEEP1_DIR/prompt-resilience.md" ]; then
  assert_pass "deep: --lens risk genera solo prompt-risk.md"
else
  assert_fail "deep: --lens risk genera solo prompt-risk.md" "dir='$DEEP1_DIR'"
fi

# ── 9. --collect con BLOCKER → exit 1 ──
cat > "$DEEP_DIR/findings-risk.json" <<'EOF'
[{"file":"bad.sh","line":3,"severity":"BLOCKER","message":"rm -rf sin guarda de ruta"}]
EOF
set +e
COLLECT_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --collect "$DEEP_DIR" --cwd "$DEEP_REPO" --lens risk 2>&1)"
COLLECT_RC=$?
set -e
if [ "$COLLECT_RC" = "1" ] && printf '%s' "$COLLECT_OUT" | grep -q "\[BLOCKER\]\[risk\]"; then
  assert_pass "collect: findings con BLOCKER → exit 1"
else
  assert_fail "collect: findings con BLOCKER → exit 1" "rc=$COLLECT_RC out=$COLLECT_OUT"
fi
if printf '%s' "$COLLECT_OUT" | grep -q "REVIEW: FAIL"; then
  assert_pass "collect: resume REVIEW: FAIL con blockers"
else
  assert_fail "collect: resume REVIEW: FAIL con blockers" "out=$COLLECT_OUT"
fi

# ── 10. --collect con WARNING/SUGGESTION (sin BLOCKER) → exit 0 ──
rm -f "$DEEP_DIR"/findings-*.json
cat > "$DEEP_DIR/findings-risk.json" <<'EOF'
[{"file":"bad.sh","line":1,"severity":"WARNING","message":"podria validar la variable"}]
EOF
set +e
COLLECT_OUT2="$(bash "$ROOT/scripts/skalling-review.sh" --collect "$DEEP_DIR" --cwd "$DEEP_REPO" --lens risk 2>&1)"
COLLECT_RC2=$?
set -e
if [ "$COLLECT_RC2" = "0" ] && printf '%s' "$COLLECT_OUT2" | grep -q "REVIEW: PASS"; then
  assert_pass "collect: solo WARNING → exit 0 (REVIEW: PASS)"
else
  assert_fail "collect: solo WARNING → exit 0 (REVIEW: PASS)" "rc=$COLLECT_RC2 out=$COLLECT_OUT2"
fi

# ── 11. BUG B: findings AUSENTES → fail-closed (NUNCA PASS) ──
# Bundle sin NINGÚN findings-*.json (vacío/recién creado) → exit != 0 con
# mensaje claro. Antes: WARN + continue → 0 blockers → PASS sin revisión (bug).
rm -f "$DEEP_DIR"/findings-*.json
set +e
COLLECT_OUT3="$(bash "$ROOT/scripts/skalling-review.sh" --collect "$DEEP_DIR" --cwd "$DEEP_REPO" --lens all 2>&1)"
COLLECT_RC3=$?
set -e
if [ "$COLLECT_RC3" != "0" ] && printf '%s' "$COLLECT_OUT3" | grep -q "sin resultados de agentes"; then
  assert_pass "collect: bundle sin findings-*.json → exit != 0 (fail-closed)"
else
  assert_fail "collect: bundle sin findings-*.json → exit != 0 (fail-closed)" "rc=$COLLECT_RC3 out=$COLLECT_OUT3"
fi

# ── 11b. BUG B: lens seleccionado sin findings → BLOCKER + exit != 0 ──
# Contrato: un lens seleccionado sin findings-<lens>.json = el agente no reportó
# = 1 BLOCKER; el review FALLA (antes: WARN + continue → 0 blockers → PASS).
PARTIAL_DIR="$TMP/partial-bundle"
mkdir -p "$PARTIAL_DIR"
printf '%s\n' '[{"file":"x.sh","line":1,"severity":"SUGGESTION","message":"opcional"}]' > "$PARTIAL_DIR/findings-risk.json"
set +e
PARTIAL_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --collect "$PARTIAL_DIR" --cwd "$DEEP_REPO" --lens all 2>&1)"
PARTIAL_RC=$?
set -e
if [ "$PARTIAL_RC" != "0" ] && printf '%s' "$PARTIAL_OUT" | grep -q "no reportó findings"; then
  assert_pass "collect: lens sin findings-<lens>.json → BLOCKER + exit != 0"
else
  assert_fail "collect: lens sin findings-<lens>.json → BLOCKER + exit != 0" "rc=$PARTIAL_RC out=$PARTIAL_OUT"
fi
if printf '%s' "$PARTIAL_OUT" | grep -q "\[BLOCKER\]\[resilience\]"; then
  assert_pass "collect: el BLOCKER ausente nombra al lens (resilience)"
else
  assert_fail "collect: el BLOCKER ausente nombra al lens (resilience)" "out=$PARTIAL_OUT"
fi

# ── 12. BUG 3+4: falsos negativos del lens risk + fail-closed de --collect ──
# Patrones legítimos que ANTES daban falso positivo: rm sobre $TMP con guarda,
# sqlite con $(_sql_quote ...) (escape seguro del repo) y líneas comentadas.
BUG34_REPO="$TMP/bug34-repo"
new_repo "$BUG34_REPO"
cat > "$BUG34_REPO/ok.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
rm -rf "$TMP"
sqlite3 "$DB" "SELECT id FROM attempts WHERE id = $(_sql_quote "$ID")"
# eval "$USER_INPUT"
EOF
git -C "$BUG34_REPO" add ok.sh
set +e
OK34_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --lens risk --cwd "$BUG34_REPO" 2>&1)"
OK34_RC=$?
set -e
if [ "$OK34_RC" = "0" ]; then
  assert_pass "risk: \$TMP con guarda + _sql_quote + eval comentado → exit 0"
else
  assert_fail "risk: \$TMP con guarda + _sql_quote + eval comentado → exit 0" "rc=$OK34_RC out=$OK34_OUT"
fi
# Falsos negativos que la auditoría detectó: rm sobre ruta temp del sistema y
# SQLi dentro de comillas dobles — ahora SÍ deben dar BLOCKER.
cat > "$BUG34_REPO/bad.sh" <<'EOF'
#!/usr/bin/env bash
rm -rf /var/tmp/cache/*
rm -rf "$CACHE"
sqlite3 "$DB" "SELECT id FROM attempts WHERE id = $ID"
EOF
git -C "$BUG34_REPO" add bad.sh
set +e
BAD34_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --lens risk --cwd "$BUG34_REPO" 2>&1)"
BAD34_RC=$?
set -e
if [ "$BAD34_RC" = "1" ] && printf '%s' "$BAD34_OUT" | grep -q "ruta temp del sistema"; then
  assert_pass "risk: rm -rf /var/tmp/cache/* → BLOCKER ruta temp del sistema"
else
  assert_fail "risk: rm -rf /var/tmp/cache/* → BLOCKER ruta temp del sistema" "rc=$BAD34_RC out=$BAD34_OUT"
fi
if printf '%s' "$BAD34_OUT" | grep -q "rm -rf sin guarda de ruta"; then
  assert_pass "risk: rm -rf \$CACHE sin guarda sigue → BLOCKER"
else
  assert_fail "risk: rm -rf \$CACHE sin guarda sigue → BLOCKER" "out=$BAD34_OUT"
fi
if printf '%s' "$BAD34_OUT" | grep -q "SQL injection.*comillas dobles"; then
  assert_pass "risk: sqlite3 ... \"WHERE id = \$ID\" → BLOCKER SQLi comillas dobles"
else
  assert_fail "risk: sqlite3 ... \"WHERE id = \$ID\" → BLOCKER SQLi comillas dobles" "out=$BAD34_OUT"
fi

# Fail-closed: findings-<lens>.json ilegible (malformado o no-lista) → NUNCA PASS
BUG34_DIR="$TMP/bug34-bundle"
mkdir -p "$BUG34_DIR"
printf 'esto no es json\n' > "$BUG34_DIR/findings-risk.json"
set +e
MALFORM_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --collect "$BUG34_DIR" --cwd "$BUG34_REPO" --lens risk 2>&1)"
MALFORM_RC=$?
set -e
if [ "$MALFORM_RC" = "1" ] && printf '%s' "$MALFORM_OUT" | grep -q "resultado ilegible"; then
  assert_pass "collect: JSON malformado → fail-closed (exit 1, BLOCKER ilegible)"
else
  assert_fail "collect: JSON malformado → fail-closed (exit 1, BLOCKER ilegible)" "rc=$MALFORM_RC out=$MALFORM_OUT"
fi
printf '{"nop": true}\n' > "$BUG34_DIR/findings-risk.json"
set +e
NOTLIST_OUT="$(bash "$ROOT/scripts/skalling-review.sh" --collect "$BUG34_DIR" --cwd "$BUG34_REPO" --lens risk 2>&1)"
NOTLIST_RC=$?
set -e
if [ "$NOTLIST_RC" = "1" ] && printf '%s' "$NOTLIST_OUT" | grep -q "resultado ilegible"; then
  assert_pass "collect: JSON válido no-lista → fail-closed (exit 1, BLOCKER ilegible)"
else
  assert_fail "collect: JSON válido no-lista → fail-closed (exit 1, BLOCKER ilegible)" "rc=$NOTLIST_RC out=$NOTLIST_OUT"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
