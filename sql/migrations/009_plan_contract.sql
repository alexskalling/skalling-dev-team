-- Migration 009: Contract enforcement para plans + tasks (v0.7.7)
-- Bloque 2 del proposal plan-unico-versionado-2026-08-06
-- Requiere DB en v0.7.6 (migration 008 aplicada).
--
-- Cambios:
--   1. plans: agrega intent_md, version, created_by, updated_by
--   2. plans: migra status 'active' -> 'in_progress' (data existente)
--   3. plans: nueva CHECK constraint incluye 'in_progress' (no 'active')
--   4. tasks: agrega purpose TEXT NOT NULL DEFAULT ''
--   5. audit triggers sobre plans (INSERT/UPDATE)
--   6. schema_meta.version bumped to 0.7.7
--
-- Estrategia: ALTER TABLE ADD COLUMN para preservar indexes.
-- CHECK constraint requires recreate (SQLite no soporta ALTER ... DROP CONSTRAINT).
-- Data migration: 'active' -> 'in_progress' BEFORE recreate del CHECK.

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. plans: agregar columnas nuevas (preserva indexes existentes)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE plans ADD COLUMN intent_md TEXT;
ALTER TABLE plans ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE plans ADD COLUMN created_by TEXT;
ALTER TABLE plans ADD COLUMN updated_by TEXT;

-- Backfill created_by/updated_by para filas existentes (agent='sol')
UPDATE plans SET created_by = COALESCE(agent, 'sol'), updated_by = COALESCE(agent, 'sol')
WHERE created_by IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. plans: migrar status 'active' -> 'in_progress' (ANTES de rebuild CHECK)
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE plans SET status = 'in_progress' WHERE status = 'active';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. plans: rebuild con nueva CHECK constraint (incluye 'in_progress')
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE plans_new (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  proposal_id INTEGER,
  design_md TEXT NOT NULL DEFAULT '',
  acceptance_md TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','in_progress','completed','abandoned')),
  agent TEXT,
  created_at TEXT,
  updated_at TEXT,
  completed_at TEXT,
  intent_md TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  created_by TEXT,
  updated_by TEXT,
  FOREIGN KEY (proposal_id) REFERENCES proposals(id)
);

INSERT INTO plans_new (
  id, slug, title, proposal_id, design_md, acceptance_md, status, agent,
  created_at, updated_at, completed_at, intent_md, version, created_by, updated_by
)
SELECT
  id, slug, title, proposal_id, COALESCE(design_md, ''), acceptance_md, status, agent,
  created_at, updated_at, completed_at, intent_md, version, created_by, updated_by
FROM plans;

DROP TABLE plans;
ALTER TABLE plans_new RENAME TO plans;
CREATE INDEX IF NOT EXISTS idx_plans_status ON plans(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. tasks: agregar purpose TEXT NOT NULL DEFAULT ''
--    (ALTER TABLE ADD COLUMN con NOT NULL requiere DEFAULT en SQLite)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE tasks ADD COLUMN purpose TEXT NOT NULL DEFAULT '';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Audit triggers sobre plans (INSERT y UPDATE)
--    audit_log usa 'ts' (no 'created_at') y 'details' (no 'payload_json').
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TRIGGER IF NOT EXISTS plans_audit_ai AFTER INSERT ON plans BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (
    datetime('now'),
    COALESCE(NEW.created_by, 'system'),
    'insert',
    'plans',
    NEW.id,
    json_object('slug', NEW.slug, 'status', NEW.status, 'version', NEW.version),
    'trigger'
  );
END;

CREATE TRIGGER IF NOT EXISTS plans_audit_au AFTER UPDATE ON plans BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (
    datetime('now'),
    COALESCE(NEW.updated_by, 'system'),
    'update',
    'plans',
    NEW.id,
    json_object(
      'slug', NEW.slug,
      'old_status', OLD.status,
      'new_status', NEW.status,
      'old_version', OLD.version,
      'new_version', NEW.version
    ),
    'trigger'
  );
END;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Bump version (idempotente)
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE schema_meta SET value = '0.7.7' WHERE key = 'version';
INSERT OR IGNORE INTO schema_meta (key, value) VALUES ('version', '0.7.7');

COMMIT;
PRAGMA foreign_keys=ON;
