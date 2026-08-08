-- v0.9.0: workflow_state singleton table (DB-first, replaces workflow.json).
-- El estado del ciclo activo vive en la DB, no en .opencode/state/workflow.json.
-- Singleton CHECK (id=1) asegura que solo hay una fila.
CREATE TABLE IF NOT EXISTS workflow_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),  -- singleton: always row id=1
    active_cycle_slug TEXT,                -- slug of currently active cycle, NULL if none
    phase TEXT,                            -- 'pol'|'sol'|'teo'|'jhon'|'luz'|'pau'
    actor TEXT,                            -- agent currently in charge
    started_at TEXT,                       -- ISO8601
    lock_token TEXT,                       -- for distributed locking (hostname+pid+timestamp)
    updated_at TEXT                        -- ISO8601
);

INSERT OR IGNORE INTO workflow_state (id, active_cycle_slug, phase, actor, started_at, updated_at)
VALUES (1, NULL, NULL, NULL, NULL, NULL);

UPDATE schema_meta SET value = '0.9.1' WHERE key = 'version';
