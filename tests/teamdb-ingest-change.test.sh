#!/usr/bin/env bash
# tests/teamdb-ingest-change.test.sh — teamdb-ingest-change.sh atomicidad + idempotencia
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

run_capture() {
  local _CAP_RC=0
  _CAP_OUT="$(eval "$@" 2>&1)" || _CAP_RC=$?
  CAPTURE_RC="$_CAP_RC"
  CAPTURE_OUT="$_CAP_OUT"
}

TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
. "$ROOT/scripts/lib/lib-teamdb.sh"

# Helper: crear estructura de change dir
create_change_dir() {
  local dir="$1"
  mkdir -p "$dir/specs"
  cat > "$dir/proposal.md" <<'EOF'
---
title: Auth feature
status: draft
agent: pol
---

# Intent

Auth with JWT tokens.
EOF
  cat > "$dir/tasks.md" <<'EOF'
- [ ] Implementar login endpoint
- [ ] Implementar logout _depends: [task-implementar-login-endpoint]
EOF
  cat > "$dir/design.md" <<'EOF'
# Design

JWT-based auth.
EOF
  cat > "$dir/specs/01-jwt.md" <<'EOF'
# Spec 01: JWT

**Given** valid credentials
**Then** issue token
EOF
  cat > "$dir/specs/02-validation.md" <<'EOF'
# Spec 02: Validation

**Given** invalid email
**Then** return 400
EOF
}

# ─── Caso 1: ingest nuevo change ───
echo "=== Caso 1: ingest nuevo change ==="
CHANGE_DIR="$TEST_DIR/change-test"
create_change_dir "$CHANGE_DIR"

run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR'"
if [ "$CAPTURE_RC" = "0" ]; then
  assert_pass "ingest retorna exit 0"
else
  assert_fail "ingest retorna exit 0" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Verificar proposal creado
PCOUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM proposals WHERE slug='auth-feature'")
if [ "$PCOUNT" = "1" ]; then
  assert_pass "proposal creado"
else
  assert_fail "proposal creado" "count=$PCOUNT"
fi

# Verificar plan creado
PLCOUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plans WHERE slug='auth-feature'")
if [ "$PLCOUNT" = "1" ]; then
  assert_pass "plan creado"
else
  assert_fail "plan creado" "count=$PLCOUNT"
fi

# Verificar tasks (2 tasks + 1 dependency)
TCOUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-feature')")
if [ "$TCOUNT" = "2" ]; then
  assert_pass "2 tasks creadas"
else
  assert_fail "2 tasks creadas" "count=$TCOUNT"
fi

# Verificar specs (2 specs)
SCOUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM specs WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-feature')")
if [ "$SCOUNT" = "2" ]; then
  assert_pass "2 specs creadas"
else
  assert_fail "2 specs creadas" "count=$SCOUNT"
fi

# Verificar design_md del plan
DM=$(teamdb_exec_value "$DB" "SELECT design_md FROM plans WHERE slug='auth-feature'")
if [ -n "$DM" ] && [ "$DM" != "0" ]; then
  assert_pass "design_md persistido"
else
  assert_fail "design_md persistido" "dm='$DM'"
fi

# ─── Caso 2: idempotencia (re-run sin --force = SKIP) ───
echo "=== Caso 2: idempotencia (re-run sin --force) ==="
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR'"
if [ "$CAPTURE_RC" = "0" ] && echo "$CAPTURE_OUT" | grep -q "SKIP"; then
  assert_pass "re-run sin --force = SKIP"
else
  assert_fail "re-run sin --force = SKIP" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# Tasks no se duplican
TCOUNT2=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-feature')")
if [ "$TCOUNT2" = "2" ]; then
  assert_pass "re-run no duplica tasks"
else
  assert_fail "re-run no duplica tasks" "count=$TCOUNT2"
fi

# ─── Caso 3: --force re-ingiere ───
echo "=== Caso 3: --force re-ingiere ==="
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR' --force"
if [ "$CAPTURE_RC" = "0" ] && echo "$CAPTURE_OUT" | grep -q "ingested"; then
  assert_pass "--force re-ingiere"
else
  assert_fail "--force re-ingiere" "rc=$CAPTURE_RC out=$CAPTURE_OUT"
fi

# ─── Caso 4: --dry-run no toca la DB ───
echo "=== Caso 4: --dry-run no toca la DB ==="
CHANGE_DIR2="$TEST_DIR/change-dry"
create_change_dir "$CHANGE_DIR2"
OLD_TCOUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks")
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR2' --dry-run"
NEW_TCOUNT=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks")
if [ "$OLD_TCOUNT" = "$NEW_TCOUNT" ]; then
  assert_pass "--dry-run no modifica DB"
else
  assert_fail "--dry-run no modifica DB" "old=$OLD_TCOUNT new=$NEW_TCOUNT"
fi

# ─── Caso 5: proposal.md sin frontmatter ───
echo "=== Caso 5: proposal.md sin frontmatter ==="
CHANGE_DIR3="$TEST_DIR/change-no-fm"
mkdir -p "$CHANGE_DIR3/specs"
cat > "$CHANGE_DIR3/proposal.md" <<'EOF'
# My Feature

Some description.
EOF
cat > "$CHANGE_DIR3/tasks.md" <<'EOF'
- [ ] Task uno
EOF
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR3' --force"
if [ "$CAPTURE_RC" = "0" ]; then
  PCOUNT3=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM proposals WHERE slug LIKE '%my-feature%'")
  if [ "$PCOUNT3" -ge "1" ]; then
    assert_pass "proposal sin frontmatter: slug derivado del dir"
  else
    assert_fail "proposal sin frontmatter" "slug no match"
  fi
