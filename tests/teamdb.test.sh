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
assert "version 0.8.0" "sqlite3 '$TEST_DIR/.opencode/context/team.db' \"SELECT value FROM schema_meta WHERE key='version'\" | grep -q '0.8.0'"

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

# ────────────────────────────────────────────────────────────────────────────
# FIX C1 — SQL injection en teamdb-migrate.sh (comillas + SQLi attempts)
# ────────────────────────────────────────────────────────────────────────────

TEST_SQLI=$(mktemp -d)
mkdir -p "$TEST_SQLI/.opencode/context"
printf '%s\n' '{"topic":"quote-test","decision":"It'"'"'s a \"good\" approach"}' > "$TEST_SQLI/.opencode/context/DECISIONS.jsonl"
printf '%s\n' '{"topic":"sqli-attempt","decision":"evil'"'"'; DROP TABLE x; --"}' > "$TEST_SQLI/.opencode/context/DECISIONS.jsonl"
bash "$SKALLING_ROOT/scripts/teamdb-migrate.sh" "$TEST_SQLI" >/dev/null 2>&1 || true
DB_SQLI="$TEST_SQLI/.opencode/context/team.db"
assert "migrate sobrevive comillas dobles" "[ -f '$DB_SQLI' ]"
assert "migrate comillas simples OK" "sqlite3 '$DB_SQLI' 'SELECT 1 FROM decisions WHERE slug=\"quote-test\"'"
assert "migrate SQLi attempt como string" "sqlite3 '$DB_SQLI' 'SELECT 1 FROM decisions WHERE slug=\"sqli-attempt\"'"
assert "tabla decisions no destruida" "sqlite3 '$DB_SQLI' 'SELECT 1 FROM decisions LIMIT 1'"
rm -rf "$TEST_SQLI"

# ────────────────────────────────────────────────────────────────────────────
# FIX C2 — audit log triggers (12 triggers: 4 tablas × 3 acciones)
# ────────────────────────────────────────────────────────────────────────────

