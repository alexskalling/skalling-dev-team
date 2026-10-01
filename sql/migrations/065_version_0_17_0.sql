-- El protocolo de revisión se adopta al retomar cada workflow, sin cerrar historial.
UPDATE schema_meta SET value = '0.17.0' WHERE key = 'version';
