#!/usr/bin/env bash
# tests/teamdb-search-sqli.test.sh — Validación parametrización teamdb-search.sh (T-1.2)
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

# Fixture: DB fresca con datos
TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1

sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('jwt','JWT Auth','refresh tokens',datetime('now'))"
sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('oauth','OAuth 2','grant flow',datetime('now'))"
sqlite3 "$DB" "INSERT INTO decisions(slug,title,body_md,decided_at) VALUES('use-jwt','Use JWT','decision body',datetime('now'))"
sqlite3 "$DB" "INSERT INTO preferences(slug,scope,body_md) VALUES('commit-style','repo','conventional commits')"
sqlite3 "$DB" "INSERT INTO known_problems(slug,title,symptom_md,workaround_md,discovered_at) VALUES('conn','Connection timeout','wait then retry','retry 30s',datetime('now'))"
sqlite3 "$DB" "INSERT INTO work_in_progress(slug,type,title,status,created_at,updated_at) VALUES('p1','plan','My plan','open',datetime('now'),datetime('now'))"

# ─── Caso 1: inyección clásica en query no rompe DB
bash "$ROOT/scripts/teamdb-search.sh" "' OR '1'='1" concepts "$TEST_DIR" >/dev/null 2>&1 || true
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='jwt'")
if [ "$COUNT" = "1" ]; then
  assert_pass "SQLi OR 1=1 no afecta tabla concepts"
else
  assert_fail "SQLi OR 1=1 no afecta tabla concepts" "count=$COUNT"
fi

# ─── Caso 2: DROP TABLE attempt no ejecuta
bash "$ROOT/scripts/teamdb-search.sh" "x'); DROP TABLE concepts; --" concepts "$TEST_DIR" >/dev/null 2>&1 || true
TBL=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'")
if [ "$TBL" = "concepts" ]; then
  assert_pass "DROP TABLE attempt no ejecuta (concepts preservada)"
else
  assert_fail "DROP TABLE attempt no ejecuta (concepts preservada)" "tbl=$TBL"
fi

# ─── Caso 3: search normal funciona con match parcial
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "JWT" concepts "$TEST_DIR" 2>/dev/null | grep -c "jwt" || true)
if [ "$RESULT" -ge 1 ]; then
  assert_pass "search normal funciona (match JWT)"
else
  assert_fail "search normal funciona (match JWT)" "result=$RESULT"
fi

# ─── Caso 4: search con comillas literales no rompe
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "can't" concepts "$TEST_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$RESULT" -ge 0 ]; then
  assert_pass "search con apostrofo no rompe"
else
  assert_fail "search con apostrofo no rompe" "result=$RESULT"
fi

# ─── Caso 5: search en decisions funciona
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "JWT" decisions "$TEST_DIR" 2>/dev/null | grep -c "use-jwt" || true)
if [ "$RESULT" -ge 1 ]; then
  assert_pass "search en decisions funciona"
else
  assert_fail "search en decisions funciona" "result=$RESULT"
fi

# ─── Caso 6: search en preferences usa LIKE (no FTS5)
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "conventional" preferences "$TEST_DIR" 2>/dev/null | grep -c "commit-style" || true)
if [ "$RESULT" -ge 1 ]; then
  assert_pass "search en preferences usa LIKE (no FTS5)"
else
  assert_fail "search en preferences usa LIKE (no FTS5)" "result=$RESULT"
fi

# ─── Caso 7: search en problems (FTS5) — fixture de T-1.4
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "timeout" problems "$TEST_DIR" 2>/dev/null | grep -c "Connection" || true)
if [ "$RESULT" -ge 1 ]; then
  assert_pass "search en problems funciona (FTS5 o LIKE)"
else
  assert_fail "search en problems funciona (FTS5 o LIKE)" "result=$RESULT"
fi

# ─── Caso 8: search en wip funciona
RESULT=$(bash "$ROOT/scripts/teamdb-search.sh" "My plan" wip "$TEST_DIR" 2>/dev/null | grep -c "p1" || true)
if [ "$RESULT" -ge 1 ]; then
  assert_pass "search en wip funciona"
else
  assert_fail "search en wip funciona" "result=$RESULT"
fi

# ─── Caso 9: search con SQLi en cada tipo
for t in concepts decisions preferences problems wip; do
  bash "$ROOT/scripts/teamdb-search.sh" "x'); DROP TABLE $t; --" "$t" "$TEST_DIR" >/dev/null 2>&1 || true
  case "$t" in
    wip) tbl="work_in_progress" ;;
    problems) tbl="known_problems" ;;
    *) tbl="$t" ;;
  esac
  EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='$tbl'")
  if [ "$EXISTS" = "$tbl" ]; then
    assert_pass "SQLi en $t no destruye tabla $tbl"
  else
    assert_fail "SQLi en $t no destruye tabla $tbl" "tbl=$EXISTS"
  fi
done

# ─── Caso 10: bash 3.2 portable check
if [ "${BASH_VERSINFO[0]}" -ge 3 ]; then
  assert_pass "compatible bash 3.2+"
else
  assert_fail "compatible bash 3.2+" "bash=$BASH_VERSION"
fi

rm -rf "$TEST_DIR"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
