-- Skalling Project DB Schema (version row stamped at build time by scripts/build-schema.sh)
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
  details TEXT,
  actor_source TEXT DEFAULT 'trigger'
);
CREATE INDEX idx_audit_ts ON audit_log(ts DESC);

CREATE TABLE schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO schema_meta VALUES ('version', '0.9.0');
INSERT INTO schema_meta VALUES ('type', 'project');

CREATE VIRTUAL TABLE concepts_fts USING fts5(title, body_md, content='concepts', content_rowid='id');
CREATE VIRTUAL TABLE decisions_fts USING fts5(title, body_md, content='decisions', content_rowid='id');
CREATE VIRTUAL TABLE wip_fts USING fts5(title, body_md, content='work_in_progress', content_rowid='id');
CREATE VIRTUAL TABLE problems_fts USING fts5(title, symptom_md, workaround_md, content='known_problems', content_rowid='id');

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

CREATE TRIGGER problems_ai AFTER INSERT ON known_problems BEGIN
  INSERT INTO problems_fts(rowid, title, symptom_md, workaround_md) VALUES (new.id, new.title, new.symptom_md, new.workaround_md);
END;
CREATE TRIGGER problems_ad AFTER DELETE ON known_problems BEGIN
  INSERT INTO problems_fts(problems_fts, rowid, title, symptom_md, workaround_md)
    VALUES('delete', old.id, old.title, old.symptom_md, old.workaround_md);
END;
CREATE TRIGGER problems_au AFTER UPDATE ON known_problems BEGIN
  INSERT INTO problems_fts(problems_fts, rowid, title, symptom_md, workaround_md)
    VALUES('delete', old.id, old.title, old.symptom_md, old.workaround_md);
  INSERT INTO problems_fts(rowid, title, symptom_md, workaround_md) VALUES (new.id, new.title, new.symptom_md, new.workaround_md);
END;

-- ────────────────────────────────────────────────────────────────────────────
-- AUDIT LOG TRIGGERS — registran INSERT/UPDATE/DELETE de las tablas críticas
-- auditado-v0.7.2: actor_source='trigger' distingue triggers de helper/manual
-- ────────────────────────────────────────────────────────────────────────────

CREATE TRIGGER concepts_audit_ai AFTER INSERT ON concepts BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'insert', 'concepts', new.id, json_object('slug', new.slug), 'trigger');
END;
CREATE TRIGGER concepts_audit_au AFTER UPDATE ON concepts BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'update', 'concepts', new.id, json_object('slug', new.slug), 'trigger');
END;
CREATE TRIGGER concepts_audit_ad AFTER DELETE ON concepts BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'delete', 'concepts', old.id, json_object('slug', old.slug), 'trigger');
END;

CREATE TRIGGER decisions_audit_ai AFTER INSERT ON decisions BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'insert', 'decisions', new.id, json_object('slug', new.slug), 'trigger');
END;
CREATE TRIGGER decisions_audit_au AFTER UPDATE ON decisions BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'update', 'decisions', new.id, json_object('slug', new.slug), 'trigger');
END;
CREATE TRIGGER decisions_audit_ad AFTER DELETE ON decisions BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'delete', 'decisions', old.id, json_object('slug', old.slug), 'trigger');
END;

CREATE TRIGGER wip_audit_ai AFTER INSERT ON work_in_progress BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'insert', 'work_in_progress', new.id, json_object('slug', new.slug, 'type', new.type), 'trigger');
END;
CREATE TRIGGER wip_audit_au AFTER UPDATE ON work_in_progress BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'update', 'work_in_progress', new.id, json_object('slug', new.slug, 'status', new.status), 'trigger');
END;
CREATE TRIGGER wip_audit_ad AFTER DELETE ON work_in_progress BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'delete', 'work_in_progress', old.id, json_object('slug', old.slug), 'trigger');
END;

CREATE TRIGGER problems_audit_ai AFTER INSERT ON known_problems BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'insert', 'known_problems', new.id, json_object('slug', new.slug), 'trigger');
END;
CREATE TRIGGER problems_audit_au AFTER UPDATE ON known_problems BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'update', 'known_problems', new.id, json_object('slug', new.slug), 'trigger');
END;
CREATE TRIGGER problems_audit_ad AFTER DELETE ON known_problems BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'delete', 'known_problems', old.id, json_object('slug', old.slug), 'trigger');
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
  due_date TEXT,                          -- v0.9.0: deadline ISO YYYY-MM-DD (overdue en teamdb-status.sh)
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

-- ════════════════════════════════════════
-- DAG + CLAIMS + HISTORY + CAPSULES v0.7.2 (T-2.9)
-- ════════════════════════════════════════

CREATE TABLE task_dependencies (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  depends_on_task_id INTEGER NOT NULL,
  type TEXT DEFAULT 'blocks' CHECK (type IN ('blocks','relates_to','supersedes')),
  created_at TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id),
  FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id),
  UNIQUE(task_id, depends_on_task_id)
);
CREATE INDEX idx_task_deps_task ON task_dependencies(task_id);
CREATE INDEX idx_task_deps_depends ON task_dependencies(depends_on_task_id);

CREATE TABLE task_claims (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  actor TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 1,
  input_hash TEXT NOT NULL,
  lease_until INTEGER NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active','done','failed','expired')),
  claimed_at TEXT NOT NULL,
  released_at TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id)
);
CREATE INDEX idx_task_claims_actor ON task_claims(actor, status);
CREATE INDEX idx_task_claims_lease ON task_claims(lease_until);
CREATE UNIQUE INDEX idx_task_claims_active ON task_claims(task_id) WHERE status = 'active';

