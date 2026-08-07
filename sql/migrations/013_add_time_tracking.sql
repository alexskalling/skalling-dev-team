-- v0.8.2: time tracking en tasks
-- (las columnas ya existen en project-schema.sql; este ALTER es no-op en DBs nuevas
--  pero agrega estimated_minutes en DBs pre-0.8.2 que aún no la tienen.
--  _run_sql() usa `|| true` para tolerar el error "duplicate column name".)
ALTER TABLE tasks ADD COLUMN estimated_minutes INTEGER;
UPDATE schema_meta SET value = '0.8.2' WHERE key = 'version';