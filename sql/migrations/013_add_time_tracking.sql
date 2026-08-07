-- v0.8.3: time tracking (no-op si ya está aplicado)
-- estimated_minutes ya está en project-schema.sql:311 desde v0.7.1;
-- este ALTER fue removido porque era redundante y rompía idempotencia.
UPDATE schema_meta SET value = '0.8.3' WHERE key = 'version';
