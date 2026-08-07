-- v0.8.0: CAS para tasks
ALTER TABLE tasks ADD COLUMN version INTEGER DEFAULT 1;
ALTER TABLE tasks ADD COLUMN locked_by TEXT;
ALTER TABLE tasks ADD COLUMN locked_at TEXT;
ALTER TABLE tasks ADD COLUMN last_modified_by TEXT;

CREATE TABLE task_lock_history (
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
