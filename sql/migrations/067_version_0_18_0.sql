-- Nuevas capacidades del runtime; conserva todos los datos y workflows existentes.
UPDATE schema_meta SET value = '0.18.0' WHERE key = 'version';
