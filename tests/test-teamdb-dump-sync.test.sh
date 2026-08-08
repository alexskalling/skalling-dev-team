#!/usr/bin/env bash
# tests/test-teamdb-dump-sync.sh — Fase 0: dump versionado + restore + merge.
#
# Verifica el núcleo de sync DB↔git:
#   1. teamdb-dump.sh genera el dump versionado determinista (hash estable).
#   2. teamdb-restore.sh no pisa una DB existente sin --force; con --force
#      restaura; en clon fresco (sin DB) crea DB + datos desde el dump.
#   3. teamdb-merge.sh inserta filas nuevas del dump y respeta las locales;
#      último-write-gana por updated_at en ambas direcciones; nunca borra.
#   4. Fail-closed: un secreto en la DB aborta el dump (exit 3).
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0
ERR_MSGS=()

assert() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  OK $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL $name"
    FAIL=$((FAIL+1))
    ERR_MSGS+=("$name")
  fi
}

# ── Setup: proyecto temporal con DB real clonada (datos de ejemplo) ────────────
WORK=$(mktemp -d /tmp/teamdb-dump-sync-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/.opencode/context" "$WORK/db/teamdb" "$WORK/sql" "$WORK/scripts/lib"
cp "$ROOT/sql/project-schema.sql" "$WORK/sql/"
cp "$ROOT/scripts/teamdb-dump.sh" "$ROOT/scripts/teamdb-restore.sh" "$ROOT/scripts/teamdb-merge.sh" "$WORK/scripts/"
cp "$ROOT/scripts/lib/lib-teamdb.sh" "$WORK/scripts/lib/"

# DB de partida: creamos una con datos (2 filas) para poder comparar.
sqlite3 "$WORK/.opencode/context/team.db" < "$WORK/sql/project-schema.sql"
sqlite3 "$WORK/.opencode/context/team.db" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON" >/dev/null 2>&1 || true
sqlite3 "$WORK/.opencode/context/team.db" "INSERT INTO concepts (slug,title,body_md,category,updated_at) VALUES ('c1','Concepto 1','base','core',datetime('now'));"
sqlite3 "$WORK/.opencode/context/team.db" "INSERT INTO concepts (slug,title,body_md,category,updated_at) VALUES ('c2','Concepto 2','base','core',datetime('now'));"

echo "==> Test 1: dump versionado determinista"
bash "$WORK/scripts/teamdb-dump.sh" "$WORK" >/dev/null 2>&1
assert "dump genera archivo" "[ -f '$WORK/db/teamdb/team.dump.sql' ]"
assert "dump contiene filas" "grep -q 'INSERT INTO \"concepts\"' '$WORK/db/teamdb/team.dump.sql'"
H1=$(shasum -a 256 "$WORK/db/teamdb/team.dump.sql" | cut -c1-16)
bash "$WORK/scripts/teamdb-dump.sh" "$WORK" >/dev/null 2>&1
H2=$(shasum -a 256 "$WORK/db/teamdb/team.dump.sql" | cut -c1-16)
assert "dump estable (hash idéntico)" "[ \"$H1\" = \"$H2\" ]"
assert "dump excluye audit_log" "! grep -q 'INSERT INTO \"audit_log\"' '$WORK/db/teamdb/team.dump.sql'"
assert "dump excluye schema_meta" "! grep -q 'INSERT INTO \"schema_meta\"' '$WORK/db/teamdb/team.dump.sql'"

echo "==> Test 2: restore no pisa sin --force"
assert "restore rechaza DB existente" "! bash '$WORK/scripts/teamdb-restore.sh' '$WORK'"
assert "restore con --force aplica" "bash '$WORK/scripts/teamdb-restore.sh' '$WORK' --force"
N_CONCEPTS=$(sqlite3 "$WORK/.opencode/context/team.db" "SELECT COUNT(*) FROM concepts;")
assert "concepts siguen en 2 (sin duplicar)" "[ \"$N_CONCEPTS\" = '2' ]"

echo "==> Test 3: restore en clon fresco (sin DB)"
FRESH=$(mktemp -d /tmp/teamdb-fresh-XXXXXX)
mkdir -p "$FRESH/.opencode/context" "$FRESH/db/teamdb" "$FRESH/sql" "$FRESH/scripts/lib"
cp "$WORK/sql/project-schema.sql" "$FRESH/sql/"
cp "$WORK/db/teamdb/team.dump.sql" "$FRESH/db/teamdb/"
cp "$WORK/scripts/teamdb-restore.sh" "$FRESH/scripts/"
cp "$WORK/scripts/lib/lib-teamdb.sh" "$FRESH/scripts/lib/"
assert "clon fresco crea DB desde dump" "bash '$FRESH/scripts/teamdb-restore.sh' '$FRESH'"
N_FRESH=$(sqlite3 "$FRESH/.opencode/context/team.db" "SELECT COUNT(*) FROM concepts;" 2>/dev/null || echo 0)
assert "clon fresco tiene los datos" "[ \"$N_FRESH\" = '2' ]"
rm -rf "$FRESH"

echo "==> Test 4: merge por fila — inserta lo nuevo, respeta lo local"
# El dump remoto agrega c3; la DB local agrega c_local.
echo "INSERT INTO \"concepts\" (\"id\",\"slug\",\"title\",\"body_md\",\"category\",\"has_ui\",\"updated_at\") VALUES (99,'c3','Remoto','remoto','core',0,'2026-08-08 00:00:00');" >> "$WORK/db/teamdb/team.dump.sql"
sqlite3 "$WORK/.opencode/context/team.db" "INSERT INTO concepts (slug,title,body_md,category,updated_at) VALUES ('c_local','Local','local','core',datetime('now'));"
bash "$WORK/scripts/teamdb-merge.sh" "$WORK" >/dev/null 2>&1
assert "merge inserta fila remota" "sqlite3 '$WORK/.opencode/context/team.db' \"SELECT COUNT(*) FROM concepts WHERE slug='c3';\" | grep -q '1'"
assert "merge respeta fila local" "sqlite3 '$WORK/.opencode/context/team.db' \"SELECT COUNT(*) FROM concepts WHERE slug='c_local';\" | grep -q '1'"

echo "==> Test 5: merge último-write-gana por updated_at"
# c1: local más nueva → el dump viejo no debe pisar.
sqlite3 "$WORK/.opencode/context/team.db" "UPDATE concepts SET body_md='local mas nueva', updated_at='2026-08-09 00:00:00' WHERE slug='c1';"
# c2: dump más nuevo → debe pisar.
sqlite3 "$WORK/.opencode/context/team.db" "UPDATE concepts SET body_md='local vieja', updated_at='2026-08-06 00:00:00' WHERE slug='c2';"
echo "INSERT INTO \"concepts\" (\"id\",\"slug\",\"title\",\"body_md\",\"category\",\"has_ui\",\"updated_at\") VALUES (1,'c1','Concepto 1','dump viejo','core',0,'2026-08-06 00:00:00');" >> "$WORK/db/teamdb/team.dump.sql"
# El id de c2: lo resolvemos desde la DB local (mismo id en el dump original).
C2_ID=$(sqlite3 "$WORK/.opencode/context/team.db" "SELECT id FROM concepts WHERE slug='c2';")
echo "INSERT INTO \"concepts\" (\"id\",\"slug\",\"title\",\"body_md\",\"category\",\"has_ui\",\"updated_at\") VALUES ($C2_ID,'c2','Concepto 2','dump mas nuevo','core',0,'2026-08-09 00:00:00');" >> "$WORK/db/teamdb/team.dump.sql"
bash "$WORK/scripts/teamdb-merge.sh" "$WORK" >/dev/null 2>&1
assert "c1 respeta local más nueva" "sqlite3 '$WORK/.opencode/context/team.db' \"SELECT body_md FROM concepts WHERE slug='c1';\" | grep -q 'local mas nueva'"
assert "c2 toma dump más nuevo" "sqlite3 '$WORK/.opencode/context/team.db' \"SELECT body_md FROM concepts WHERE slug='c2';\" | grep -q 'dump mas nuevo'"

echo "==> Test 6: fail-closed de secretos"
sqlite3 "$WORK/.opencode/context/team.db" "INSERT INTO concepts (slug,title,body_md,category,updated_at) VALUES ('secret-test','S','ghp_1234567890abcdefghijklmnopqrstuvwxyz','core',datetime('now'));"
SEC_DUMP_RC=0
bash "$WORK/scripts/teamdb-dump.sh" "$WORK" >/dev/null 2>&1 || SEC_DUMP_RC=$?
assert "dump aborta con secreto (rc!=0)" "[ \"$SEC_DUMP_RC\" -ne 0 ]"
assert "no escribe dump con secreto" "! grep -q 'secret-test' '$WORK/db/teamdb/team.dump.sql'"

echo "================================="
echo "RESULTADO: $PASS pass, $FAIL fail"
echo "================================="
if [ "$FAIL" -gt 0 ]; then
  printf 'Fallaron: %s\n' "${ERR_MSGS[*]}" >&2
fi
[ "$FAIL" -eq 0 ]
