-- v0.7.9: routing_decisions + receipts (idempotente v0.8.3)
CREATE TABLE IF NOT EXISTS routing_decisions (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  user_intent TEXT NOT NULL,
  chosen_route TEXT NOT NULL,
  route_reason TEXT,
  agents_involved TEXT,
  outcome TEXT DEFAULT 'PENDING',
  completed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_ts ON routing_decisions(ts);

CREATE TABLE IF NOT EXISTS receipts (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  agent TEXT NOT NULL,
  command TEXT NOT NULL,
  exit_code INTEGER NOT NULL,
  output_summary TEXT,
  ts TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_receipts_task ON receipts(task_id);
CREATE INDEX IF NOT EXISTS idx_receipts_agent ON receipts(agent);

UPDATE schema_meta SET value = '0.7.9' WHERE key = 'version';
