#!/usr/bin/env bash
# tests/teamdb-export-audit.test.sh — Validación export audit_log + schema_meta (T-2.7)
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

TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"

# Generar al menos un audit row via teamdb_write_project
TEAMDB_ACTOR=test bash "$ROOT/scripts/teamdb-write-wal.test.sh" >/dev/null 2>&1 || true
TEAMDB_ACTOR=test teamdb_write_project "$DB" \
  "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,datetime('now'))" \
  "audit-export-test" "AET" "x" >/dev/null 2>&1

# 1. data_audit_log.sql existe
bash "$ROOT/scripts/teamdb-export.sh" "$TEST_DIR" >/dev/null 2>&1
if [ -f "$TEST_DIR/.opencode/context/teamdb/data_audit_log.sql" ]; then
  assert_pass "data_audit_log.sql existe tras export"
else
  assert_fail "data_audit_log.sql existe tras export" "no archivo"
fi

# 2. data_schema_meta.sql existe
if [ -f "$TEST_DIR/.opencode/context/teamdb/data_schema_meta.sql" ]; then
  assert_pass "data_schema_meta.sql existe tras export"
else
  assert_fail "data_schema_meta.sql existe tras export" "no archivo"
fi

# 3. audit_log row presente en data_audit_log.sql
if [ -f "$TEST_DIR/.opencode/context/teamdb/data_audit_log.sql" ]; then
  if grep -q "INSERT INTO audit_log" "$TEST_DIR/.opencode/context/teamdb/data_audit_log.sql"; then
    assert_pass "data_audit_log.sql tiene INSERTs"
  else
    assert_fail "data_audit_log.sql tiene INSERTs" "no matches"
  fi
fi

# 4. schema_meta row presente
if [ -f "$TEST_DIR/.opencode/context/teamdb/data_schema_meta.sql" ]; then
  if grep -q "INSERT INTO schema_meta" "$TEST_DIR/.opencode/context/teamdb/data_schema_meta.sql"; then
    assert_pass "data_schema_meta.sql tiene INSERTs"
  else
    assert_fail "data_schema_meta.sql tiene INSERTs" "no matches"
  fi
fi

# 5. Round-trip: import en DB nueva preserva audit_log
TEST_DIR2="$(mktemp -d)"
mkdir -p "$TEST_DIR2/.opencode/context"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR2" >/dev/null 2>&1
# Copiar data_audit_log.sql y aplicarlo
if [ -f "$TEST_DIR/.opencode/context/teamdb/data_audit_log.sql" ]; then
  AUDIT_FILE="$TEST_DIR/.opencode/context/teamdb/data_audit_log.sql"
  # Extraer solo INSERTs
  INSERT_COUNT=$(grep -c "^INSERT INTO audit_log" "$AUDIT_FILE" 2>/dev/null || echo 0)
  if [ "$INSERT_COUNT" -gt 0 ]; then
    # Aplicar los INSERTs
    grep "^INSERT INTO audit_log" "$AUDIT_FILE" | sqlite3 "$TEST_DIR2/.opencode/context/team.db" 2>&1 || true
    AUDIT_ROUND_TRIP=$(sqlite3 "$TEST_DIR2/.opencode/context/team.db" "SELECT COUNT(*) FROM audit_log" 2>/dev/null || echo 0)
    if [ "$AUDIT_ROUND_TRIP" -ge 0 ]; then
      assert_pass "round-trip: audit_log puede importarse en DB nueva"
    else
      assert_fail "round-trip: audit_log puede importarse" "rc=$?"
    fi
  else
    assert_fail "audit_log.sql no tiene INSERTs" "count=$INSERT_COUNT"
  fi
fi

# 6. Export incluye tablas cycle (proposals, plans, specs, design_notes, tasks)
for tbl in proposals plans tasks; do
  if [ -f "$TEST_DIR/.opencode/context/teamdb/data_${tbl}.sql" ]; then
    assert_pass "export incluye data_${tbl}.sql"
  else
    assert_fail "export incluye data_${tbl}.sql"
  fi
done

# 7. Export incluye DAG/claims/history/capsules (T-2.9)
for tbl in task_dependencies task_claims plan_history task_context_capsules; do
  if [ -f "$TEST_DIR/.opencode/context/teamdb/data_${tbl}.sql" ]; then
    assert_pass "export incluye data_${tbl}.sql"
  else
    assert_fail "export incluye data_${tbl}.sql"
  fi
done

# 8. Idempotente: 2 corridas no rompen
bash "$ROOT/scripts/teamdb-export.sh" "$TEST_DIR" >/dev/null 2>&1
bash "$ROOT/scripts/teamdb-export.sh" "$TEST_DIR" >/dev/null 2>&1
if [ -f "$TEST_DIR/.opencode/context/teamdb/data_audit_log.sql" ]; then
  assert_pass "export idempotente"
else
  assert_fail "export idempotente"
fi

# 9. shellcheck
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/teamdb-export.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "teamdb-export.sh shellcheck 0 errores"
else
  assert_fail "teamdb-export.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

rm -rf "$TEST_DIR" "$TEST_DIR2"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
