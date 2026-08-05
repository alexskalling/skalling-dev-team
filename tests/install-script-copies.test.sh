#!/usr/bin/env bash
# tests/install-script-copies.test.sh — Validación de install-global --dry-run (T-1.5)
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

# HOME aislado
FAKE_HOME="$(mktemp -d)"
export HOME="$FAKE_HOME"
mkdir -p "$HOME/.config"

OUT="$(bash "$ROOT/install-global.sh" --dry-run 2>&1)"
RC=$?
export HOME="$HOME_BAK"

if [ "$RC" -eq 0 ]; then
  assert_pass "install-global --dry-run retorna exit 0"
else
  assert_fail "install-global --dry-run retorna exit 0" "rc=$RC out=$OUT"
fi

# Debe mencionar CADA script teamdb-* del repo
for s in teamdb-init teamdb-migrate teamdb-export teamdb-import \
         teamdb-search teamdb-related teamdb-graph \
         teamdb-plan teamdb-status teamdb-amend teamdb-resume \
         teamdb-execute-plan wip-tree; do
  if echo "$OUT" | grep -q "$s.sh"; then
    assert_pass "dry-run menciona $s.sh"
  else
    assert_fail "dry-run menciona $s.sh" "no aparece"
  fi
done

# Debe mencionar lib-teamdb.sh
if echo "$OUT" | grep -q "lib-teamdb.sh"; then
  assert_pass "dry-run menciona lib-teamdb.sh"
else
  assert_fail "dry-run menciona lib-teamdb.sh" "no aparece"
fi

# Debe mencionar teamdb_exec.py (motor de writes con bound params)
if echo "$OUT" | grep -q "teamdb_exec.py"; then
  assert_pass "dry-run menciona teamdb_exec.py"
else
  assert_fail "dry-run menciona teamdb_exec.py" "no aparece"
fi

# El bundle instalado debe poder ESCRIBIR (teamdb_exec.py presente + heal global)
mkdir -p "$FAKE_HOME/.config/opencode"
sqlite3 "$FAKE_HOME/.config/opencode/team.db" <<'SQL'
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version', '0.7.1');
INSERT INTO schema_meta VALUES ('type', 'global');
CREATE TABLE user_preferences (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  scope TEXT NOT NULL,
  scope_value TEXT,
  body_md TEXT,
  confidence REAL DEFAULT 1.0,
  source TEXT
);
SQL
export HOME="$FAKE_HOME"
bash "$ROOT/install-global.sh" >/dev/null 2>&1
if [ -f "$FAKE_HOME/.config/opencode/scripts/teamdb_exec.py" ]; then
  assert_pass "install copia teamdb_exec.py"
else
  assert_fail "install copia teamdb_exec.py"
fi
WRITE_RC=1
TEAMDB_ACTOR=ci bash -c '
  . "$1/scripts/lib-teamdb.sh"
  teamdb_init_global >/dev/null
  teamdb_write_global \
    "INSERT INTO user_preferences(slug,scope,body_md) VALUES(?,?,?)" \
    "installed-write" "test" "body" >/dev/null 2>&1
' _ "$FAKE_HOME/.config/opencode"
WRITE_RC=$?
export HOME="$HOME_BAK"
if [ "$WRITE_RC" = "0" ]; then
  assert_pass "bundle instalado escribe via teamdb_write_global"
else
  assert_fail "bundle instalado escribe via teamdb_write_global" "rc=$WRITE_RC"
fi

# La ruta canónica sql/ debe estar instalada (schemas + migrations) — layout scripts.
if [ -f "$FAKE_HOME/.config/opencode/sql/project-schema.sql" ] \
   && grep -q "actor_source" "$FAKE_HOME/.config/opencode/sql/project-schema.sql"; then
  assert_pass "sql/project-schema.sql instalado con actor_source"
else
  assert_fail "sql/project-schema.sql instalado con actor_source"
fi
if [ -f "$FAKE_HOME/.config/opencode/sql/global-schema.sql" ] \
   && grep -q "actor_source" "$FAKE_HOME/.config/opencode/sql/global-schema.sql"; then
  assert_pass "sql/global-schema.sql instalado con actor_source"
else
  assert_fail "sql/global-schema.sql instalado con actor_source"
fi
if [ -f "$FAKE_HOME/.config/opencode/sql/migrations/004_add_actor_source.sql" ]; then
  assert_pass "sql/migrations/004_add_actor_source.sql instalado"
else
  assert_fail "sql/migrations/004_add_actor_source.sql instalado"
fi

