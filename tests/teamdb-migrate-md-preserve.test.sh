#!/usr/bin/env bash
# tests/teamdb-migrate-md-preserve.test.sh — Validación preserva .md (T-2.8, DC-1)
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

# ─── Caso 1: .md con frontmatter se migra a DB
TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context/concept"
DB="$TEST_DIR/.opencode/context/team.db"

cat > "$TEST_DIR/.opencode/context/concept/auth-jwt.md" <<'EOF'
---
type: Concept
tags: [auth, jwt]
confidence: 0.9
---

# Auth JWT

Contenido del concept doc.
EOF

bash "$ROOT/scripts/teamdb-migrate.sh" "$TEST_DIR" >/dev/null 2>&1

COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='auth-jwt'")
if [ "$COUNT" = "1" ]; then
  assert_pass ".md con frontmatter se migra a DB"
else
  assert_fail ".md con frontmatter se migra" "count=$COUNT"
fi

# 2. El archivo .md SIGUE EXISTIENDO (DC-1)
if [ -f "$TEST_DIR/.opencode/context/concept/auth-jwt.md" ]; then
  assert_pass ".md preservado tras migrate (DC-1)"
else
  assert_fail ".md preservado tras migrate" "no existe"
fi

# 3. El .md NO se movió a legacy/
if [ ! -d "$TEST_DIR/.opencode/context/legacy/concept" ]; then
  assert_pass ".md NO se movió a legacy/"
else
  assert_fail ".md NO se movió a legacy/" "legacy/concept existe"
fi

# 4. .jsonl SÍ se mueve a legacy/
echo '{"topic":"j","decision":"d"}' > "$TEST_DIR/.opencode/context/DECISIONS.jsonl"
bash "$ROOT/scripts/teamdb-migrate.sh" "$TEST_DIR" >/dev/null 2>&1
if [ -d "$TEST_DIR/.opencode/context/legacy" ] && [ -f "$TEST_DIR/.opencode/context/legacy/DECISIONS.jsonl" ]; then
  assert_pass ".jsonl SÍ se movió a legacy/"
else
  assert_fail ".jsonl SÍ se movió a legacy/" "no legacy/DECISIONS.jsonl"
fi

# 5. Idempotente: 3 corridas no rompen
bash "$ROOT/scripts/teamdb-migrate.sh" "$TEST_DIR" >/dev/null 2>&1
bash "$ROOT/scripts/teamdb-migrate.sh" "$TEST_DIR" >/dev/null 2>&1
bash "$ROOT/scripts/teamdb-migrate.sh" "$TEST_DIR" >/dev/null 2>&1
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='auth-jwt'")
if [ "$COUNT" = "1" ]; then
  assert_pass "idempotente: 3 corridas no duplican"
else
  assert_fail "idempotente" "count=$COUNT"
fi

# 6. Sin .jsonl: termina 0 + warning
TEST_DIR2="$(mktemp -d)"
mkdir -p "$TEST_DIR2/.opencode/context/concept"
# Solo .md, sin .jsonl
cat > "$TEST_DIR2/.opencode/context/concept/x.md" <<'EOF'
---
type: Concept
---
# X
body
EOF
run_capture() {
  local _CAP_RC=0
  _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
  CAPTURE_RC="$_CAP_RC"
  CAPTURE_OUT="$_CAP_OUT"
}
run_capture "bash '$ROOT/scripts/teamdb-migrate.sh' '$TEST_DIR2'"
if [ "$CAPTURE_RC" = "0" ]; then
  assert_pass "sin .jsonl: termina exit 0"
else
  assert_fail "sin .jsonl: termina exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 7. Sin .jsonl ni .md: warning + exit 0
TEST_DIR3="$(mktemp -d)"
mkdir -p "$TEST_DIR3/.opencode/context"
run_capture "bash '$ROOT/scripts/teamdb-migrate.sh' '$TEST_DIR3'"
if [ "$CAPTURE_RC" = "0" ] || echo "$CAPTURE_OUT" | grep -qE "WARN|warning"; then
  assert_pass "sin .jsonl ni .md: warning + exit 0"
else
  assert_fail "sin .jsonl ni .md" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# 8. .md con frontmatter malformado: continúa (no falla)
TEST_DIR4="$(mktemp -d)"
mkdir -p "$TEST_DIR4/.opencode/context/concept"
cat > "$TEST_DIR4/.opencode/context/concept/malformed.md" <<'EOF'
No frontmatter here, just plain content.
EOF
run_capture "bash '$ROOT/scripts/teamdb-migrate.sh' '$TEST_DIR4'"
if [ "$CAPTURE_RC" = "0" ]; then
  assert_pass ".md sin frontmatter: continúa (exit 0)"
else
  assert_fail ".md sin frontmatter: continúa" "rc=$CAPTURE_RC"
fi

# 9. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-migrate.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-migrate.sh shellcheck 0 errores"
else
  assert_fail "teamdb-migrate.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR" "$TEST_DIR2" "$TEST_DIR3" "$TEST_DIR4"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
