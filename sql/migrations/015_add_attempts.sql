-- v0.8.3: attempts ledger (idea de sdd-attempt, versión simple)
-- El CREATE TABLE es idempotente; en DBs frescas la tabla ya la crea
-- project-schema.sql y esto es un no-op. El UPDATE schema_meta mantiene
-- la versión alineada con VERSION (0.8.3, no se bumpeó).
-- En DBs pre-v0.8.3 la tabla applied_migrations no existe (solo la crea
-- project-schema.sql para DBs frescas); crearla acá permite que el runner
-- registre esta migración y no la re-aplique en re-runs.
CREATE TABLE IF NOT EXISTS applied_migrations (
  name TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT UNIQUE NOT NULL,
  change_name TEXT NOT NULL,
  request_id TEXT NOT NULL,
  work_unit TEXT,
  evidence_goal TEXT,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  max_changed_lines INTEGER NOT NULL DEFAULT 400,
  attempts_used INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'proceed',  -- proceed | blocked | complete
  outcome TEXT,                           -- ok | fail | partial | abandoned
  evidence TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_attempts_change ON attempts(change_name);
CREATE INDEX IF NOT EXISTS idx_attempts_state ON attempts(state);
UPDATE schema_meta SET value = '0.8.3' WHERE key = 'version';
