#!/usr/bin/env bash
# tests/teamdb-upgrade-existing.test.sh — una base que ya aplicó la 047
# original (c7517ea) se alinea con la versión actual al actualizar.
#
# Tercera auditoría (sobre e95a388): la 047 se modificó después de publicarse;
# las bases que ya la tenían registrada no recibían las columnas de consumo
# (skalling-metrics report fallaba con "no such column: tokens_input") y
# conservaban triggers con DELETE que teamdb_guard rechaza (toda escritura de
# memoria fallaba con "not authorized"). La 048 lo corrige de forma idempotente.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap '[ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"' EXIT
fail() { echo "✗ $1" >&2; exit 1; }
mkdir -p "$TMP/.opencode/context"
DB="$TMP/.opencode/context/team.db"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TMP" >/dev/null 2>&1

# Estado de c7517ea: sin columnas de consumo, trigger de versión con DELETE,
# versión 0.13.0 y la 048 sin aplicar.
sqlite3 "$DB" <<'SQL'
ALTER TABLE workflow_metrics DROP COLUMN tokens_input;
ALTER TABLE workflow_metrics DROP COLUMN tokens_output;
ALTER TABLE workflow_metrics DROP COLUMN tokens_cache_read;
ALTER TABLE workflow_metrics DROP COLUMN cost;
ALTER TABLE workflow_metrics DROP COLUMN agents_used;
ALTER TABLE workflow_metrics DROP COLUMN retries;
DROP TRIGGER decisions_version_au;
CREATE TRIGGER decisions_version_au AFTER UPDATE ON decisions BEGIN
  DELETE FROM memory_versions WHERE table_name = 'decisions' AND slug = OLD.slug AND OLD.slug IS NOT NEW.slug;
  INSERT OR REPLACE INTO memory_versions(table_name, slug, updated_at)
  VALUES ('decisions', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'));
END;
DELETE FROM applied_migrations WHERE name = '048_version_0_13_1';
UPDATE schema_meta SET value = '0.13.0' WHERE key = 'version';
SQL
SKALLING_RUNTIME_AGENT=pau bash "$ROOT/scripts/teamdb-memory.sh" --project "$TMP" decision orm ORM Drizzle >/dev/null 2>&1 \
  && fail "el estado viejo debería rechazar escrituras (si no, el test no reproduce el defecto)"

SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TMP" >/dev/null 2>&1 || fail "teamdb-init no pudo actualizar"
[ "$(sqlite3 "$DB" "SELECT value FROM schema_meta WHERE key='version'")" = "0.13.1" ] || fail "versión no actualizada"
for col in tokens_input tokens_output tokens_cache_read cost agents_used retries; do
  [ "$(sqlite3 "$DB" "SELECT count(*) FROM pragma_table_info('workflow_metrics') WHERE name='$col'")" = 1 ] || fail "falta $col"
done
bash "$ROOT/scripts/skalling-metrics.sh" report "$TMP" >/dev/null || fail "skalling-metrics report falla"
SKALLING_RUNTIME_AGENT=pau bash "$ROOT/scripts/teamdb-memory.sh" --project "$TMP" decision orm ORM Drizzle >/dev/null \
  || fail "la memoria sigue sin poder escribirse"
SKALLING_RUNTIME_AGENT=pau bash "$ROOT/scripts/teamdb-memory.sh" --project "$TMP" decision orm ORM "Drizzle v2" >/dev/null \
  || fail "la actualización de memoria falla"
# Idempotente: correrla sobre una base que ya tiene todo no rompe nada.
python3 "$ROOT/sql/migrations/048_version_0_13_1.py" "$DB" || fail "048 no es idempotente"
echo "PASS: una base de c7517ea queda con columnas de consumo, triggers válidos y memoria escribible"
