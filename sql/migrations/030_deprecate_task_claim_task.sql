-- Fase 4: unifica el ciclo de claims en teamdb-claim.sh (lease/epoch,
-- input_hash, transiciones verificadas). teamdb-claim-task.sh (CAS simple
-- sobre tasks.status/version, sin expiración de lease) no tenía ningún
-- caller real fuera de sus propios tests -- ningún agente ni skill lo
-- invocaba. task_lock_history queda como superficie legacy de solo
-- lectura, mismo tratamiento que work_in_progress/code_graph_cache.
INSERT INTO schema_meta(key, value)
VALUES ('legacy_surface.task_lock_history', 'read_only_compatibility')
ON CONFLICT(key) DO UPDATE SET value=excluded.value;

UPDATE schema_meta SET value = '0.11.2' WHERE key = 'version';
