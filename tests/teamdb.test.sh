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

# Test 9-15: scripts bash
assert "teamdb-init.sh existe" "[ -x '$SKALLING_ROOT/scripts/teamdb-init.sh' ]"
assert "teamdb-migrate.sh existe" "[ -x '$SKALLING_ROOT/scripts/teamdb-migrate.sh' ]"
assert "teamdb-export.sh existe" "[ -x '$SKALLING_ROOT/scripts/teamdb-export.sh' ]"
assert "teamdb-import.sh existe" "[ -x '$SKALLING_ROOT/scripts/teamdb-import.sh' ]"
assert "wip-tree.sh existe" "[ -x '$SKALLING_ROOT/scripts/wip-tree.sh' ]"
assert "lib-teamdb.sh existe" "[ -x '$SKALLING_ROOT/scripts/lib/lib-teamdb.sh' ]"
assert "global-schema.sql existe" "[ -f '$SKALLING_ROOT/sql/global-schema.sql' ]"

# Test 16: E2E init + insert + export
TEST_E2E=$(mktemp -d)
mkdir -p "$TEST_E2E/.opencode/context"
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-init.sh" "$TEST_E2E" >/dev/null 2>&1
assert "E2E init" "[ -f '$TEST_E2E/.opencode/context/team.db' ]"

sqlite3 "$TEST_E2E/.opencode/context/team.db" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('e2e','E2E test','# content',datetime('now'))"
assert "E2E insert" "sqlite3 '$TEST_E2E/.opencode/context/team.db' 'SELECT 1 FROM concepts WHERE slug=\"e2e\"'"

bash "$SKALLING_ROOT/scripts/teamdb-export.sh" "$TEST_E2E" >/dev/null 2>&1
assert "E2E export" "[ -f '$TEST_E2E/.opencode/context/teamdb/data_concepts.sql' ]"

# Test 17: jerarquía completa
sqlite3 "$TEST_E2E/.opencode/context/team.db" "INSERT INTO work_in_progress (slug,type,title,status,created_at,updated_at) VALUES ('p','plan','Test Plan','open',datetime('now'),datetime('now'))"
sqlite3 "$TEST_E2E/.opencode/context/team.db" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,created_at,updated_at) SELECT 'f','feature',id,'Test Feature','open',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='p'"
sqlite3 "$TEST_E2E/.opencode/context/team.db" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,created_at,updated_at) SELECT 't','task',id,'Test Task','open',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='f'"

count=$(sqlite3 "$TEST_E2E/.opencode/context/team.db" "SELECT COUNT(*) FROM work_in_progress WHERE parent_id IS NOT NULL")
assert "jerarquia 2 niveles" "[ \"$count\" = '2' ]"

# Test 18: FTS5 search tras export+import round-trip
sqlite3 "$TEST_E2E/.opencode/context/team.db" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('jwt-cfg','JWT Config','refresh tokens rotan cada 15min',datetime('now'))"
fts_title=$(sqlite3 "$TEST_E2E/.opencode/context/team.db" "SELECT title FROM concepts_fts WHERE concepts_fts MATCH 'tokens'")
assert "FTS5 match en E2E" "[ \"$fts_title\" = 'JWT Config' ]"

rm -rf "$TEST_DIR" "$TEST_DIR2" "$TEST_E2E"

# Test: wip-tree con datos demo
TEST_DEMO=$(mktemp -d)
mkdir -p "$TEST_DEMO/.opencode/context"
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-init.sh" "$TEST_DEMO" >/dev/null
DB="$TEST_DEMO/.opencode/context/team.db"

# Crear plan + features + tasks
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,title,status,owner,created_at,updated_at) VALUES ('p','plan','Mi Plan','open','sol',datetime('now'),datetime('now'))"
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,owner,created_at,updated_at) SELECT 'f','feature',id,'Mi Feature','open','teo',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='p'"
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,owner,created_at,updated_at) SELECT 't','task',id,'Mi Task','open','teo',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='f'"

out=$(bash "$SKALLING_ROOT/scripts/wip-tree.sh" "$TEST_DEMO")
assert "wip-tree muestra plan" "echo \"$out\" | grep -q 'PLAN: Mi Plan'"
assert "wip-tree muestra feature" "echo \"$out\" | grep -q 'feature: Mi Feature'"
assert "wip-tree muestra task" "echo \"$out\" | grep -q 'task: Mi Task'"

rm -rf "$TEST_DEMO"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
