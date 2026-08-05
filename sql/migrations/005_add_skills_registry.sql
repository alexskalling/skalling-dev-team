-- Migration 005: skills_registry por proyecto (v0.7.3)
-- Indice de skills: metadata (name/description/version/source/load_path).
-- El contenido sigue en archivos (SKILL.md en .opencode/skills o ~/.agents/skills);
-- aca solo la ficha. Idempotente.
CREATE TABLE IF NOT EXISTS skills_registry (
  name TEXT PRIMARY KEY,
  description TEXT,
  version TEXT,
  source TEXT,
  load_path TEXT,
  added_at TEXT DEFAULT (datetime('now'))
);

UPDATE schema_meta SET value = '0.7.3' WHERE key = 'version';
