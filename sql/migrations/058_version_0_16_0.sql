-- Lifecycle links are stored with their workflow; no destructive schema rebuild.
UPDATE schema_meta SET value = '0.16.0' WHERE key = 'version';
