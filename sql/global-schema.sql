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
  version TEXT
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

INSERT INTO schema_meta VALUES ('version', '0.7.2');
INSERT INTO schema_meta VALUES ('type', 'global');

CREATE INDEX idx_user_prefs_scope ON user_preferences(scope, scope_value);
CREATE INDEX idx_stack_cache_path ON stack_cache(project_path);
