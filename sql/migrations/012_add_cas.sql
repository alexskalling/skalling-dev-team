-- v0.8.0: CAS para tasks (idempotente v0.8.3)
-- ADD COLUMN IF NOT EXISTS requiere SQLite >= 3.35.
-- En SQLite viejos, _run_sql() detecta la columna via PRAGMA table_info y skip-ea.
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS locked_by TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS locked_at TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS last_modified_by TEXT;

CREATE TABLE IF NOT EXISTS task_lock_history (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  agent TEXT NOT NULL,
  action TEXT NOT NULL,
  ts TEXT NOT NULL,
  old_version INTEGER,
  new_version INTEGER,
  details TEXT
);

UPDATE schema_meta SET value = '0.8.0' WHERE key = 'version';