else
  assert_fail "proposal sin frontmatter" "rc=$CAPTURE_RC"
fi

# ─── Caso 6: sin tasks.md ni specs ───
echo "=== Caso 6: solo proposal.md (sin tasks ni specs) ==="
CHANGE_DIR4="$TEST_DIR/change-minimal"
mkdir -p "$CHANGE_DIR4/specs"
cat > "$CHANGE_DIR4/proposal.md" <<'EOF'
---
title: Minimal
status: approved
agent: pol
---

Minimal change.
EOF
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR4'"
if [ "$CAPTURE_RC" = "0" ]; then
  P4=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM proposals WHERE slug='minimal'")
  PL4=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM plans WHERE slug='minimal'")
  T4=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='minimal')")
  S4=$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM specs WHERE plan_id=(SELECT id FROM plans WHERE slug='minimal')")
  if [ "$P4" = "1" ] && [ "$PL4" = "1" ] && [ "$T4" = "0" ] && [ "$S4" = "0" ]; then
    assert_pass "solo proposal+plan sin tasks/specs"
  else
    assert_fail "solo proposal+plan sin tasks/specs" "p=$P4 pl=$PL4 t=$T4 s=$S4"
  fi
else
  assert_fail "solo proposal.md" "rc=$CAPTURE_RC"
fi

# ─── Caso 7: cambio de status del proposal ───
echo "=== Caso 7: proposal status preserved ==="
PSTATUS=$(teamdb_exec_value "$DB" "SELECT status FROM proposals WHERE slug='minimal'")
if [ "$PSTATUS" = "approved" ]; then
  assert_pass "proposal status=approved preservado"
else
  assert_fail "proposal status preservado" "status=$PSTATUS"
fi

# ─── Caso 8: proposal.md con status approved ───
echo "=== Caso 8: proposal status=draft default ==="
CHANGE_DIR5="$TEST_DIR/change-default-status"
mkdir -p "$CHANGE_DIR5/specs"
cat > "$CHANGE_DIR5/proposal.md" <<'EOF'
# No Status

No status in frontmatter.
EOF
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR5' --force"
PSTATUS5=$(teamdb_exec_value "$DB" "SELECT status FROM proposals WHERE slug='no-status'")
if [ "$PSTATUS5" = "draft" ]; then
  assert_pass "sin status → default draft"
else
  assert_fail "sin status → default draft" "status=$PSTATUS5"
fi

# ─── Caso 9: change-dir inexistente ───
echo "=== Caso 9: change-dir inexistente ==="
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '/no/existe'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "change-dir inexistente rechazado"
else
  assert_fail "change-dir inexistente rechazado" "rc=0"
fi

# ─── Caso 10: sin proposal.md ───
echo "=== Caso 10: sin proposal.md ==="
CHANGE_DIR6="$TEST_DIR/change-no-prop"
mkdir -p "$CHANGE_DIR6/specs"
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR6'"
if [ "$CAPTURE_RC" != "0" ]; then
  assert_pass "sin proposal.md rechazado"
else
  assert_fail "sin proposal.md rechazado" "rc=0"
fi

# ─── Caso 11: specs con slug prefix spec- ───
echo "=== Caso 11: specs slug con prefijo spec- ==="
CHANGE_DIR7="$TEST_DIR/change-spec-prefix"
mkdir -p "$CHANGE_DIR7/specs"
cat > "$CHANGE_DIR7/proposal.md" <<'EOF'
---
title: Spec prefix test
status: draft
agent: pol
---

Test.
EOF
cat > "$CHANGE_DIR7/specs/spec-01-test.md" <<'EOF'
# Test spec

Body content.
EOF
run_capture "bash '$ROOT/scripts/teamdb-ingest-change.sh' '$TEST_DIR' '$CHANGE_DIR7' --force"
if [ "$CAPTURE_RC" = "0" ]; then
  S7=$(teamdb_exec_value "$DB" "SELECT slug FROM specs WHERE plan_id=(SELECT id FROM plans WHERE slug='spec-prefix-test')")
  if [ "$S7" = "spec-01-test" ]; then
    assert_pass "spec slug con prefijo spec- preservado"
  else
    assert_fail "spec slug con prefijo spec-" "slug=$S7"
  fi
else
  assert_fail "spec slug con prefijo spec-" "rc=$CAPTURE_RC"
fi

# ─── Caso 12: intent_md del proposal contiene markdown ───
echo "=== Caso 12: intent_md preserva markdown ==="
INTENT=$(teamdb_exec_value "$DB" "SELECT intent_md FROM proposals WHERE slug='auth-feature'")
if echo "$INTENT" | grep -q "JWT"; then
  assert_pass "intent_md preserva contenido"
else
  assert_fail "intent_md preserva contenido" "intent='$INTENT'"
fi

# ─── Caso 13: due_date NO inventado (queda NULL) ───
echo "=== Caso 13: due_date no inventado (NULL sin token de fecha) ==="
DD=$(teamdb_exec_value "$DB" "SELECT due_date FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='auth-feature') LIMIT 1")
if [ -z "$DD" ] || [ "$DD" = "0" ]; then
  assert_pass "due_date NULL sin token de fecha"
else
  assert_fail "due_date no inventado" "due_date='$DD'"
fi

# ─── Caso 14: shellcheck del script ───
echo "=== Caso 14: shellcheck ==="
SHELLCHECK_RC=0
shellcheck -e SC1091 "$ROOT/scripts/teamdb-ingest-change.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-ingest-change.sh shellcheck 0 errores"
else
  assert_fail "teamdb-ingest-change.sh shellcheck" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
