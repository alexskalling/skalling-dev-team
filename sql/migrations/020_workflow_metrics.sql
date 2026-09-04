CREATE TABLE IF NOT EXISTS workflow_metrics (
  request_id TEXT PRIMARY KEY,
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high')),
  route TEXT,
  agents_count INTEGER DEFAULT 0,
  handoffs INTEGER DEFAULT 0,
  permission_prompts INTEGER DEFAULT 0,
  context_bytes INTEGER DEFAULT 0,
  started_at TEXT NOT NULL,
  completed_at TEXT,
  duration_ms INTEGER,
  outcome TEXT
);
CREATE INDEX IF NOT EXISTS idx_workflow_metrics_started ON workflow_metrics(started_at DESC);
UPDATE schema_meta SET value = '0.9.3' WHERE key = 'version';
