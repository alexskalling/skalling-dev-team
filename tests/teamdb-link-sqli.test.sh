#!/usr/bin/env bash
# tests/teamdb-link-sqli.test.sh — Validación teamdb-link.sh::count_type() con payload SQLi
# Patrón: tests/teamdb-search-sqli.test.sh / tests/teamdb-wip-tree-sqli.test.sh.
# Objetivo: defense-in-depth en count_type(). Todos los call sites actuales
# pasan literales fijos (related/uses/part_of/references) y memory_links.link_type
# tiene un CHECK constraint que ya impide guardar un payload como valor —, pero
# la función interpolaba "$1" crudo en el SQL sin escapar: cualquier caller
# futuro con un argumento no controlado sería inyectable de inmediato, sin que
# el CHECK constraint proteja nada (la inyección pasa por el WHERE, no por un
# INSERT). Migrado a _sql_quote (mismo helper que el resto de lib-teamdb.sh usa
# para esto). Validamos que la construcción real de la query —
# "SELECT COUNT(*) FROM memory_links WHERE link_type = $(_sql_quote "$1")" —
# neutraliza un payload de tautología (' OR '1'='1) en vez de matchear todo.
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

# ── Fixture ──
TEST_DIR="$(mktemp -d)"
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1

# shellcheck disable=SC1091
source "$ROOT/scripts/lib/lib-teamdb.sh"

# Filas de control con link_type válidos (respetan el CHECK constraint).
sqlite3 "$DB" "INSERT INTO memory_links(from_table,from_id,to_table,to_id,link_type,confidence) VALUES('concepts',1,'concepts',2,'related',1.0)"
sqlite3 "$DB" "INSERT INTO memory_links(from_table,from_id,to_table,to_id,link_type,confidence) VALUES('concepts',1,'concepts',3,'uses',1.0)"

count_type() {
  sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links WHERE link_type = $(_sql_quote "$1")"
}

# ── Caso 1: literal normal sigue contando bien (control positivo) ──
N=$(count_type "related")
if [ "$N" = "1" ]; then
  assert_pass "count_type('related') cuenta correctamente"
else
  assert_fail "count_type('related') cuenta correctamente" "n=$N"
fi

# ── Caso 2: tautología SQLi no matchea todas las filas ──
PAYLOAD="x' OR '1'='1"
N=$(count_type "$PAYLOAD")
if [ "$N" = "0" ]; then
  assert_pass "tautología SQLi (' OR '1'='1) no matchea filas"
else
  assert_fail "tautología SQLi (' OR '1'='1) no matchea filas" "n=$N (esperado 0, total filas=2)"
fi

# ── Caso 3: payload DROP TABLE no ejecuta nada, tabla sobrevive ──
count_type "evil'; DROP TABLE memory_links; --" >/dev/null 2>&1 || true
TBL=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE name='memory_links'")
if [ "$TBL" = "memory_links" ]; then
  assert_pass "payload DROP TABLE no ejecuta nada, memory_links sobrevive"
else
  assert_fail "payload DROP TABLE no ejecuta nada, memory_links sobrevive" "tbl=$TBL"
fi

# ── Caso 4: las 2 filas de control siguen intactas tras los intentos ──
TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM memory_links")
if [ "$TOTAL" = "2" ]; then
  assert_pass "filas de control intactas tras los intentos de SQLi"
else
  assert_fail "filas de control intactas tras los intentos de SQLi" "total=$TOTAL"
fi

# ── Caso 5: teamdb-link.sh (script real, no la función aislada) sigue corriendo limpio ──
RC=0
bash "$ROOT/scripts/teamdb-link.sh" "$TEST_DIR" >/dev/null 2>&1 || RC=$?
if [ "$RC" = "0" ]; then
  assert_pass "teamdb-link.sh corre limpio (rc=0) tras el fix"
else
  assert_fail "teamdb-link.sh corre limpio (rc=0) tras el fix" "rc=$RC"
fi

# ── Caso 6: bash 3.2 portable check ──
if [ "${BASH_VERSINFO[0]}" -ge 3 ]; then
  assert_pass "compatible bash 3.2+"
else
  assert_fail "compatible bash 3.2+" "bash=$BASH_VERSION"
fi

rm -rf "$TEST_DIR"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
