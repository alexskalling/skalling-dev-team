-- Registro aditivo de versiones anteriores. No modifica ni elimina conocimiento existente.
CREATE TABLE IF NOT EXISTS data_revisions (
  id INTEGER PRIMARY KEY,
  table_name TEXT NOT NULL,
  row_key TEXT,
  previous_json TEXT NOT NULL,
  changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
UPDATE schema_meta SET value = '0.11.0' WHERE key = 'version';
