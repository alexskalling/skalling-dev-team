-- v0.7.1: Agregar tablas del ciclo completo (proposals, plans, specs, design_notes, tasks)
-- Aplicar sobre DBs existentes que estén en v0.7.0 o anterior.

-- Recrear schema_meta (patrón safe para renombrar + reemplazar)
ALTER TABLE schema_meta RENAME TO schema_meta_old;
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta SELECT * FROM schema_meta_old;
DROP TABLE schema_meta_old;

-- Proposals: lo que Pol escribe al validar intent
CREATE TABLE proposals (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  intent_md TEXT NOT NULL,
  questions_json TEXT,
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft','approved','rejected')),
  agent TEXT,
  decided_by TEXT,
  created_at TEXT,
  updated_at TEXT,
  decided_at TEXT
);
CREATE INDEX idx_proposals_status ON proposals(status);

-- Plans: el plan completo creado por Sol
CREATE TABLE plans (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  proposal_id INTEGER,
  design_md TEXT NOT NULL,
  acceptance_md TEXT,
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft','active','completed','abandoned')),
  agent TEXT,
  created_at TEXT,
  updated_at TEXT,
  completed_at TEXT,
  FOREIGN KEY (proposal_id) REFERENCES proposals(id)
);
CREATE INDEX idx_plans_status ON plans(status);

-- Specs: detalles técnicos de cada plan
CREATE TABLE specs (
  id INTEGER PRIMARY KEY,
  plan_id INTEGER NOT NULL,
  slug TEXT NOT NULL,
  title TEXT NOT NULL,
  body_md TEXT NOT NULL,
  order_index INTEGER DEFAULT 0,
  created_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (plan_id) REFERENCES plans(id),
  UNIQUE(plan_id, slug)
);
CREATE INDEX idx_specs_plan ON specs(plan_id);

-- Design notes: ADRs específicos del plan
CREATE TABLE design_notes (
  id INTEGER PRIMARY KEY,
  plan_id INTEGER NOT NULL,
  slug TEXT NOT NULL,
  title TEXT NOT NULL,
  context_md TEXT NOT NULL,
  decision_md TEXT NOT NULL,
  consequences_md TEXT,
  status TEXT DEFAULT 'proposed' CHECK (status IN ('proposed','accepted','rejected')),
  created_at TEXT,
  updated_at TEXT,
  decided_at TEXT,
  FOREIGN KEY (plan_id) REFERENCES plans(id)
);
CREATE INDEX idx_design_notes_plan ON design_notes(plan_id);

-- Tasks: tareas granulares (mejor que work_in_progress para SDD)
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY,
  plan_id INTEGER NOT NULL,
  slug TEXT NOT NULL,
  title TEXT NOT NULL,
  description_md TEXT,
  acceptance_md TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending','in_progress','in_review','approved','resolved','rejected','blocked')),
  priority INTEGER DEFAULT 3,
  owner TEXT,
  blocked_reason TEXT,
  resolution_md TEXT,
  order_index INTEGER DEFAULT 0,
  estimated_minutes INTEGER,
  created_at TEXT,
  updated_at TEXT,
  started_at TEXT,
  resolved_at TEXT,
  FOREIGN KEY (plan_id) REFERENCES plans(id),
  UNIQUE(plan_id, slug)
);
CREATE INDEX idx_tasks_plan ON tasks(plan_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_owner ON tasks(owner);

UPDATE schema_meta SET value = '0.7.1' WHERE key = 'version';
