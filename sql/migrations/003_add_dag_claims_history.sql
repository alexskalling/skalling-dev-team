-- Migration 003 v2: DAG + CLAIMS + HISTORY + CAPSULES + UNIQUE PARCIAL
-- Idempotente para DBs v0.7.0/v0.7.1 que ya tienen la tabla task_claims.
-- Si la tabla existe (con o sin UNIQUE), la recrea preservando data.
-- Agrega indice unico parcial WHERE status='active' para historial de attempts.

-- 1. Recreate task_claims preservando data (sin UNIQUE, con indice unico parcial).
-- Solo hacer la copia si task_claims existe Y task_claims_new NO existe (idempotencia).
CREATE TABLE IF NOT EXISTS task_claims_new (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  actor TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 1,
  input_hash TEXT NOT NULL,
  lease_until INTEGER NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active','done','failed','expired')),
  claimed_at TEXT NOT NULL,
  released_at TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id)
);
-- Copiar data SOLO si task_claims existe (la primera vez); en corridas subsiguientes
-- task_claims_new ya existe con data, no duplicar.
-- pragma_table_info no falla si la tabla no existe (retorna 0 rows).
INSERT INTO task_claims_new
  SELECT * FROM task_claims
  WHERE (SELECT count(*) FROM pragma_table_info('task_claims')) > 0
    AND NOT EXISTS (SELECT 1 FROM task_claims_new WHERE task_claims_new.id = task_claims.id);
DROP TABLE IF EXISTS task_claims;
ALTER TABLE task_claims_new RENAME TO task_claims;
CREATE INDEX IF NOT EXISTS idx_task_claims_actor ON task_claims(actor, status);
CREATE INDEX IF NOT EXISTS idx_task_claims_lease ON task_claims(lease_until);
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_claims_active ON task_claims(task_id) WHERE status = 'active';

-- 2. Otras tablas (idempotentes con IF NOT EXISTS)
CREATE TABLE IF NOT EXISTS task_dependencies (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  depends_on_task_id INTEGER NOT NULL,
  type TEXT DEFAULT 'blocks' CHECK (type IN ('blocks','relates_to','supersedes')),
  created_at TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id),
  FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id),
  UNIQUE(task_id, depends_on_task_id)
);
CREATE INDEX IF NOT EXISTS idx_task_deps_task ON task_dependencies(task_id);
CREATE INDEX IF NOT EXISTS idx_task_deps_depends ON task_dependencies(depends_on_task_id);

CREATE TABLE IF NOT EXISTS plan_history (
  id INTEGER PRIMARY KEY,
  plan_id INTEGER NOT NULL,
  version INTEGER NOT NULL,
  changed_by TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  diff_md TEXT,
  snapshot_before TEXT,
  operation TEXT NOT NULL CHECK (operation IN ('created','amended','approved','deprecated','superseded')),
  FOREIGN KEY (plan_id) REFERENCES plans(id)
);
CREATE INDEX IF NOT EXISTS idx_plan_history_plan ON plan_history(plan_id, version DESC);

-- 3. task_context_capsules con provenance (Issue 8): recrea preservando data.
-- Recrea SIEMPRE la tabla: en DBs viejas (sin provenance) agrega la columna; en
-- DBs nuevas (ya con provenance) es no-op (COPY guardado por NOT EXISTS).
CREATE TABLE IF NOT EXISTS task_context_capsules_new (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  memory_table TEXT NOT NULL CHECK (memory_table IN ('concepts','decisions','preferences','known_problems')),
  memory_id INTEGER NOT NULL,
  relevance INTEGER DEFAULT 1,
  provenance TEXT DEFAULT 'linked',
  FOREIGN KEY (task_id) REFERENCES tasks(id),
  UNIQUE(task_id, memory_table, memory_id)
);
INSERT INTO task_context_capsules_new
  SELECT id, task_id, memory_table, memory_id, relevance
  FROM task_context_capsules
  WHERE (SELECT count(*) FROM pragma_table_info('task_context_capsules')) > 0
    AND NOT EXISTS (SELECT 1 FROM task_context_capsules_new WHERE task_context_capsules_new.id = task_context_capsules.id);
DROP TABLE IF EXISTS task_context_capsules;
ALTER TABLE task_context_capsules_new RENAME TO task_context_capsules;
CREATE INDEX IF NOT EXISTS idx_task_ctx_capsule ON task_context_capsules(task_id);

-- 4. Version del schema: esta migracion es la de v0.7.2 (corrige el re-estampado
-- de la migration 002 a 0.7.1 en DBs nuevas). Idempotente.
UPDATE schema_meta SET value = '0.7.2' WHERE key = 'version';