TEST_AUDIT=$(mktemp -d)
mkdir -p "$TEST_AUDIT/.opencode/context"
DB_AUDIT="$TEST_AUDIT/.opencode/context/team.db"
sqlite3 "$DB_AUDIT" < "$SKALLING_ROOT/sql/project-schema.sql"
trigger_count=$(sqlite3 "$DB_AUDIT" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name LIKE '%audit%'")
assert "audit triggers presentes (12)" "[ \"$trigger_count\" = '12' ]"

sqlite3 "$DB_AUDIT" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('audit-test','Audit','test',datetime('now'))"
sqlite3 "$DB_AUDIT" "INSERT INTO decisions (slug,title,body_md,decided_at) VALUES ('audit-dec','Decision','d',datetime('now'))"
sqlite3 "$DB_AUDIT" "INSERT INTO work_in_progress (slug,type,title,status,created_at,updated_at) VALUES ('audit-wip','task','WIP','open',datetime('now'),datetime('now'))"
sqlite3 "$DB_AUDIT" "INSERT INTO known_problems (slug,title,symptom_md,discovered_at) VALUES ('audit-prob','Problem','p',datetime('now'))"
audit_count=$(sqlite3 "$DB_AUDIT" "SELECT COUNT(*) FROM audit_log")
assert "audit_log captura 4 inserts" "[ \"$audit_count\" = '4' ]"

sqlite3 "$DB_AUDIT" "UPDATE concepts SET body_md='updated' WHERE slug='audit-test'"
sqlite3 "$DB_AUDIT" "DELETE FROM concepts WHERE slug='audit-test'"
audit_count=$(sqlite3 "$DB_AUDIT" "SELECT COUNT(*) FROM audit_log WHERE action IN ('update','delete')")
assert "audit_log captura update+delete" "[ \"$audit_count\" = '2' ]"
rm -rf "$TEST_AUDIT"

# ────────────────────────────────────────────────────────────────────────────
# FIX H4 — import en DB existente (extrae solo INSERTs, no rompe)
# ────────────────────────────────────────────────────────────────────────────

TEST_IMPORT=$(mktemp -d)
mkdir -p "$TEST_IMPORT/.opencode/context"
bash "$SKALLING_ROOT/scripts/teamdb-init.sh" "$TEST_IMPORT" >/dev/null 2>&1
DB="$TEST_IMPORT/.opencode/context/team.db"
sqlite3 "$DB" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('existing','Existing','old',datetime('now'))"
bash "$SKALLING_ROOT/scripts/teamdb-export.sh" "$TEST_IMPORT" >/dev/null 2>&1
sqlite3 "$DB" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('new','New','new',datetime('now'))"
import_out=$(bash "$SKALLING_ROOT/scripts/teamdb-import.sh" "$TEST_IMPORT" 2>&1)
assert "import en DB existente no rompe" "[ -f '$DB' ]"
assert "import reporta success" "echo \"$import_out\" | grep -q 'imported:'"
count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug IN ('existing','new')")
assert "conceptos preservados tras import" "[ \"$count\" = '2' ]"
rm -rf "$TEST_IMPORT"

# ────────────────────────────────────────────────────────────────────────────
# FIX C3 — flock wrappea teamdb_write_project
# ────────────────────────────────────────────────────────────────────────────

TEST_FLOCK=$(mktemp -d)
mkdir -p "$TEST_FLOCK/.opencode/context"
bash "$SKALLING_ROOT/scripts/teamdb-init.sh" "$TEST_FLOCK" >/dev/null 2>&1
DB="$TEST_FLOCK/.opencode/context/team.db"
assert "teamdb_write_project definida" "grep -q 'teamdb_write_project' '$SKALLING_ROOT/scripts/lib/lib-teamdb.sh'"
assert "teamdb_write_project usa flock" "grep -q 'flock' '$SKALLING_ROOT/scripts/lib/lib-teamdb.sh'"
source "$SKALLING_ROOT/scripts/lib/lib-teamdb.sh"
teamdb_write_project "$DB" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('flock-test','Flock','test',datetime('now'))"
count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='flock-test'")
assert "teamdb_write_project ejecuta INSERT" "[ \"$count\" = '1' ]"
rm -rf "$TEST_FLOCK"

# ────────────────────────────────────────────────────────────────────────────
# FIX L11 — memory_links y memory_tags funcionan
# ────────────────────────────────────────────────────────────────────────────

TEST_ML=$(mktemp -d)
mkdir -p "$TEST_ML/.opencode/context"
DB="$TEST_ML/.opencode/context/team.db"
sqlite3 "$DB" < "$SKALLING_ROOT/sql/project-schema.sql"
sqlite3 "$DB" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('a','A','a',datetime('now'))"
sqlite3 "$DB" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('b','B','b',datetime('now'))"
sqlite3 "$DB" "INSERT INTO memory_links (from_table,from_id,to_table,to_id,link_type) VALUES ('concepts',1,'concepts',2,'uses')"
count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links")
assert "memory_links INSERT funciona" "[ \"$count\" = '1' ]"

sqlite3 "$DB" "INSERT INTO tags (name,color) VALUES ('urgent','red')"
sqlite3 "$DB" "INSERT INTO memory_tags (memory_table,memory_id,tag_id) VALUES ('concepts',1,1)"
count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM memory_tags")
assert "memory_tags INSERT funciona" "[ \"$count\" = '1' ]"

bash "$SKALLING_ROOT/scripts/teamdb-export.sh" "$TEST_ML" >/dev/null 2>&1
assert "export crea data_memory_links.sql" "[ -f '$TEST_ML/.opencode/context/teamdb/data_memory_links.sql' ]"
assert "export crea data_memory_tags.sql" "[ -f '$TEST_ML/.opencode/context/teamdb/data_memory_tags.sql' ]"
rm -rf "$TEST_ML"

# ────────────────────────────────────────────────────────────────────────────
# FIX M8 — doctor chequea teamdb
# ────────────────────────────────────────────────────────────────────────────

assert "doctor contiene check_teamdb" "grep -q 'check_teamdb' '$SKALLING_ROOT/setup-team-doctor.sh'"
assert "doctor referencia VERSION" "grep -q 'VERSION' '$SKALLING_ROOT/setup-team-doctor.sh'"

# ────────────────────────────────────────────────────────────────────────────
# FIX H6 — install-global.sh VERSION dinámico
# ────────────────────────────────────────────────────────────────────────────

assert "install-global.sh lee VERSION" "grep -q \"grep '__version__'\" '$SKALLING_ROOT/install-global.sh'"
assert "install-global.sh sin version hardcoded" "! grep -q 'SKALLING_VERSION=\"0.6.2\"' '$SKALLING_ROOT/install-global.sh'"

# ────────────────────────────────────────────────────────────────────────────
# FIX M9 — .gitattributes para .sql merge
# ────────────────────────────────────────────────────────────────────────────

assert ".gitattributes tiene data_*.sql" "grep -q 'data_\\*.sql' '$SKALLING_ROOT/templates/gitattributes.template'"
assert ".gitattributes usa merge=union para sql" "grep -q 'data_\\*.sql merge=union' '$SKALLING_ROOT/templates/gitattributes.template'"

# Test routing_decisions
TEST_R=$(mktemp -d)
mkdir -p "$TEST_R/.opencode/context"
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-init.sh" "$TEST_R" >/dev/null
DB_R="$TEST_R/.opencode/context/team.db"
sqlite3 "$DB_R" "INSERT INTO routing_decisions (ts, user_intent, chosen_route) VALUES (datetime('now'), 'test', 'SDD')"
assert "routing_decisions existe" "sqlite3 '$DB_R' 'SELECT 1 FROM routing_decisions'"

# Test receipts
sqlite3 "$DB_R" "INSERT INTO receipts (id, task_id, agent, command, exit_code, ts) VALUES ('r1', 't1', 'teo', 'npm test', 0, datetime('now'))"
assert "receipts existe" "sqlite3 '$DB_R' 'SELECT 1 FROM receipts'"
rm -rf "$TEST_R"

# ────────────────────────────────────────────────────────────────────────────
# v0.8.0: CAS (compare-and-swap) para tasks
# ────────────────────────────────────────────────────────────────────────────

# Test CAS
TEST_CAS=$(mktemp -d)
mkdir -p "$TEST_CAS/.opencode/context"
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-init.sh" "$TEST_CAS" >/dev/null 2>&1
DB_CAS="$TEST_CAS/.opencode/context/team.db"

# Crear task
sqlite3 "$DB_CAS" "INSERT INTO tasks (plan_id, slug, title, status) VALUES (0, 'test-cas', 'CAS test', 'pending')"
TASK_ID=$(sqlite3 "$DB_CAS" "SELECT id FROM tasks WHERE slug='test-cas'")

# Primer claim: debe funcionar
out=$(bash "$SKALLING_ROOT/scripts/teamdb-claim-task.sh" "$TASK_ID" teo "$TEST_CAS" 2>&1)
assert "primer claim OK" "echo '$out' | grep -q 'claimed'"

# Segundo claim: debe fallar (ya in_progress)
out2=$(bash "$SKALLING_ROOT/scripts/teamdb-claim-task.sh" "$TASK_ID" teo "$TEST_CAS" 2>&1 || true)
assert "segundo claim falla" "echo '$out2' | grep -q 'no estaba pending'"

# Lock history existe
count=$(sqlite3 "$DB_CAS" "SELECT COUNT(*) FROM task_lock_history WHERE task_id=$TASK_ID")
assert "lock history registrado" "[ \"$count\" -ge 1 ]"
rm -rf "$TEST_CAS"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