# Un proyecto inicializado desde el bundle instalado funciona end-to-end
export HOME="$FAKE_HOME"
PROJ="$FAKE_HOME/proj"
mkdir -p "$PROJ"
bash "$FAKE_HOME/.config/opencode/scripts/teamdb-init.sh" "$PROJ" >/dev/null 2>&1
RC_INIT=$?
export HOME="$HOME_BAK"
PROJ_DB="$PROJ/.opencode/context/team.db"
if [ "$RC_INIT" = "0" ]; then
  assert_pass "teamdb-init.sh instalado inicializa proyecto (exit 0)"
else
  assert_fail "teamdb-init.sh instalado inicializa proyecto (exit 0)" "rc=$RC_INIT"
fi
if [ -f "$PROJ_DB" ]; then
  assert_pass "DB de proyecto creada por bundle instalado"
else
  assert_fail "DB de proyecto creada por bundle instalado"
fi
VER_PROJ=$(sqlite3 "$PROJ_DB" "SELECT value FROM schema_meta WHERE key='version'")
HAS_ACTOR=$(sqlite3 "$PROJ_DB" "SELECT count(*) FROM pragma_table_info('audit_log') WHERE name='actor_source'")
HAS_HISTORY=$(sqlite3 "$PROJ_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='plan_history'")
if [ "$VER_PROJ" = "0.7.2" ] && [ "$HAS_ACTOR" = "1" ] && [ -n "$HAS_HISTORY" ]; then
  assert_pass "proyecto instalado: version 0.7.2 + actor_source + migraciones 003"
else
  assert_fail "proyecto instalado: version 0.7.2 + actor_source + migraciones 003" \
    "ver=$VER_PROJ actor=$HAS_ACTOR history=$HAS_HISTORY"
fi

# Hooks instalados de verdad (end-to-end, no solo dry-run)
export HOME="$FAKE_HOME"
bash "$ROOT/install-global.sh" >/dev/null 2>&1
export HOME="$HOME_BAK"
INST_HOOKS="$FAKE_HOME/.config/opencode/hooks"
if [ -x "$INST_HOOKS/pre-commit" ] && [ -x "$INST_HOOKS/post-merge" ]; then
  assert_pass "hooks instalados en \$OPENCODE_DIR/hooks y ejecutables"
else
  assert_fail "hooks instalados en \$OPENCODE_DIR/hooks y ejecutables" "ls: $(ls "$INST_HOOKS" 2>/dev/null)"
fi

# skalling-init.md debe resolver $SK_ROOT (no $(dirname "$SKALLING_ROOT")) y buscar hooks en $SK_ROOT/hooks
if grep -q '\$(dirname "\$SKALLING_ROOT")' "$ROOT/command/skalling-init.md"; then
  assert_fail "skalling-init.md sin referencias \$(dirname \$SKALLING_ROOT)"
else
  assert_pass "skalling-init.md sin referencias \$(dirname \$SKALLING_ROOT)"
fi
if grep -q 'HOOKS_SRC="\$SK_ROOT/hooks"' "$ROOT/command/skalling-init.md"; then
  assert_pass "skalling-init.md busca hooks en \$SK_ROOT/hooks (ruta del installer)"
else
  assert_fail "skalling-init.md busca hooks en \$SK_ROOT/hooks (ruta del installer)"
fi
if grep -q '\$SK_ROOT/scripts/teamdb-init.sh' "$ROOT/command/skalling-init.md"; then
  assert_pass "skalling-init.md usa \$SK_ROOT/scripts/teamdb-init.sh"
else
  assert_fail "skalling-init.md usa \$SK_ROOT/scripts/teamdb-init.sh"
fi

# Verificar que NO hay `|| true` silenciador cerca de hooks
if grep -nE "hooks/.*2>/dev/null \|\| true" "$ROOT/install-global.sh" >/dev/null 2>&1; then
  assert_fail "NO hay || true silenciador en sección hooks"
else
  assert_pass "NO hay || true silenciador en sección hooks"
fi

# Verificar que install_teamdb_hooks hace chmod +x sobre los hooks copiados
if grep -nE 'chmod \+x[[:space:]]+"\$\{?hook' "$ROOT/install-global.sh" >/dev/null 2>&1 \
   || grep -nE "chmod \\+x[[:space:]]+\"\\\$hook" "$ROOT/install-global.sh" >/dev/null 2>&1; then
  assert_pass "install_teamdb_hooks hace chmod +x sobre hooks"
else
  assert_fail "install_teamdb_hooks hace chmod +x sobre hooks" "no aparece"
fi

# Verificar que los hooks actuales NO usan SCRIPT_DIR/.. (paths fragiles) — T-1.6 lo arregla.
# Skipped: este assert es de T-1.6, no T-1.5.

rm -rf "$FAKE_HOME"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
