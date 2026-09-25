-- v0.11.5: agrega scripts/skalling-models.sh, asignación de modelo de
-- OpenCode independiente por agente (comando /skalling-models), y
-- teamdb-task-groups.sh, detector de tasks paralelizables dentro de un plan
-- basado solo en task_dependencies real (nunca en archivos tocados, esa
-- señal no existe en el schema). Sin cambios de schema; solo eleva la
-- versión declarada.
UPDATE schema_meta SET value = '0.11.5' WHERE key = 'version';