CREATE TABLE plan_history (
  id INTEGER PRIMARY KEY,
  plan_id INTEGER NOT NULL,
  version INTEGER NOT NULL,
  changed_by TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  diff_md TEXT,
  snapshot_before TEXT,
  operation TEXT NOT NULL CHECK (operation IN ('created','amended','approved','deprecated','superseded')),
  FOREIGN KEY (plan_id) REFERENCES plans(id)
);
CREATE INDEX idx_plan_history_plan ON plan_history(plan_id, version DESC);

CREATE TABLE task_context_capsules (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  memory_table TEXT NOT NULL CHECK (memory_table IN ('concepts','decisions','preferences','known_problems')),
  memory_id INTEGER NOT NULL,
  relevance INTEGER DEFAULT 1,
  provenance TEXT DEFAULT 'linked',
  FOREIGN KEY (task_id) REFERENCES tasks(id),
  UNIQUE(task_id, memory_table, memory_id)
);
CREATE INDEX idx_task_ctx_capsule ON task_context_capsules(task_id);

-- ════════════════════════════════════════
-- SKILLS REGISTRY (v0.7.3)
-- Indice/ficha de las skills del proyecto. El CONTENIDO NO se guarda aca:
-- vive en .opencode/skills/<name>/SKILL.md (o ~/.agents/skills). Solo metadata
-- para saber qué skills tiene el proyecto, para qué sirven y dónde cargarlas.
-- ════════════════════════════════════════
CREATE TABLE IF NOT EXISTS skills_registry (
  name TEXT PRIMARY KEY,
  description TEXT,
  version TEXT,
  source TEXT,
  load_path TEXT,
  added_at TEXT DEFAULT (datetime('now'))
);

-- ════════════════════════════════════════
-- v0.7.9: Routing + Receipts (mejores prácticas adaptadas)
-- ════════════════════════════════════════

CREATE TABLE routing_decisions (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  user_intent TEXT NOT NULL,
  chosen_route TEXT NOT NULL CHECK (chosen_route IN ('INLINE','INTERVENTION','FAST-TRACK','SDD','DIRECT','RESEARCH')),
  route_reason TEXT,
  agents_involved TEXT,
  outcome TEXT DEFAULT 'PENDING' CHECK (outcome IN ('PENDING','SUCCESS','FAIL','CANCELLED')),
  completed_at TEXT
);
CREATE INDEX idx_routing_decisions_ts ON routing_decisions(ts);
CREATE INDEX idx_routing_decisions_route ON routing_decisions(chosen_route);

CREATE TABLE receipts (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  agent TEXT NOT NULL,
  command TEXT NOT NULL,
  exit_code INTEGER NOT NULL,
  output_summary TEXT,
  ts TEXT NOT NULL,
  tree_hash TEXT               -- v0.8.3: hash del árbol revisado (seal inmutable)
);
CREATE INDEX idx_receipts_task ON receipts(task_id);
CREATE INDEX idx_receipts_agent ON receipts(agent);
CREATE INDEX idx_receipts_ts ON receipts(ts);

-- ════════════════════════════════════════
-- v0.8.0: CAS (compare-and-swap) para tasks
-- Previene race conditions cuando 2 agentes intentan reclamar la misma task.
-- version se incrementa en cada update; locked_by marca quién la está editando.
-- ════════════════════════════════════════

ALTER TABLE tasks ADD COLUMN version INTEGER DEFAULT 1;
ALTER TABLE tasks ADD COLUMN locked_by TEXT;
ALTER TABLE tasks ADD COLUMN locked_at TEXT;
ALTER TABLE tasks ADD COLUMN last_modified_by TEXT;

CREATE TABLE task_lock_history (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  agent TEXT NOT NULL,
  action TEXT NOT NULL,                  -- 'lock' | 'unlock' | 'update'
  ts TEXT NOT NULL,
  old_version INTEGER,
  new_version INTEGER,
  details TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id)
);
CREATE INDEX idx_task_lock_history_task ON task_lock_history(task_id);

-- ════════════════════════════════════════
-- v0.8.3: Migration tracking (idempotente)
-- Tabla que registra qué migrations ya se aplicaron.
-- _run_sql() la consulta para no re-aplicar migrations en re-runs.
-- ════════════════════════════════════════
CREATE TABLE applied_migrations (
  name TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

-- ════════════════════════════════════════
-- v0.8.3: Attempts ledger (idea de sdd-attempt, versión simple)
-- Registro de intentos de implementación por change: cuántos se usaron,
-- cuál es el tope (max_attempts / max_changed_lines) y el estado de la puerta.
-- La escribe scripts/teamdb-attempt.sh (acquire/settle/status).
-- ════════════════════════════════════════
CREATE TABLE IF NOT EXISTS attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT UNIQUE NOT NULL,
  change_name TEXT NOT NULL,
  request_id TEXT NOT NULL,
  work_unit TEXT,
  evidence_goal TEXT,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  max_changed_lines INTEGER NOT NULL DEFAULT 400,
  attempts_used INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'proceed',  -- proceed | blocked | complete
  outcome TEXT,                           -- ok | fail | partial | abandoned
  evidence TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_attempts_change ON attempts(change_name);
CREATE INDEX IF NOT EXISTS idx_attempts_state ON attempts(state);
