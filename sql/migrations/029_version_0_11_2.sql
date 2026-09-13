-- v0.11.2: consolida escaping SQL, corrige fuga de TMP_DIR y falsos
-- positivos del gate de riesgo. Alinea TeamDB existente con el runtime.
UPDATE schema_meta SET value = '0.11.2' WHERE key = 'version';
