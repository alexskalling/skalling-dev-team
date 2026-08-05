#!/usr/bin/env bash
# test-teamdb-safe.sh — Test no destructivo del flujo teamdb
# No toca nada en tu repo real. Trabaja en /tmp/.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKALLING_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR=$(mktemp -d /tmp/teamdb-test-XXXXXX)
BACKUP_DIR=""
PASS=0
FAIL=0

cleanup() {
  if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $name"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name"
    FAIL=$((FAIL+1))
  fi
}

echo "==> Test teamdb en $TEST_DIR"
echo ""

# 1. Crear proyecto
mkdir -p "$TEST_DIR/.opencode/context/concept"
echo "test plan fixture" > "$TEST_DIR/.opencode/context/project_decisions.jsonl"
echo ""

# 2. Poblar .jsonl legacy
cat > "$TEST_DIR/.opencode/context/DECISIONS.jsonl" <<EOF
{"topic":"use-typescript","decision":"TypeScript everywhere","reason":"types"}
{"topic":"test-with-vitest","decision":"Vitest como test runner","reason":"rapido"}
EOF

cat > "$TEST_DIR/.opencode/context/PREFERENCES.jsonl" <<EOF
{"slug":"no-else","scope":"code-style","preference":"early return, no else"}
{"slug":"spanish-comments","scope":"language","preference":"comentarios en español"}
EOF

cat > "$TEST_DIR/.opencode/context/PATTERNS.jsonl" <<EOF
{"name":"repository-pattern","description":"un repository por aggregate root"}
{"name":"value-object","description":"objetos inmutables identificados por valor"}
EOF

# 3. Poblar concept/*.md
cat > "$TEST_DIR/.opencode/context/concept/auth.md" <<EOF
# Auth con JWT

Stateless, refresh cada 15min.

## Por qué
- API-first
- Sin sesiones en memoria
EOF

cat > "$TEST_DIR/.opencode/context/concept/db.md" <<EOF
# PostgreSQL

DB principal del proyecto.

## Config
- Drizzle ORM
- Migraciones en /drizzle/
EOF

# 4. Backup
BACKUP_DIR=$(mktemp -d /tmp/teamdb-backup-XXXXXX)
cp -r "$TEST_DIR/.opencode" "$BACKUP_DIR/"
echo "✓ Backup creado en $BACKUP_DIR"
echo ""

# 5. Correr migrate
echo "==> Migrando legacy..."
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-migrate.sh" "$TEST_DIR"
echo ""

# 6. Verificar
DB="$TEST_DIR/.opencode/context/team.db"
echo "==> Verificando migración..."
assert "DB existe" "[ -f '$DB' ]"
assert "DECISIONS migradas" "sqlite3 '$DB' 'SELECT 1 FROM decisions WHERE slug=\"use-typescript\"'"
assert "DECISIONS 2da" "sqlite3 '$DB' 'SELECT 1 FROM decisions WHERE slug=\"test-with-vitest\"'"
assert "PREFERENCES migradas" "sqlite3 '$DB' 'SELECT 1 FROM preferences WHERE slug=\"no-else\"'"
assert "PATTERNS migradas" "sqlite3 '$DB' 'SELECT 1 FROM concepts WHERE slug=\"repository-pattern\"'"
assert "concept/auth.md migrado" "sqlite3 '$DB' 'SELECT 1 FROM concepts WHERE slug=\"auth\"'"
assert "concept/db.md migrado" "sqlite3 '$DB' 'SELECT 1 FROM concepts WHERE slug=\"db\"'"
assert "Legacy movido" "[ -d '$TEST_DIR/.opencode/context/legacy' ]"
assert "DECISIONS.jsonl no existe" "[ ! -f '$TEST_DIR/.opencode/context/DECISIONS.jsonl' ]"
echo ""

# 7. FTS5
echo "==> Probando FTS5..."
sqlite3 "$DB" "SELECT title FROM concepts WHERE slug='auth'" >/dev/null
hits=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts_fts WHERE concepts_fts MATCH 'JWT OR stateless'")
assert "FTS5 encuentra 'JWT OR stateless'" "[ \"$hits\" -gt 0 ]"
echo ""

# 8. Jerarquía wip
echo "==> Creando jerarquía plan/feature/task..."
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,title,body_md,status,owner,created_at,updated_at) VALUES ('plan1','plan','Test Plan','# objetivo','open','sol',datetime('now'),datetime('now'))"
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,owner,created_at,updated_at) SELECT 'feat1','feature',id,'Test Feature','open','teo',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='plan1'"
sqlite3 "$DB" "INSERT INTO work_in_progress (slug,type,parent_id,title,status,owner,created_at,updated_at) SELECT 'task1','task',id,'Test Task','open','jhon',datetime('now'),datetime('now') FROM work_in_progress WHERE slug='feat1'"

count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM work_in_progress WHERE type='plan'")
assert "1 plan creado" "[ \"$count\" = '1' ]"
count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM work_in_progress WHERE type='feature'")
assert "1 feature creado" "[ \"$count\" = '1' ]"
count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM work_in_progress WHERE type='task'")
assert "1 task creada" "[ \"$count\" = '1' ]"
echo ""

# 9. wip-tree
echo "==> Visualizando jerarquía:"
echo ""
bash "$SKALLING_ROOT/scripts/wip-tree.sh" "$TEST_DIR"
echo ""

# 10. Export
echo "==> Exportando DB..."
SKALLING_ROOT="$SKALLING_ROOT" bash "$SKALLING_ROOT/scripts/teamdb-export.sh" "$TEST_DIR"
assert "data_concepts.sql existe" "[ -f '$TEST_DIR/.opencode/context/teamdb/data_concepts.sql' ]"
assert "data_decisions.sql existe" "[ -f '$TEST_DIR/.opencode/context/teamdb/data_decisions.sql' ]"
assert "data_preferences.sql existe" "[ -f '$TEST_DIR/.opencode/context/teamdb/data_preferences.sql' ]"
assert "data_memory_links.sql existe" "[ -f '$TEST_DIR/.opencode/context/teamdb/data_memory_links.sql' ]"
echo ""

# 11. Audit log
echo "==> Verificando audit log..."
sqlite3 "$DB" "INSERT INTO concepts (slug,title,body_md,updated_at) VALUES ('audit-test','Audit','test',datetime('now'))"
count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE table_name='concepts'")
assert "audit_log captura INSERT" "[ \"$count\" -gt 0 ]"
echo ""

# Resumen
echo "================================="
echo "RESULTADO: $PASS pass, $FAIL fail"
echo "================================="
if [ "$FAIL" -eq 0 ]; then
  echo "✅ TODO OK. Teamdb v0.7.0 funciona end-to-end."
  exit 0
else
  echo "❌ Hay $FAIL fallos. Revisá."
  exit 1
fi
