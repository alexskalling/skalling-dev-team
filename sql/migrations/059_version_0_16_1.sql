-- Patch de portabilidad; sin cambios destructivos de esquema.
UPDATE schema_meta SET value = '0.16.1' WHERE key = 'version';
