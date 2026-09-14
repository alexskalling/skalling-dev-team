-- Declara en el schema versionado las tablas que scripts/skalling-goal.py y
-- scripts/skalling-workflow.py venian creando al vuelo en su primer uso
-- (CREATE TABLE IF NOT EXISTS en runtime, sin migration ni entrada en
-- sql/project-schema.sql). El schema es version y se migra, no una sorpresa
-- del primer /skalling-goal o skalling_workflow en un proyecto existente.
CREATE TABLE IF NOT EXISTS session_goals(
  session TEXT PRIMARY KEY, objective TEXT NOT NULL, status TEXT NOT NULL,
  base_head TEXT NOT NULL, protected TEXT NOT NULL, branch TEXT NOT NULL,
  turns INTEGER NOT NULL DEFAULT 0, stagnant INTEGER NOT NULL DEFAULT 0,
  fingerprint TEXT NOT NULL, checkpoint TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL DEFAULT '', commit_sha TEXT,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS session_goal_history(
  id INTEGER PRIMARY KEY, session TEXT NOT NULL, goal_json TEXT NOT NULL,
  archived_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS agent_workflows(id TEXT PRIMARY KEY, body TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS agent_workflow_events(
  id INTEGER PRIMARY KEY, request_id TEXT NOT NULL, actor TEXT NOT NULL,
  session TEXT NOT NULL, action TEXT NOT NULL, state TEXT NOT NULL,
  evidence TEXT NOT NULL, ts REAL NOT NULL
);

UPDATE schema_meta SET value = '0.11.4' WHERE key = 'version';
