#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR=$(mktemp -d /tmp/teamdb-git-XXXXXX)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

assert() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  OK $name"; PASS=$((PASS+1))
  else
    echo "  FAIL $name"; FAIL=$((FAIL+1))
  fi
}

cd "$TEST_DIR"
mkdir -p .opencode/context
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null
DB="$TEST_DIR/.opencode/context/team.db"

echo "==> Test 1: DB init"
assert "DB existe" "[ -f '$DB' ]"
ver=$(sqlite3 "$DB" "SELECT value FROM schema_meta WHERE key='version'")
assert "schema 0.7.0" "[ \"$ver\" = '0.7.0' ]"

echo "==> Test 2: Hooks existen"
assert "pre-commit" "[ -f '$SKALLING_ROOT/scripts/hooks/pre-commit' ]"
assert "post-merge" "[ -f '$SKALLING_ROOT/scripts/hooks/post-merge' ]"
assert "global DB" "[ -f '$HOME/.config/opencode/team.db' ]"

echo "==> Test 3: Scripts bash"
assert "lib-teamdb.sh" "[ -f '$SKALLING_ROOT/scripts/lib/lib-teamdb.sh' ]"
assert "wip-tree.sh" "[ -f '$SKALLING_ROOT/scripts/wip-tree.sh' ]"
assert "teamdb-init.sh" "[ -f '$SKALLING_ROOT/scripts/teamdb-init.sh' ]"
assert "teamdb-migrate.sh" "[ -f '$SKALLING_ROOT/scripts/teamdb-migrate.sh' ]"
assert "teamdb-export.sh" "[ -f '$SKALLING_ROOT/scripts/teamdb-export.sh' ]"
assert "teamdb-import.sh" "[ -f '$SKALLING_ROOT/scripts/teamdb-import.sh' ]"

echo "==> Test 4: WIP tree funciona"
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,title,status,owner,created_at,updated_at) VALUES ('p','plan','Test','open','sol',datetime('now'),datetime('now'))"
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,owner,created_at,updated_at) SELECT 'f','feature',id,'Feat','open','teo',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='p'"
out=$(bash "$SKALLING_ROOT/scripts/wip-tree.sh" "$TEST_DIR" 2>/dev/null | grep -c "PLAN: Test" || echo "0")
assert "wip-tree muestra plan" "[ \"$out\" -gt 0 ]"

echo "==> Test 5: Export funciona"
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-export.sh" "$TEST_DIR" >/dev/null
assert "data_concepts.sql" "[ -f '$TEST_DIR/.opencode/context/teamdb/data_concepts.sql' ]"

echo "================================="
echo "RESULTADO: $PASS pass, $FAIL fail"
echo "================================="
[ "$FAIL" -eq 0 ]