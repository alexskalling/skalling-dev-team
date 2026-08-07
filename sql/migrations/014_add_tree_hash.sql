-- v0.8.3: tree_hash en receipts (revisión congelada)
-- El ALTER no es idempotente por sí mismo, pero el runner (teamdb-init _run_sql)
-- lo tolera: registra la migración en applied_migrations y trata el
-- "duplicate column" de DBs nuevas (donde project-schema.sql ya crea la columna)
-- como [partial] sin fallar. En DBs existentes añade la columna.
ALTER TABLE receipts ADD COLUMN tree_hash TEXT;
UPDATE schema_meta SET value = '0.8.3' WHERE key = 'version';
