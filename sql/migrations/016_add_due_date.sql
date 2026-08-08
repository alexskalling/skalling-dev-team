-- v0.9.0: due_date en tasks (deadline del ciclo; teamdb-status.sh la usa para
-- marcar overdue). Mismo patrón 014: el runner (teamdb-init _run_sql) tolera el
-- "duplicate column" de DBs frescas (donde project-schema.sql ya crea la columna)
-- y lo registra como [partial] sin fallar.
ALTER TABLE tasks ADD COLUMN due_date TEXT;
UPDATE schema_meta SET value = '0.9.0' WHERE key = 'version';
