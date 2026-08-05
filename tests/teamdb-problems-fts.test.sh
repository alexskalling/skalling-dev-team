#!/usr/bin/env bash
# tests/teamdb-problems-fts.test.sh — Validación FTS5 para known_problems (T-1.4)
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

# Fixture
TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1

# ─── Caso 1: problems_fts existe tras init
HAS_FTS=$(sqlite3 "$DB" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='problems_fts'")
if [ "$HAS_FTS" = "1" ]; then
  assert_pass "problems_fts existe tras teamdb-init"
else
  assert_fail "problems_fts existe tras teamdb-init" "missing"
fi

# ─── Caso 2: trigger de insert existe
HAS_TRIG=$(sqlite3 "$DB" "SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='problems_ai'")
if [ "$HAS_TRIG" = "1" ]; then
  assert_pass "trigger problems_ai existe"
else
  assert_fail "trigger problems_ai existe" "missing"
fi

# ─── Caso 3: insert en known_problems se refleja en problems_fts
sqlite3 "$DB" "INSERT INTO known_problems(slug,title,symptom_md,workaround_md,discovered_at) VALUES('conn','Connection timeout','wait then retry','retry after 30s',datetime('now'))"
MATCH=$(sqlite3 "$DB" "SELECT title FROM known_problems WHERE id IN (SELECT rowid FROM problems_fts WHERE problems_fts MATCH 'timeout')")
if [ "$MATCH" = "Connection timeout" ]; then
  assert_pass "FTS5 match 'timeout' retorna fila"
else
  assert_fail "FTS5 match 'timeout' retorna fila" "match='$MATCH'"
fi

# ─── Caso 4: search via script funciona
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "timeout" problems "$TEST_DIR" 2>/dev/null | grep -c "Connection" || true)
if [ "$RESULT" -ge 1 ]; then
  assert_pass "search.sh encuentra 'timeout' en problems"
else
  assert_fail "search.sh encuentra 'timeout' en problems" "result=$RESULT"
fi

# ─── Caso 5: search por workaround funciona
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "retry" problems "$TEST_DIR" 2>/dev/null | grep -c "Connection" || true)
if [ "$RESULT" -ge 1 ]; then
  assert_pass "search.sh matchea 'retry' (workaround_md) en problems"
else
  assert_fail "search.sh matchea 'retry' (workaround_md) en problems" "result=$RESULT"
fi

# ─── Caso 6: update de known_problems se refleja en problems_fts
sqlite3 "$DB" "UPDATE known_problems SET symptom_md = 'now needs restart' WHERE slug='conn'"
MATCH=$(sqlite3 "$DB" "SELECT title FROM known_problems WHERE id IN (SELECT rowid FROM problems_fts WHERE problems_fts MATCH 'restart')")
if [ "$MATCH" = "Connection timeout" ]; then
  assert_pass "UPDATE en known_problems se refleja en FTS"
else
  assert_fail "UPDATE en known_problems se refleja en FTS" "match='$MATCH'"
fi

# ─── Caso 7: delete de known_problems limpia problems_fts
sqlite3 "$DB" "DELETE FROM known_problems WHERE slug='conn'"
MATCH=$(sqlite3 "$DB" "SELECT title FROM known_problems WHERE id IN (SELECT rowid FROM problems_fts WHERE problems_fts MATCH 'restart')")
if [ -z "$MATCH" ]; then
  assert_pass "DELETE en known_problems limpia FTS"
else
  assert_fail "DELETE en known_problems limpia FTS" "match='$MATCH'"
fi

# ─── Caso 8: SQLi en search problems no rompe
bash "$ROOT/scripts/teamdb-search.sh" "x'); DROP TABLE known_problems; --" problems "$TEST_DIR" >/dev/null 2>&1 || true
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='known_problems'")
if [ "$EXISTS" = "known_problems" ]; then
  assert_pass "SQLi en search problems no destruye tabla"
else
  assert_fail "SQLi en search problems no destruye tabla" "EXISTS=$EXISTS"
fi

rm -rf "$TEST_DIR"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
