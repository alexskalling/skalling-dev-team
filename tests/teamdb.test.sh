#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "✓ $name"
    PASS=$((PASS+1))
  else
    echo "✗ $name"
    FAIL=$((FAIL+1))
  fi
}

# Test 1
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.opencode/context"
assert "schema project" "sqlite3 '$TEST_DIR/.opencode/context/team.db' < '$SKALLING_ROOT/sql/project-schema.sql'"

# Test 2
assert "concepts" "sqlite3 '$TEST_DIR/.opencode/context/team.db' 'SELECT 1 FROM concepts LIMIT 1'"
assert "decisions" "sqlite3 '$TEST_DIR/.opencode/context/team.db' 'SELECT 1 FROM decisions LIMIT 1'"
assert "wip" "sqlite3 '$TEST_DIR/.opencode/context/team.db' 'SELECT 1 FROM work_in_progress LIMIT 1'"

# Test 3: jerarquía
sqlite3 "$TEST_DIR/.opencode/context/team.db" "INSERT INTO work_in_progress (slug,type,title,status,created_at,updated_at) VALUES ('p1','plan','Plan 1','open',datetime('now'),datetime('now'))"
sqlite3 "$TEST_DIR/.opencode/context/team.db" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,created_at,updated_at) SELECT 'f1','feature',id,'Feature 1','open',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='p1'"
sqlite3 "$TEST_DIR/.opencode/context/team.db" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,created_at,updated_at) SELECT 't1','task',id,'Task 1','open',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='f1'"

count=$(sqlite3 "$TEST_DIR/.opencode/context/team.db" "SELECT COUNT(*) FROM work_in_progress WHERE type='plan'")
assert "1 plan" "[ \"$count\" = '1' ]"

count=$(sqlite3 "$TEST_DIR/.opencode/context/team.db" "SELECT COUNT(*) FROM work_in_progress WHERE type='feature'")
assert "1 feature" "[ \"$count\" = '1' ]"

count=$(sqlite3 "$TEST_DIR/.opencode/context/team.db" "SELECT COUNT(*) FROM work_in_progress WHERE type='task'")
assert "1 task" "[ \"$count\" = '1' ]"

# Test 4: FTS5
sqlite3 "$TEST_DIR/.opencode/context/team.db" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('test','JWT Auth','# JWT works',datetime('now'))"
assert "FTS5 search" "sqlite3 '$TEST_DIR/.opencode/context/team.db' \"SELECT 1 FROM concepts_fts WHERE concepts_fts MATCH 'JWT'\""

# Test 5: scripts ejecutables
assert "wip-tree.sh existe" "[ -x '$SKALLING_ROOT/scripts/wip-tree.sh' ]"
assert "lib-teamdb.sh existe" "[ -x '$SKALLING_ROOT/scripts/lib/lib-teamdb.sh' ]"

# Test 6: schema global
TEST_DIR2=$(mktemp -d)
assert "schema global" "sqlite3 '$TEST_DIR2/team.db' < '$SKALLING_ROOT/sql/global-schema.sql'"
assert "agents_meta" "sqlite3 '$TEST_DIR2/team.db' 'SELECT 1 FROM agents_meta LIMIT 1'"

# Test 7: migrations
mkdir -p "$TEST_DIR/.opencode/context/teamdb"
assert "export" "bash $SKALLING_ROOT/scripts/teamdb-export.sh '$TEST_DIR'"
assert "data_concepts.sql" "[ -f '$TEST_DIR/.opencode/context/teamdb/data_concepts.sql' ]"

# Test 8: versión
assert "version 0.7.0" "sqlite3 '$TEST_DIR/.opencode/context/team.db' \"SELECT value FROM schema_meta WHERE key='version'\" | grep -q '0.7.0'"

rm -rf "$TEST_DIR" "$TEST_DIR2"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
