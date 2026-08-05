#!/usr/bin/env bash
# tests/teamdb-related-sqli.test.sh — Validación parametrización teamdb-related.sh (T-1.3)
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

# Captura output + exit code de un comando. Globales: _CAP_OUT, _CAP_RC.
run_capture() {
  local rc=0
  _CAP_OUT="$(eval "$@" 2>&1)" || rc=$?
  _CAP_RC="$rc"
}

# Fixture: DB fresca con datos
TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1

sqlite3 "$DB" "INSERT INTO concepts(slug,title,body_md,updated_at) VALUES('jwt','JWT Auth','refresh tokens',datetime('now'))"
sqlite3 "$DB" "INSERT INTO decisions(slug,title,body_md,decided_at) VALUES('use-jwt','Use JWT','decision body',datetime('now'))"
sqlite3 "$DB" "INSERT INTO preferences(slug,scope,body_md) VALUES('commit-style','repo','conventional commits')"
sqlite3 "$DB" "INSERT INTO known_problems(slug,title,symptom_md,workaround_md,discovered_at) VALUES('conn','Connection timeout','wait','retry 30s',datetime('now'))"
sqlite3 "$DB" "INSERT INTO tags(name) VALUES('security')"
sqlite3 "$DB" "INSERT INTO memory_tags(memory_table,memory_id,tag_id) SELECT 'concepts', id, (SELECT id FROM tags WHERE name='security') FROM concepts WHERE slug='jwt'"
sqlite3 "$DB" "INSERT INTO memory_links(from_table,from_id,to_table,to_id,link_type) SELECT 'concepts', c1.id, 'concepts', c2.id, 'uses' FROM concepts c1, concepts c2 WHERE c1.slug='jwt' AND c2.slug='jwt'"

# ─── Caso 1: TYPE inválido se rechaza
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "jwt" "concept'"'"'; DROP TABLE memory_links; --" "$TEST_DIR" 2>&1'
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='memory_links'")
if [ "$_CAP_RC" != "0" ] && [ "$EXISTS" = "memory_links" ]; then
  assert_pass "type inválido rechazado (no ejecuta SQLi)"
else
  assert_fail "type inválido rechazado (no ejecuta SQLi)" "rc=$_CAP_RC EXISTS=$EXISTS out=$_CAP_OUT"
fi

# ─── Caso 2: SLUG con SQLi en concept no destruye
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "evil'"'"'; DROP TABLE concepts; --" concept "$TEST_DIR" 2>&1'
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='concepts'")
if [ "$EXISTS" = "concepts" ]; then
  assert_pass "SQLi en slug (concept) no destruye tabla concepts"
else
  assert_fail "SQLi en slug (concept) no destruye tabla concepts" "EXISTS=$EXISTS"
fi

# ─── Caso 3: SLUG con SQLi en decision no destruye
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "evil'"'"'; DROP TABLE decisions; --" decision "$TEST_DIR" 2>&1'
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='decisions'")
if [ "$EXISTS" = "decisions" ]; then
  assert_pass "SQLi en slug (decision) no destruye tabla decisions"
else
  assert_fail "SQLi en slug (decision) no destruye tabla decisions" "EXISTS=$EXISTS"
fi

# ─── Caso 4: SQLi en preference
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "evil'"'"'; DROP TABLE preferences; --" preference "$TEST_DIR" 2>&1'
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='preferences'")
if [ "$EXISTS" = "preferences" ]; then
  assert_pass "SQLi en slug (preference) no destruye tabla preferences"
else
  assert_fail "SQLi en slug (preference) no destruye tabla preferences" "EXISTS=$EXISTS"
fi

# ─── Caso 5: SQLi en problem
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "evil'"'"'; DROP TABLE known_problems; --" problem "$TEST_DIR" 2>&1'
EXISTS=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='known_problems'")
if [ "$EXISTS" = "known_problems" ]; then
  assert_pass "SQLi en slug (problem) no destruye tabla known_problems"
else
  assert_fail "SQLi en slug (problem) no destruye tabla known_problems" "EXISTS=$EXISTS"
fi

# ─── Caso 6: caso válido funciona
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "jwt" concept "$TEST_DIR" 2>&1'
if [ "$_CAP_RC" = "0" ]; then
  assert_pass "caso válido (jwt concept) retorna exit 0"
else
  assert_fail "caso válido (jwt concept) retorna exit 0" "rc=$_CAP_RC out=$_CAP_OUT"
fi

# ─── Caso 7: muestra tags
if echo "$_CAP_OUT" | grep -q "security"; then
  assert_pass "muestra tags del concept"
else
  assert_fail "muestra tags del concept" "no aparece 'security'"
fi

# ─── Caso 8: muestra links out
if echo "$_CAP_OUT" | grep -qE "uses|jwt"; then
  assert_pass "muestra links out del concept"
else
  assert_fail "muestra links out del concept" "no aparece 'uses'"
fi

# ─── Caso 9: type desconocido (no en whitelist) falla
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "jwt" "unknown_type" "$TEST_DIR" 2>&1'
if [ "$_CAP_RC" != "0" ]; then
  assert_pass "type desconocido falla con exit != 0"
else
  assert_fail "type desconocido falla con exit != 0" "rc=$_CAP_RC"
fi

# ─── Caso 10: slug inexistente falla
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "no-existe" concept "$TEST_DIR" 2>&1'
if [ "$_CAP_RC" != "0" ]; then
  assert_pass "slug inexistente falla con exit != 0"
else
  assert_fail "slug inexistente falla con exit != 0" "rc=$_CAP_RC"
fi

# ─── Caso 11: decision válido
run_capture 'bash "$ROOT/scripts/teamdb-related.sh" "use-jwt" decision "$TEST_DIR" 2>&1'
if [ "$_CAP_RC" = "0" ]; then
  assert_pass "caso válido (use-jwt decision) retorna exit 0"
else
  assert_fail "caso válido (use-jwt decision) retorna exit 0" "rc=$_CAP_RC"
fi

rm -rf "$TEST_DIR"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
