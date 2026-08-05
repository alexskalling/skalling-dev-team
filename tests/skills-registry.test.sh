#!/usr/bin/env bash
# tests/skills-registry.test.sh — Registro de skills (indice) en la DB.
# El CONTENIDO de las skills vive en archivos (SKILL.md); la DB guarda solo
# metadata (name/description/version/source/load_path): skills_active (global)
# y skills_registry (por proyecto). Migración 005 + sync script.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
HOME_BAK="$HOME"
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

# ── A) Schemas ────────────────────────────────────────────────
if grep -q "CREATE TABLE IF NOT EXISTS skills_registry" "$ROOT/sql/project-schema.sql" \
   && grep -q "description TEXT" "$ROOT/sql/project-schema.sql" \
   && grep -q "load_path TEXT" "$ROOT/sql/project-schema.sql"; then
  assert_pass "project-schema.sql: skills_registry con description y load_path"
else
  assert_fail "project-schema.sql: skills_registry con description y load_path"
fi

if grep -q "CREATE TABLE skills_active" "$ROOT/sql/global-schema.sql" \
   && grep -A8 "CREATE TABLE skills_active" "$ROOT/sql/global-schema.sql" | grep -q "description TEXT" \
   && grep -A8 "CREATE TABLE skills_active" "$ROOT/sql/global-schema.sql" | grep -q "load_path TEXT"; then
  assert_pass "global-schema.sql: skills_active con description y load_path"
else
  assert_fail "global-schema.sql: skills_active con description y load_path"
fi

if [ -f "$ROOT/sql/migrations/005_add_skills_registry.sql" ]; then
  assert_pass "existe migración 005_add_skills_registry.sql"
else
  assert_fail "existe migración 005_add_skills_registry.sql"
fi

# ── B) Migración 005 idempotente sobre DB minima ──────────────
TMP="$(mktemp -d /var/folders/0k/fn8hdjkd03s5jhp5j5hlp47m0000gn/T/opencode/skills-reg-XXXXXX)"
export HOME="$TMP/home"
mkdir -p "$HOME/.config/opencode"

DB_MIG="$TMP/mig.db"
sqlite3 "$DB_MIG" "CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT INTO schema_meta VALUES('version','0.7.2');"
if sqlite3 "$DB_MIG" < "$ROOT/sql/migrations/005_add_skills_registry.sql" >/dev/null 2>&1; then
  assert_pass "migración 005 aplica (exit 0)"
else
  assert_fail "migración 005 aplica (exit 0)"
