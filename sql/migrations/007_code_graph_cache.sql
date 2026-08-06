-- Migration 007: code_graph_cache (v0.7.6)
-- Cache del grafo de imports del proyecto (para que el LLM lo tenga listo)
CREATE TABLE IF NOT EXISTS code_graph_cache (
  id INTEGER PRIMARY KEY,
  node_path TEXT UNIQUE NOT NULL,
  node_lang TEXT,
  node_type TEXT DEFAULT 'source',
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cgc_path ON code_graph_cache(node_path);

CREATE TABLE IF NOT EXISTS code_imports (
  id INTEGER PRIMARY KEY,
  from_path TEXT NOT NULL,
  to_path TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(from_path, to_path)
);
CREATE INDEX IF NOT EXISTS idx_ci_from ON code_imports(from_path);
CREATE INDEX IF NOT EXISTS idx_ci_to ON code_imports(to_path);

UPDATE schema_meta SET value = '0.7.6' WHERE key = 'version';
