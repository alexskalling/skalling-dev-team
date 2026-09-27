"""048 — v0.13.1: alinea con 0.13.0 las bases que aplicaron la 047 anterior.

La 047 se modificó después de haberse publicado en main (c7517ea): se le
agregaron las columnas de consumo de workflow_metrics y sus triggers de
versión pasaron de usar DELETE a solo upsert. Una base que ya había aplicado
la 047 original la tiene registrada y no la vuelve a correr: quedaba sin
columnas (skalling-metrics.sh report fallaba con "no such column") y con
triggers que teamdb_guard rechaza (toda escritura de memoria por los helpers
fallaba con "not authorized").

En Python porque SQLite no tiene ADD COLUMN IF NOT EXISTS: la migración es
idempotente y sirve igual para bases de c7517ea, de v0.13.0 o nuevas.

Uso (lo invoca teamdb-init.sh): python3 048_version_0_13_1.py <team.db>
"""
import sqlite3
import sys

VERSION_SQL = "UPDATE schema_meta SET value = '0.13.1' WHERE key = 'version';"
METRIC_COLUMNS = (('tokens_input', 'INTEGER'), ('tokens_output', 'INTEGER'), ('tokens_cache_read', 'INTEGER'),
                  ('cost', 'REAL'), ('agents_used', 'TEXT'), ('retries', 'INTEGER'))
VERSIONED = ('decisions', 'preferences', 'known_problems')


def columns(db, table):
    return {row[1] for row in db.execute(f'PRAGMA table_info("{table}")')}


def upsert_trigger(table, event):
    return f"""CREATE TRIGGER {table}_version_{event} AFTER {'INSERT' if event == 'ai' else 'UPDATE'} ON {table} BEGIN
  INSERT INTO memory_versions(table_name, slug, updated_at)
  VALUES ('{table}', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT(table_name, slug) DO UPDATE SET updated_at = excluded.updated_at;
END;"""


def main(path):
    db = sqlite3.connect(path, timeout=10)
    try:
        db.execute('BEGIN IMMEDIATE')
        tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if 'workflow_metrics' in tables:
            present = columns(db, 'workflow_metrics')
            for name, kind in METRIC_COLUMNS:
                if name not in present:
                    db.execute(f'ALTER TABLE workflow_metrics ADD COLUMN {name} {kind}')
        if 'task_claims' in tables and 'session' not in columns(db, 'task_claims'):
            db.execute('ALTER TABLE task_claims ADD COLUMN session TEXT')
        db.execute("""CREATE TABLE IF NOT EXISTS memory_versions (
          table_name TEXT NOT NULL CHECK (table_name IN ('decisions','preferences','known_problems')),
          slug TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (table_name, slug))""")
        for table in VERSIONED:
            if table not in tables:
                continue
            for event in ('ai', 'au', 'ad'):
                db.execute(f'DROP TRIGGER IF EXISTS {table}_version_{event}')
            db.execute(upsert_trigger(table, 'ai'))
            db.execute(upsert_trigger(table, 'au'))
            db.execute(f"INSERT OR IGNORE INTO memory_versions(table_name, slug, updated_at) "
                       f"SELECT '{table}', slug, strftime('%Y-%m-%d %H:%M:%f', 'now') FROM {table}")
        db.execute(VERSION_SQL)
        db.commit()
    except sqlite3.Error as error:
        db.rollback()
        raise SystemExit(f'048: {error}')
    finally:
        db.close()


if __name__ == '__main__':
    main(sys.argv[1])
