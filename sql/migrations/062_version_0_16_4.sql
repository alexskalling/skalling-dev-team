-- Verificaciones sin auto-install; no modifica datos ni tablas.
UPDATE schema_meta SET value = '0.16.4' WHERE key = 'version';