fi
MIG_TABLE=$(sqlite3 "$DB_MIG" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='skills_registry'")
MIG_VER=$(sqlite3 "$DB_MIG" "SELECT value FROM schema_meta WHERE key='version'")
if [ "$MIG_TABLE" = "1" ] && [ "$MIG_VER" = "0.7.3" ]; then
  assert_pass "migración 005 crea skills_registry y bump a 0.7.3"
else
  assert_fail "migración 005 crea skills_registry y bump a 0.7.3" "table=$MIG_TABLE ver=$MIG_VER"
fi
if sqlite3 "$DB_MIG" < "$ROOT/sql/migrations/005_add_skills_registry.sql" >/dev/null 2>&1; then
  assert_pass "migración 005 idempotente (segunda pasada sin error)"
else
  assert_fail "migración 005 idempotente (segunda pasada sin error)"
fi

# ── C) teamdb-init de proyecto llega a 0.7.3 con skills_registry ──
PROJ="$TMP/proj"
mkdir -p "$PROJ"
bash "$ROOT/scripts/teamdb-init.sh" "$PROJ" >/dev/null 2>&1
P_DB="$PROJ/.opencode/context/team.db"
P_VER=$(sqlite3 "$P_DB" "SELECT value FROM schema_meta WHERE key='version'" 2>/dev/null)
P_SKILLS=$(sqlite3 "$P_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='skills_registry'" 2>/dev/null)
if [ "$P_VER" = "0.7.3" ] && [ "$P_SKILLS" = "1" ]; then
  assert_pass "teamdb-init proyecto: 0.7.3 + skills_registry"
else
  assert_fail "teamdb-init proyecto: 0.7.3 + skills_registry" "ver=$P_VER skills=$P_SKILLS"
fi

# ── D) Sync puebla global + proyecto (idempotente) ────────────
mkdir -p "$HOME/.agents/skills/alpha"
cat > "$HOME/.agents/skills/alpha/SKILL.md" <<'MD'
---
name: alpha
description: Skill alpha para pruebas
---
# Alpha
MD
mkdir -p "$HOME/.agents/skills/beta"
cat > "$HOME/.agents/skills/beta/SKILL.md" <<'MD'
---
name: beta
description: Skill beta sin version
version: 2.1.0
---
# Beta
MD
mkdir -p "$HOME/.config/opencode/skills/gamma"
cat > "$HOME/.config/opencode/skills/gamma/SKILL.md" <<'MD'
---
name: gamma
description: Skill gamma global instalada
---
# Gamma
MD

PROJ_SK="$PROJ/.opencode/skills/foo"
mkdir -p "$PROJ_SK"
cat > "$PROJ_SK/SKILL.md" <<'MD'
---
name: foo
description: Skill local del proyecto
---
# Foo
MD
cat > "$PROJ/skills-lock.json" <<'JSON'
{
  "version": 1,
  "skills": {
    "foo": { "source": "local", "sourceType": "path", "skillPath": ".opencode/skills/foo/SKILL.md", "computedHash": "abc" },
    "remote-only": { "source": "some/repo", "sourceType": "github", "skillPath": "skills/remote-only/SKILL.md", "computedHash": "def" }
  }
}
JSON

export SKALLING_ROOT="$ROOT"
bash "$ROOT/scripts/teamdb-skills-sync.sh" "$PROJ" >/dev/null 2>&1
SYNC_RC=$?
if [ "$SYNC_RC" = "0" ]; then
  assert_pass "teamdb-skills-sync.sh retorna exit 0"
else
  assert_fail "teamdb-skills-sync.sh retorna exit 0" "rc=$SYNC_RC"
fi

G_DB="$HOME/.config/opencode/team.db"
G_ROWS=$(sqlite3 "$G_DB" "SELECT COUNT(*) FROM skills_active")
G_ALPHA_DESC=$(sqlite3 "$G_DB" "SELECT description FROM skills_active WHERE skill_name='alpha'")
if [ "$G_ROWS" = "3" ] && [ "$G_ALPHA_DESC" = "Skill alpha para pruebas" ]; then
  assert_pass "skills_active global: 3 skills con description extraída del frontmatter"
else
  assert_fail "skills_active global: 3 skills con description extraída del frontmatter" "rows=$G_ROWS alpha_desc=$G_ALPHA_DESC"
fi

P_ROWS=$(sqlite3 "$P_DB" "SELECT COUNT(*) FROM skills_registry")
P_FOO_DESC=$(sqlite3 "$P_DB" "SELECT description FROM skills_registry WHERE name='foo'")
P_REMOTE_SRC=$(sqlite3 "$P_DB" "SELECT source FROM skills_registry WHERE name='remote-only'")
P_REMOTE_DESC=$(sqlite3 "$P_DB" "SELECT COALESCE(description,'NULL') FROM skills_registry WHERE name='remote-only'")
if [ "$P_ROWS" = "2" ] && [ "$P_FOO_DESC" = "Skill local del proyecto" ] && [ "$P_REMOTE_SRC" = "some/repo" ] && [ "$P_REMOTE_DESC" = "NULL" ]; then
  assert_pass "skills_registry proyecto: local con descripción + locked remoto sin SKILL.md local"
else
  assert_fail "skills_registry proyecto: local con descripción + locked remoto sin SKILL.md local" \
    "rows=$P_ROWS foo=$P_FOO_DESC remote_src=$P_REMOTE_SRC remote_desc=$P_REMOTE_DESC"
fi

bash "$ROOT/scripts/teamdb-skills-sync.sh" "$PROJ" >/dev/null 2>&1
G_ROWS2=$(sqlite3 "$G_DB" "SELECT COUNT(*) FROM skills_active")
P_ROWS2=$(sqlite3 "$P_DB" "SELECT COUNT(*) FROM skills_registry")
if [ "$G_ROWS2" = "3" ] && [ "$P_ROWS2" = "2" ]; then
  assert_pass "sync idempotente (2da pasada sin duplicados)"
else
  assert_fail "sync idempotente (2da pasada sin duplicados)" "global=$G_ROWS2 proj=$P_ROWS2"
fi

export HOME="$HOME_BAK"
rm -rf "$TMP"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
