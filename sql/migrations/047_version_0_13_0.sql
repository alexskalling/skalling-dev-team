-- v0.13.0: cierre de la auditoría externa de v0.12.0 (27-09-2026).
--
-- 1. task_claims.session: la identidad de un claim es rol + sesión. Antes dos
--    sesiones de Teo recibían el mismo claim como "idempotente".
-- 2. memory_versions: versión (último cambio) de decisions, preferences y
--    known_problems. Sin versión, el merge entre integrantes ignoraba
--    cualquier cambio (contenido o estado) de una fila que ya existía en el
--    otro clon. Tabla aparte, mantenida por triggers que no tocan la fila:
--    un UPDATE sobre la propia tabla dentro de un trigger corrompe los
--    índices FTS externos (decisions_fts...). Los triggers solo hacen upsert:
--    teamdb_guard prohíbe DELETE incluso dentro de un trigger, y con él toda
--    escritura de memoria por los helpers fallaba (prueba real con 2.0.18).
--    Una versión huérfana (slug renombrado o fila borrada) es inocua.
--    Resolución: gana la versión más reciente; teamdb-merge.sh informa los
--    conflictos.
ALTER TABLE task_claims ADD COLUMN session TEXT;

CREATE TABLE IF NOT EXISTS memory_versions (
  table_name TEXT NOT NULL CHECK (table_name IN ('decisions','preferences','known_problems')),
  slug TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (table_name, slug)
);
CREATE TRIGGER IF NOT EXISTS decisions_version_ai AFTER INSERT ON decisions BEGIN
  INSERT INTO memory_versions(table_name, slug, updated_at)
  VALUES ('decisions', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT(table_name, slug) DO UPDATE SET updated_at = excluded.updated_at;
END;
CREATE TRIGGER IF NOT EXISTS decisions_version_au AFTER UPDATE ON decisions BEGIN
  INSERT INTO memory_versions(table_name, slug, updated_at)
  VALUES ('decisions', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT(table_name, slug) DO UPDATE SET updated_at = excluded.updated_at;
END;
CREATE TRIGGER IF NOT EXISTS preferences_version_ai AFTER INSERT ON preferences BEGIN
  INSERT INTO memory_versions(table_name, slug, updated_at)
  VALUES ('preferences', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT(table_name, slug) DO UPDATE SET updated_at = excluded.updated_at;
END;
CREATE TRIGGER IF NOT EXISTS preferences_version_au AFTER UPDATE ON preferences BEGIN
  INSERT INTO memory_versions(table_name, slug, updated_at)
  VALUES ('preferences', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT(table_name, slug) DO UPDATE SET updated_at = excluded.updated_at;
END;
CREATE TRIGGER IF NOT EXISTS known_problems_version_ai AFTER INSERT ON known_problems BEGIN
  INSERT INTO memory_versions(table_name, slug, updated_at)
  VALUES ('known_problems', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT(table_name, slug) DO UPDATE SET updated_at = excluded.updated_at;
END;
CREATE TRIGGER IF NOT EXISTS known_problems_version_au AFTER UPDATE ON known_problems BEGIN
  INSERT INTO memory_versions(table_name, slug, updated_at)
  VALUES ('known_problems', NEW.slug, strftime('%Y-%m-%d %H:%M:%f', 'now'))
  ON CONFLICT(table_name, slug) DO UPDATE SET updated_at = excluded.updated_at;
END;

INSERT OR IGNORE INTO memory_versions(table_name, slug, updated_at) SELECT 'decisions', slug, coalesce(decided_at, strftime('%Y-%m-%d %H:%M:%f','now')) FROM decisions;
INSERT OR IGNORE INTO memory_versions(table_name, slug, updated_at) SELECT 'preferences', slug, strftime('%Y-%m-%d %H:%M:%f','now') FROM preferences;
INSERT OR IGNORE INTO memory_versions(table_name, slug, updated_at) SELECT 'known_problems', slug, coalesce(resolved_at, discovered_at, strftime('%Y-%m-%d %H:%M:%f','now')) FROM known_problems;

UPDATE schema_meta SET value = '0.13.0' WHERE key = 'version';
