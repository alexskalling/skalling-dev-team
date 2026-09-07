-- Skalling v0.10.3
-- Declara readiness verificable y agrega DISCOVERY al contrato de routing.

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

CREATE TABLE routing_decisions_new (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  user_intent TEXT NOT NULL,
  chosen_route TEXT NOT NULL CHECK (chosen_route IN ('DISCOVERY','INLINE','INTERVENTION','FAST-TRACK','SDD','DIRECT','RESEARCH')),
  route_reason TEXT,
  agents_involved TEXT,
  outcome TEXT DEFAULT 'PENDING' CHECK (outcome IN ('PENDING','SUCCESS','FAIL','CANCELLED')),
  completed_at TEXT
);

INSERT INTO routing_decisions_new
  (id, ts, user_intent, chosen_route, route_reason, agents_involved, outcome, completed_at)
SELECT id, ts, user_intent, chosen_route, route_reason, agents_involved, outcome, completed_at
FROM routing_decisions;

DROP TABLE routing_decisions;
ALTER TABLE routing_decisions_new RENAME TO routing_decisions;
CREATE INDEX idx_routing_decisions_ts ON routing_decisions(ts);
CREATE INDEX idx_routing_decisions_route ON routing_decisions(chosen_route);

INSERT INTO schema_meta(key, value)
VALUES ('project_readiness', 'missing')
ON CONFLICT(key) DO NOTHING;

UPDATE schema_meta SET value = '0.10.3' WHERE key = 'version';

COMMIT;
PRAGMA foreign_keys=ON;
