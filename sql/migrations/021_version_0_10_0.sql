-- v0.10.0: Adaptive routing, bounded context retrieval and workflow telemetry.
-- Kept separate from 020 so databases that already applied the metrics schema
-- at v0.9.3 still advance to the current bundle version.
UPDATE schema_meta SET value = '0.10.0' WHERE key = 'version';
