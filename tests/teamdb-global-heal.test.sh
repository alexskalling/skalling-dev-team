#!/usr/bin/env bash
# tests/teamdb-global-heal.test.sh — Heal aditivo idempotente del team.db global (H2)
# Cubre: install-global.sh sobre DB vieja, teamdb_init_global runtime, idempotencia.
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

# DB global "vieja" (pre-0.7.2: sin audit_log) realista
seed_old_global() {
  mkdir -p "$HOME/.config/opencode"
  sqlite3 "$HOME/.config/opencode/team.db" <<'SQL'
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
INSERT INTO user_preferences VALUES (1, 'viejas-pref', 'test', NULL, 'body', 1.0, 'seed');
CREATE TABLE stack_cache (
  id INTEGER PRIMARY KEY,
  project_path TEXT UNIQUE NOT NULL,
  detected_at TEXT,
  language TEXT,
  framework TEXT,
  test_runner TEXT,
  package_manager TEXT,
  fingerprint TEXT
);
SQL
}

# ── Test 1: install-global.sh cura una DB global vieja ──────────────────────
FAKE_HOME="$(mktemp -d)"
export HOME="$FAKE_HOME"
seed_old_global
bash "$ROOT/install-global.sh" >/dev/null 2>&1
RC=$?
export HOME="$HOME_BAK"

if [ "$RC" -eq 0 ]; then
  assert_pass "install-global.sh con DB global vieja retorna exit 0"
else
  assert_fail "install-global.sh con DB global vieja retorna exit 0" "rc=$RC"
fi

if sqlite3 "$FAKE_HOME/.config/opencode/team.db" "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log'" | grep -q audit_log; then
  assert_pass "install heals: audit_log creada en DB global vieja"
else
  assert_fail "install heals: audit_log creada en DB global vieja"
fi

HAS_COL=$(sqlite3 "$FAKE_HOME/.config/opencode/team.db" "SELECT 1 FROM pragma_table_info('audit_log') WHERE name='actor_source'")
if [ "$HAS_COL" = "1" ]; then
  assert_pass "install heals: audit_log.actor_source presente"
else
  assert_fail "install heals: audit_log.actor_source presente" "col=$HAS_COL"
fi

VER=$(sqlite3 "$FAKE_HOME/.config/opencode/team.db" "SELECT value FROM schema_meta WHERE key='version'")
if [ "$VER" = "0.7.8" ]; then
  assert_pass "install heals: schema_meta.version al día (0.7.8)"
else
  assert_fail "install heals: schema_meta.version al día (0.7.8)" "ver=$VER"
fi

PREFS=$(sqlite3 "$FAKE_HOME/.config/opencode/team.db" "SELECT COUNT(*) FROM user_preferences WHERE slug='viejas-pref'")
if [ "$PREFS" = "1" ]; then
  assert_pass "install heals: datos existentes intactos"
else
  assert_fail "install heals: datos existentes intactos" "count=$PREFS"
fi
rm -rf "$FAKE_HOME"

# ── Test 2: teamdb_init_global (runtime) cura DB vieja y write funciona ────
FAKE_HOME="$(mktemp -d)"
export HOME="$FAKE_HOME"
export SKALLING_ROOT="$ROOT"
seed_old_global
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"
DB_GLOBAL=$(teamdb_init_global)

if [ -f "$DB_GLOBAL" ]; then
  assert_pass "teamdb_init_global retorna DB global"
else
  assert_fail "teamdb_init_global retorna DB global" "db=$DB_GLOBAL"
fi

TEAMDB_ACTOR=teo teamdb_write_global \
  "INSERT INTO user_preferences(slug,scope,body_md) VALUES(?,?,?)" \
  "nueva-pref" "test" "body" >/dev/null 2>&1
RC_WRITE=$?
export HOME="$HOME_BAK"
if [ "$RC_WRITE" = "0" ]; then
  assert_pass "teamdb_write_global funciona tras heal"
else
  assert_fail "teamdb_write_global funciona tras heal" "rc=$RC_WRITE"
fi

AUDIT_ROW=$(sqlite3 "$DB_GLOBAL" "SELECT COUNT(*) FROM audit_log WHERE agent='teo' AND actor_source='helper' AND action='mutate-global'")
if [ "$AUDIT_ROW" = "1" ]; then
  assert_pass "heal: audit row global con actor_source='helper'"
else
  assert_fail "heal: audit row global con actor_source='helper'" "count=$AUDIT_ROW"
fi

# ── Test 3: heal es idempotente (2ª pasada no rompe nada) ──────────────────
export HOME="$FAKE_HOME"
teamdb_heal_global
RC_HEAL2=$?
VER2=$(sqlite3 "$DB_GLOBAL" "SELECT value FROM schema_meta WHERE key='version'")
PREFS2=$(sqlite3 "$DB_GLOBAL" "SELECT COUNT(*) FROM user_preferences")
export HOME="$HOME_BAK"
if [ "$RC_HEAL2" = "0" ] && [ "$VER2" = "0.7.8" ] && [ "$PREFS2" = "2" ]; then
  assert_pass "heal idempotente (2ª pasada sin cambios)"
else
  assert_fail "heal idempotente (2ª pasada sin cambios)" "rc=$RC_HEAL2 ver=$VER2 prefs=$PREFS2"
fi
rm -rf "$FAKE_HOME"

# ── Test 4: DB nueva se crea del schema actual (camino fresco intacto) ─────
FAKE_HOME="$(mktemp -d)"
export HOME="$FAKE_HOME"
export SKALLING_ROOT="$ROOT"
. "$ROOT/scripts/lib/lib-teamdb.sh"
DB_FRESH=$(teamdb_init_global)
export HOME="$HOME_BAK"
HAS_TABLE=$(sqlite3 "$DB_FRESH" "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log'")
HAS_COL2=$(sqlite3 "$DB_FRESH" "SELECT 1 FROM pragma_table_info('audit_log') WHERE name='actor_source'")
VER3=$(sqlite3 "$DB_FRESH" "SELECT value FROM schema_meta WHERE key='version'")
if [ -n "$HAS_TABLE" ] && [ "$HAS_COL2" = "1" ] && [ "$VER3" = "0.7.8" ]; then
  assert_pass "DB global nueva usa schema actual (audit_log + actor_source + 0.7.8)"
else
  assert_fail "DB global nueva usa schema actual" "table=$HAS_TABLE col=$HAS_COL2 ver=$VER3"
fi
rm -rf "$FAKE_HOME"

# ── Test 5: install-global.sh llama teamdb_heal_global ─────────────────────
if grep -q "teamdb_heal_global" "$ROOT/install-global.sh"; then
  assert_pass "install-global.sh usa teamdb_heal_global"
else
  assert_fail "install-global.sh usa teamdb_heal_global"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
