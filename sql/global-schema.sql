-- Skalling Global DB Schema (version row stamped at build time by scripts/build-schema.sh)
-- Path: ~/.config/opencode/team.db

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

CREATE TABLE agents_meta (
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  role TEXT,
  description TEXT,
  skills TEXT,
  triggers TEXT
);

CREATE TABLE skills_active (
  id INTEGER PRIMARY KEY,
  skill_name TEXT NOT NULL UNIQUE,
  source TEXT,
  installed_at TEXT,
  version TEXT,
  description TEXT,
  load_path TEXT
);

CREATE TABLE constitution_rules (
  id INTEGER PRIMARY KEY,
  rule_num TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  body_md TEXT,
  applies_to TEXT
);

CREATE TABLE user_preferences (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  scope TEXT NOT NULL,
  scope_value TEXT,
  body_md TEXT,
  confidence REAL DEFAULT 1.0,
  source TEXT
);

CREATE TABLE stack_cache (
  id INTEGER PRIMARY KEY,
  project_path TEXT UNIQUE NOT NULL,
  detected_at TEXT,
  language TEXT,
  framework TEXT,
  test_runner TEXT,
  package_manager TEXT,
  fingerprint TEXT
);

CREATE TABLE projects_index (
  id INTEGER PRIMARY KEY,
  project_path TEXT UNIQUE NOT NULL,
  project_name TEXT,
  first_seen TEXT,
  last_opened TEXT,
  concept_count INTEGER DEFAULT 0,
  decision_count INTEGER DEFAULT 0
);

CREATE TABLE tags (
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  color TEXT
);

CREATE TABLE schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Operational tables: memory, decisions, work, routing, workflow.
-- Without these, fresh installs are missing the tables the agents query.
-- Added 2026-08-17 to keep global-schema.sql in sync with project-schema.sql.

CREATE TABLE concepts (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  body_md TEXT,
  category TEXT,
  has_ui BOOLEAN DEFAULT 0,
  updated_at TEXT NOT NULL
);

CREATE TABLE decisions (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  body_md TEXT,
  status TEXT DEFAULT 'accepted' CHECK (status IN ('proposed','accepted','superseded','rejected')),
  decided_at TEXT,
  decided_by TEXT
);

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

CREATE TABLE workflow_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  active_cycle_slug TEXT,
  phase TEXT,
  actor TEXT,
  started_at TEXT,
  lock_token TEXT,
  updated_at TEXT
);

INSERT INTO schema_meta VALUES ('version', '0.9.3');
INSERT INTO schema_meta VALUES ('type', 'global');

CREATE INDEX idx_user_prefs_scope ON user_preferences(scope, scope_value);
CREATE INDEX idx_stack_cache_path ON stack_cache(project_path);
CREATE INDEX idx_concepts_category ON concepts(category);
CREATE INDEX idx_concepts_slug ON concepts(slug);
CREATE INDEX idx_decisions_status ON decisions(status);
CREATE INDEX idx_wip_status ON work_in_progress(status);
CREATE INDEX idx_wip_owner ON work_in_progress(owner);
CREATE INDEX idx_wip_priority ON work_in_progress(priority, status);
CREATE INDEX idx_wip_parent ON work_in_progress(parent_id);
CREATE INDEX idx_wip_type ON work_in_progress(type);
CREATE INDEX idx_routing_decisions_ts ON routing_decisions(ts);
