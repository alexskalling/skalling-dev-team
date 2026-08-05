-- Migration 004 v2: audit_log.actor_source ('helper' | 'trigger' | 'manual')
-- v0.7.2: distingue el origen del audit row. Idempotente: en DBs nuevas la
-- columna ya existe (viene del schema), el error "duplicate column name" lo
-- traga teamdb-init (ver init). En DBs v0.7.1/v0.7.0 la agrega.
ALTER TABLE audit_log ADD COLUMN actor_source TEXT DEFAULT 'trigger';

UPDATE schema_meta SET value = '0.7.2' WHERE key = 'version';
