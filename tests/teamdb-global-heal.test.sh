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

for operational_table in routing_decisions workflow_metrics workflow_state; do
  if sqlite3 "$FAKE_HOME/.config/opencode/team.db" "SELECT name FROM sqlite_master WHERE type='table' AND name='$operational_table'" | grep -q "$operational_table"; then
    assert_pass "install heals: $operational_table disponible"
  else
    assert_fail "install heals: $operational_table disponible"
  fi
done

VER=$(sqlite3 "$FAKE_HOME/.config/opencode/team.db" "SELECT value FROM schema_meta WHERE key='version'")
EXPECTED_VER="$(grep -E '^__version__' "$ROOT/VERSION" | sed -E 's/.*"([^"]+)".*/\1/')"
if [ "$VER" = "$EXPECTED_VER" ]; then
  assert_pass "install heals: schema_meta.version al día ($EXPECTED_VER)"
else
  assert_fail "install heals: schema_meta.version al día ($EXPECTED_VER)" "ver=$VER"
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
if [ "$RC_HEAL2" = "0" ] && [ "$VER2" = "$EXPECTED_VER" ] && [ "$PREFS2" = "2" ]; then
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
if [ -n "$HAS_TABLE" ] && [ "$HAS_COL2" = "1" ] && [ "$VER3" = "$EXPECTED_VER" ]; then
  assert_pass "DB global nueva usa schema actual (audit_log + actor_source + $EXPECTED_VER)"
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

# ── Test 6: heal rebuilda routing_decisions si el CHECK viejo no tiene DISCOVERY ──
# Bug real (2026-09-13): CREATE TABLE IF NOT EXISTS es no-op sobre una tabla que
# ya existe, aunque su CHECK sea el viejo. Una DB global creada antes de que
# 'DISCOVERY' se agregara al contrato de routing quedaba con el CHECK viejo para
# siempre, pese a reinstalar -- rompia con IntegrityError al primer routing en
# modo DISCOVERY. Mismo rebuild que ya usa 024_version_0_10_3.sql para proyecto.
FAKE_HOME="$(mktemp -d)"
export HOME="$FAKE_HOME"
export SKALLING_ROOT="$ROOT"
mkdir -p "$FAKE_HOME/.config/opencode"
sqlite3 "$FAKE_HOME/.config/opencode/team.db" <<'SQL'
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version', '0.10.2');
INSERT INTO schema_meta VALUES ('type', 'global');
CREATE TABLE routing_decisions (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  user_intent TEXT NOT NULL,
  chosen_route TEXT NOT NULL CHECK (chosen_route IN ('INLINE','INTERVENTION','FAST-TRACK','SDD','DIRECT','RESEARCH')),
  route_reason TEXT,
  agents_involved TEXT,
  outcome TEXT DEFAULT 'PENDING' CHECK (outcome IN ('PENDING','SUCCESS','FAIL','CANCELLED')),
  completed_at TEXT
);
INSERT INTO routing_decisions (ts, user_intent, chosen_route) VALUES ('2026-01-01', 'vieja-decision', 'INLINE');
SQL
. "$ROOT/scripts/lib/lib-teamdb.sh"
DB_OLD_ROUTING="$(teamdb_init_global)"
export HOME="$HOME_BAK"

if sqlite3 "$DB_OLD_ROUTING" "SELECT sql FROM sqlite_master WHERE type='table' AND name='routing_decisions'" | grep -q DISCOVERY; then
  assert_pass "heal rebuilda routing_decisions: CHECK ahora incluye DISCOVERY"
else
  assert_fail "heal rebuilda routing_decisions: CHECK ahora incluye DISCOVERY"
fi

RC_DISCOVERY=0
sqlite3 "$DB_OLD_ROUTING" "INSERT INTO routing_decisions (ts, user_intent, chosen_route) VALUES (datetime('now'), 'prueba-discovery', 'DISCOVERY')" 2>/dev/null || RC_DISCOVERY=$?
if [ "$RC_DISCOVERY" = "0" ]; then
  assert_pass "heal rebuilda routing_decisions: insert con chosen_route=DISCOVERY funciona"
else
  assert_fail "heal rebuilda routing_decisions: insert con chosen_route=DISCOVERY funciona" "rc=$RC_DISCOVERY"
fi

OLD_ROW="$(sqlite3 "$DB_OLD_ROUTING" "SELECT COUNT(*) FROM routing_decisions WHERE user_intent='vieja-decision' AND chosen_route='INLINE'")"
if [ "$OLD_ROW" = "1" ]; then
  assert_pass "heal rebuilda routing_decisions: fila previa (INLINE) sobrevive intacta"
else
  assert_fail "heal rebuilda routing_decisions: fila previa sobrevive intacta" "count=$OLD_ROW"
fi

export HOME="$FAKE_HOME"
teamdb_heal_global >/dev/null 2>&1
RC_HEAL_AGAIN=$?
export HOME="$HOME_BAK"
TOTAL_ROWS="$(sqlite3 "$DB_OLD_ROUTING" "SELECT COUNT(*) FROM routing_decisions")"
if [ "$RC_HEAL_AGAIN" = "0" ] && [ "$TOTAL_ROWS" = "2" ]; then
  assert_pass "heal del rebuild es idempotente (2ª pasada no duplica ni rompe)"
else
  assert_fail "heal del rebuild es idempotente" "rc=$RC_HEAL_AGAIN rows=$TOTAL_ROWS"
fi
rm -rf "$FAKE_HOME"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
