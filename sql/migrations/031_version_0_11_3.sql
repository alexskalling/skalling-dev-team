-- v0.11.3: fix critico de teamdb_heal_global (routing_decisions sin
-- DISCOVERY en el CHECK), limpieza del fantasma teamdb-claim-task.sh en
-- instalaciones existentes, teamdb-read.sh acepta proyecto como ultimo
-- argumento posicional, telemetria ya no pierde datos por requests
-- huerfanas, y el modelo de permisos de los 8 agentes pasa a default
-- allow con lista corta de criticos.
UPDATE schema_meta SET value = '0.11.3' WHERE key = 'version';
