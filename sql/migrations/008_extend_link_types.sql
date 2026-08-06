-- Migration 008: extender memory_links.link_type CHECK constraint (v0.7.6)
-- v0.7.6: Auto-enlaza WIP items (work_in_progress) en el grafo de memoria.
-- Nuevos link_types:
--   - part_of:     WIP hijo (feature/task) -> WIP padre (plan/feature)
--   - references:  decision -> concept (decision menciona slug del concept en body_md)
--   - informed_by: alias semantico de references (decision informada por concept)
--   - same_tag:    alias semantico de related (mismo tag entre items heterogeneos)
--
-- SQLite no permite ALTER TABLE ... DROP CONSTRAINT. Patron idempotente:
-- rename -> recreate -> copy -> drop old.

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS memory_links_new (
  id INTEGER PRIMARY KEY,
  from_table TEXT NOT NULL,
  from_id INTEGER NOT NULL,
  to_table TEXT NOT NULL,
  to_id INTEGER NOT NULL,
  link_type TEXT NOT NULL CHECK (link_type IN (
    'extends','contradicts','uses','supersedes','related',
    'part_of','references','informed_by','same_tag'
  )),
  confidence REAL DEFAULT 1.0
);

INSERT INTO memory_links_new (id, from_table, from_id, to_table, to_id, link_type, confidence)
SELECT id, from_table, from_id, to_table, to_id, link_type, confidence
FROM memory_links
WHERE NOT EXISTS (
  SELECT 1 FROM memory_links_new WHERE memory_links_new.id = memory_links.id
);

DROP TABLE memory_links;
ALTER TABLE memory_links_new RENAME TO memory_links;

CREATE INDEX idx_links_from ON memory_links(from_table, from_id);
CREATE INDEX idx_links_to ON memory_links(to_table, to_id);

COMMIT;
PRAGMA foreign_keys=ON;

UPDATE schema_meta SET value = '0.7.6' WHERE key = 'version';
