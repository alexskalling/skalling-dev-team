-- Skalling Project DB Schema v0.7.0
-- Path: <proyecto>/.opencode/context/team.db

CREATE TABLE concepts (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  body_md TEXT,
  category TEXT,
  has_ui BOOLEAN DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_concepts_category ON concepts(category);
CREATE INDEX idx_concepts_slug ON concepts(slug);

CREATE TABLE decisions (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  body_md TEXT,
  status TEXT DEFAULT 'accepted' CHECK (status IN ('proposed','accepted','superseded','rejected')),
  decided_at TEXT,
  decided_by TEXT
);
CREATE INDEX idx_decisions_status ON decisions(status);

CREATE TABLE preferences (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  scope TEXT NOT NULL,
  scope_value TEXT,
  body_md TEXT,
  confidence REAL DEFAULT 0.8,
  source TEXT
);
CREATE INDEX idx_preferences_scope ON preferences(scope);

CREATE TABLE known_problems (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  symptom_md TEXT,
  workaround_md TEXT,
  status TEXT DEFAULT 'open' CHECK (status IN ('open','monitoring','resolved','wontfix')),
  discovered_at TEXT,
  resolved_at TEXT
);
CREATE INDEX idx_problems_status ON known_problems(status);

CREATE TABLE work_in_progress (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  type TEXT CHECK (type IN ('plan','feature','task')),
  parent_id INTEGER,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'open' CHECK (status IN ('open','in_progress','in_review','approved','resolved','rejected','abandoned')),
  priority INTEGER DEFAULT 3,
  owner TEXT,
  body_md TEXT,
  acceptance_md TEXT,
  resolution_md TEXT,
  created_at TEXT,
  updated_at TEXT,
  resolved_at TEXT,
  FOREIGN KEY (parent_id) REFERENCES work_in_progress(id)
);
CREATE INDEX idx_wip_status ON work_in_progress(status);
CREATE INDEX idx_wip_owner ON work_in_progress(owner);
CREATE INDEX idx_wip_priority ON work_in_progress(priority, status);
CREATE INDEX idx_wip_parent ON work_in_progress(parent_id);
CREATE INDEX idx_wip_type ON work_in_progress(type);

CREATE TABLE tags (
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  color TEXT
);

CREATE TABLE memory_tags (
  memory_table TEXT NOT NULL CHECK (memory_table IN ('concepts','decisions','preferences','known_problems','work_in_progress')),
  memory_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (memory_table, memory_id, tag_id),
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE TABLE memory_links (
  id INTEGER PRIMARY KEY,
  from_table TEXT NOT NULL,
  from_id INTEGER NOT NULL,
  to_table TEXT NOT NULL,
  to_id INTEGER NOT NULL,
  link_type TEXT NOT NULL CHECK (link_type IN ('extends','contradicts','uses','supersedes','related')),
  confidence REAL DEFAULT 1.0
);
CREATE INDEX idx_links_from ON memory_links(from_table, from_id);
CREATE INDEX idx_links_to ON memory_links(to_table, to_id);

CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  agent TEXT,
  action TEXT,
  table_name TEXT,
  row_id INTEGER,
  details TEXT
);
CREATE INDEX idx_audit_ts ON audit_log(ts DESC);

CREATE TABLE schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO schema_meta VALUES ('version', '0.7.0');
INSERT INTO schema_meta VALUES ('type', 'project');

CREATE VIRTUAL TABLE concepts_fts USING fts5(title, body_md, content='concepts', content_rowid='id');
CREATE VIRTUAL TABLE decisions_fts USING fts5(title, body_md, content='decisions', content_rowid='id');
CREATE VIRTUAL TABLE wip_fts USING fts5(title, body_md, content='work_in_progress', content_rowid='id');

CREATE TRIGGER concepts_ai AFTER INSERT ON concepts BEGIN
  INSERT INTO concepts_fts(rowid, title, body_md) VALUES (new.id, new.title, new.body_md);
END;
CREATE TRIGGER concepts_ad AFTER DELETE ON concepts BEGIN
  INSERT INTO concepts_fts(concepts_fts, rowid, title, body_md) VALUES('delete', old.id, old.title, old.body_md);
END;
CREATE TRIGGER concepts_au AFTER UPDATE ON concepts BEGIN
  INSERT INTO concepts_fts(concepts_fts, rowid, title, body_md) VALUES('delete', old.id, old.title, old.body_md);
  INSERT INTO concepts_fts(rowid, title, body_md) VALUES (new.id, new.title, new.body_md);
END;

CREATE TRIGGER decisions_ai AFTER INSERT ON decisions BEGIN
  INSERT INTO decisions_fts(rowid, title, body_md) VALUES (new.id, new.title, new.body_md);
END;
CREATE TRIGGER decisions_ad AFTER DELETE ON decisions BEGIN
  INSERT INTO decisions_fts(decisions_fts, rowid, title, body_md) VALUES('delete', old.id, old.title, old.body_md);
END;
CREATE TRIGGER decisions_au AFTER UPDATE ON decisions BEGIN
  INSERT INTO decisions_fts(decisions_fts, rowid, title, body_md) VALUES('delete', old.id, old.title, old.body_md);
  INSERT INTO decisions_fts(rowid, title, body_md) VALUES (new.id, new.title, new.body_md);
END;

CREATE TRIGGER wip_ai AFTER INSERT ON work_in_progress BEGIN
  INSERT INTO wip_fts(rowid, title, body_md) VALUES (new.id, new.title, new.body_md);
END;
CREATE TRIGGER wip_ad AFTER DELETE ON work_in_progress BEGIN
  INSERT INTO wip_fts(wip_fts, rowid, title, body_md) VALUES('delete', old.id, old.title, old.body_md);
END;
CREATE TRIGGER wip_au AFTER UPDATE ON work_in_progress BEGIN
  INSERT INTO wip_fts(wip_fts, rowid, title, body_md) VALUES('delete', old.id, old.title, old.body_md);
  INSERT INTO wip_fts(rowid, title, body_md) VALUES (new.id, new.title, new.body_md);
END;

-- ────────────────────────────────────────────────────────────────────────────
-- AUDIT LOG TRIGGERS — registran INSERT/UPDATE/DELETE de las tablas críticas
-- ────────────────────────────────────────────────────────────────────────────

CREATE TRIGGER concepts_audit_ai AFTER INSERT ON concepts BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'insert', 'concepts', new.id, json_object('slug', new.slug));
END;
CREATE TRIGGER concepts_audit_au AFTER UPDATE ON concepts BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'update', 'concepts', new.id, json_object('slug', new.slug));
END;
CREATE TRIGGER concepts_audit_ad AFTER DELETE ON concepts BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'delete', 'concepts', old.id, json_object('slug', old.slug));
END;

