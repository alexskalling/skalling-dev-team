-- Migration 010: incluir 'approved' en CHECK de plans.status (v0.7.8)
-- Bloque post-v0.7.7 fix: BUG-1 (decisión + schema no alineados)
--
-- Contexto:
--   La decisión documentada (plan-unico-versionado-v0.7.7) define lifecycle:
--     draft → approved → in_progress → completed (+ abandoned)
--   Migration 009 migró 'active' → 'in_progress' pero OLVIDÓ incluir 'approved'
--   en la nueva CHECK constraint. Schema actual acepta solo 4 estados:
--     (draft, in_progress, completed, abandoned)
--   Esta migration agrega 'approved' como 5to estado válido, alineando schema
--   con la decisión documentada.
--
-- Cambios:
--   1. plans: rebuild con nueva CHECK constraint (incluye 'approved')
--   2. Recrea audit triggers sobre plans (preserva schema de audit_log:
--      columnas ts/agent/action/table_name/row_id/details/actor_source)
--   3. schema_meta.version bumped to 0.7.8

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. plans: rebuild con nueva CHECK constraint (incluye 'approved')
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE plans_new (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  proposal_id INTEGER,
  design_md TEXT NOT NULL DEFAULT '',
  acceptance_md TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','in_progress','completed','abandoned')),
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

INSERT INTO plans_new (id, slug, title, proposal_id, design_md, acceptance_md, status, agent, created_at, updated_at, completed_at, intent_md, version, created_by, updated_by)
SELECT id, slug, title, proposal_id, COALESCE(design_md, ''), acceptance_md, status, agent, created_at, updated_at, completed_at, intent_md, version, COALESCE(created_by, agent, 'sol'), COALESCE(updated_by, agent, 'sol')
FROM plans;

DROP TABLE plans;
ALTER TABLE plans_new RENAME TO plans;
CREATE INDEX IF NOT EXISTS idx_plans_status ON plans(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Audit triggers sobre plans (INSERT y UPDATE)
--    Preserva schema audit_log: ts / agent / action / table_name / row_id /
--    details / actor_source (definido en migration 004)
-- ─────────────────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS plans_audit_ai;
DROP TRIGGER IF EXISTS plans_audit_au;

CREATE TRIGGER plans_audit_ai AFTER INSERT ON plans
BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (
    datetime('now'),
    COALESCE(NEW.created_by, 'system'),
    'insert',
    'plans',
    NEW.id,
    json_object('slug', NEW.slug, 'title', NEW.title, 'status', NEW.status, 'version', NEW.version),
    'trigger'
  );
END;

CREATE TRIGGER plans_audit_au AFTER UPDATE ON plans
BEGIN
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
-- 3. Bump version (idempotente)
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE schema_meta SET value='0.7.8' WHERE key='version';
INSERT OR IGNORE INTO schema_meta (key, value) VALUES ('version', '0.7.8');

COMMIT;
PRAGMA foreign_keys=ON;