CREATE TRIGGER decisions_audit_ai AFTER INSERT ON decisions BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'insert', 'decisions', new.id, json_object('slug', new.slug));
END;
CREATE TRIGGER decisions_audit_au AFTER UPDATE ON decisions BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'update', 'decisions', new.id, json_object('slug', new.slug));
END;
CREATE TRIGGER decisions_audit_ad AFTER DELETE ON decisions BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'delete', 'decisions', old.id, json_object('slug', old.slug));
END;

CREATE TRIGGER wip_audit_ai AFTER INSERT ON work_in_progress BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'insert', 'work_in_progress', new.id, json_object('slug', new.slug, 'type', new.type));
END;
CREATE TRIGGER wip_audit_au AFTER UPDATE ON work_in_progress BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'update', 'work_in_progress', new.id, json_object('slug', new.slug, 'status', new.status));
END;
CREATE TRIGGER wip_audit_ad AFTER DELETE ON work_in_progress BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'delete', 'work_in_progress', old.id, json_object('slug', old.slug));
END;

CREATE TRIGGER problems_audit_ai AFTER INSERT ON known_problems BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'insert', 'known_problems', new.id, json_object('slug', new.slug));
END;
CREATE TRIGGER problems_audit_au AFTER UPDATE ON known_problems BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'update', 'known_problems', new.id, json_object('slug', new.slug));
END;
CREATE TRIGGER problems_audit_ad AFTER DELETE ON known_problems BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details)
  VALUES (datetime('now'), 'system', 'delete', 'known_problems', old.id, json_object('slug', old.slug));
END;

-- ════════════════════════════════════════
-- CICLO COMPLETO EN DB (v0.7.1)
-- ════════════════════════════════════════

-- Proposals: lo que Pol escribe al validar intent
CREATE TABLE proposals (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  intent_md TEXT NOT NULL,                 -- markdown con el intent validado
  questions_json TEXT,                     -- JSON con preguntas/respuestas
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft','approved','rejected')),
  agent TEXT,                              -- 'pol'
  decided_by TEXT,                         -- 'user'
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
  proposal_id INTEGER,                     -- FK a proposals
  design_md TEXT NOT NULL,                 -- markdown con arquitectura
  acceptance_md TEXT,                      -- cómo se mide éxito
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft','active','completed','abandoned')),
  agent TEXT,                              -- 'sol'
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
  owner TEXT,                              -- 'teo' | 'jhon' | 'luz' | 'pau'
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

-- Update schema version
UPDATE schema_meta SET value = '0.7.1' WHERE key = 'version';
