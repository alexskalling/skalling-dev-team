# Plan único versionado: 1 proposal → 1 plan → N tasks ejecutables, todo en DB

**Slug:** plan-unico-versionado-2026-08-06
**Status:** approved
**Agent:** pol
**Fecha:** 2026-08-06 12:00:00

## Contexto

Hoy, cuando un usuario pide un plan, el sistema produce artefactos redundantes y contradictorios:

1. **Dos planes paralelos por feature**. Pol escribe `proposal.md` (validación ligera del intent). Sol escribe `design.md` + `tasks.md` (plan técnico detallado). Ambos viven en `.opencode/changes/<slug>/` como archivos separados. Si Teo los lee, ve DOS documentos distintos sobre el mismo tema y no sabe cuál seguir.

2. **Tasks con títulos poéticos**. Las tasks que escribe Sol tienen nombres tipo "Gimme Shelter", "Sympathy for the Devil". Sin propósito explícito, sin criterios de aceptación verificables, sin orden lógico que indique qué bloquea qué.

3. **Sol CREA OTRO PLAN en vez de mejorar el existente**. Cuando el `proposal.md` necesita más detalle técnico, Sol abre `design.md` aparte en lugar de hacer UPDATE del mismo plan en la DB. Resultado: dos documentos divergentes sobre la misma feature.

4. **Teo se inventa planes**. Cuando va a ejecutar, en vez de consultar la DB por el plan activo del slug y seguirlo, a veces inventa su propio approach basándose en lo que vio en el `proposal.md` + `design.md` + su propio instinto.

5. **Dos sources of truth**. Las tasks existen en archivos `.md` Y en la tabla `tasks` de `team.db`. Si editás uno, el otro queda stale. No hay garantía de que lo que Teo ejecuta coincida con lo que el humano aprobó.

## Causa raíz

El modelo actual es **filesystem-first**: el ciclo de un plan vive en archivos `.md` bajo `.opencode/changes/<slug>/`. La DB tiene las tablas (`proposals`, `plans`, `tasks`, `task_dependencies`, `plan_history`) pero los agentes no las usan como contrato — las usan como espejo opcional.

Síntomas estructurales:

- **Falta enforcement de "1 plan por slug activo"**. `plans.slug` es `UNIQUE`, pero nada impide que haya un plan `draft` y otro `active` para el mismo slug simultáneamente. `teamdb-plan.sh` resuelve esto parcialmente con `ON CONFLICT(slug) DO UPDATE`, pero no hay check explícito.
- **No hay lifecycle formal**. `plans.status` acepta `draft|active|completed|abandoned`. Falta `in_progress` y `approved` para representar el flujo real (Pol escribe proposal → user aprueba → Sol mejora → Teo ejecuta → complete).
- **`tasks.purpose` no existe**. Solo hay `title` + `description_md`. Los criterios de aceptación van en `acceptance_md` pero no se enforce que estén presentes.
- **`tasks.depends_on` no existe como JSON**. Está la tabla `task_dependencies` (mejor diseño relacional, de hecho), pero no se usa en `teamdb-plan.sh` consistentemente para visualizar el DAG.
- **`plans.intent_md` no existe**. Solo `design_md`. La intención validada por Pol queda huérfana del plan una vez que Sol lo "toma".
- **`plans.version` no existe**. `plan_history` tiene `version` pero `plans` no. Imposible hacer "última versión" sin joins.

## Decisión

**Un solo plan semántico por feature-slug, viviendo en la DB. Los archivos `.md` son SOLO exports legibles para git, no contratos.**

### Reglas duras

1. **1 plan por feature-slug**. Constraint: `UNIQUE(slug WHERE status IN ('draft','approved','in_progress'))` — solo puede haber UNO activo a la vez. Si se quiere un nuevo intento, el viejo pasa a `abandoned` (no se borra; queda en `audit_log`).
2. **Source of truth = DB**. El artefacto canónico es la fila de la tabla (`proposals`, `plans`, `tasks`). El `.md` en `.opencode/changes/<slug>/` se regenera con `teamdb-export-md.sh` y SIEMPRE lleva header `<!-- GENERATED -->`. Editar el `.md` está prohibido y se detecta con diff contra la DB.
3. **Lifecycle explícito**: `draft → approved → in_progress → completed`. Transiciones registradas en `audit_log` (ya hay triggers en `tasks`, falta en `plans`).
4. **Pol escribe el `proposal`** (intención validada, no muy detallado). Status inicial: `draft`.
5. **Sol hace UPDATE del mismo plan**, no crea otro. Cuando necesita más detalle técnico, edita `plans.design_md` + agrega `specs` + `design_notes`. El plan pasa a `approved` cuando Pol/user lo firma.
6. **Pol NO borra el plan de Sol**. Solo puede agregar otra versión (incrementar `plans.version`, append a `plan_history` con `operation='amended'`).
7. **Teo busca el plan activo por slug en la DB y lo sigue**. Comando: `teamdb-execute-plan.sh <project> --slug=<slug>`. NO inventa otro. NO lee `.md` para "interpretar".
8. **Tasks con contrato**: cada task tiene `purpose` (1-2 frases por qué existe) + `acceptance_md` (criterios verificables) + `order_index` (entero, orden de ejecución) + DAG via `task_dependencies` (FK a otras tasks del mismo plan). Títulos NO poéticos: `"Migrar plans.design_md a nullable"` no `"Gimme Shelter"`.

### Responsabilidades por agente

| Agente | Responsabilidad | Acción sobre la DB |
|---|---|---|
| **Pol** | Validar intent, escribir `proposal` | `INSERT proposals(status='draft')`. No toca `plans`. |
| **Sol** | Mejorar plan técnico, definir tasks | `UPDATE plans(design_md, version+=1)`, `INSERT specs`, `INSERT tasks`, `INSERT task_dependencies`. Status: `draft → approved`. |
| **Teo** | Ejecutar tasks | `SELECT tasks WHERE plan_id=? ORDER BY order_index`, claim con `task_claims`, `UPDATE tasks(status='in_progress')`. |
| **Luz** | Verificar AC de cada task | `UPDATE tasks(status='in_review', resolution_md='...')`. |
| **Pau** | Cerrar feature | `UPDATE plans(status='completed')` cuando todas las tasks están `approved`. |

### Schema propuesto (migration 009)

> **Nota técnica**: las tablas `plans` y `tasks` YA EXISTEN (migration 002, schema v0.7.1). El approach es **ALTER TABLE** + nuevas constraints, NO `CREATE TABLE` (eso borraría data existente).

```sql
-- 009_unique_plan_active.sql
PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

-- 1. plans: agregar columnas faltantes
CREATE TABLE plans_new (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  proposal_id INTEGER REFERENCES proposals(id),
  intent_md TEXT,                          -- NUEVO: copia del proposal.intent_md al crear el plan
  design_md TEXT NOT NULL DEFAULT '',
  acceptance_md TEXT,
  status TEXT DEFAULT 'draft' CHECK(status IN ('draft','approved','in_progress','completed','abandoned')),
  version INTEGER DEFAULT 1,               -- NUEVO
  agent TEXT,
  created_at TEXT,
  updated_at TEXT,
  completed_at TEXT,
  created_by TEXT,                         -- NUEVO
  updated_by TEXT                          -- NUEVO
);

INSERT INTO plans_new (id, slug, title, proposal_id, intent_md, design_md, acceptance_md,
                       status, agent, created_at, updated_at, completed_at, version)
SELECT id, slug, title, proposal_id, NULL AS intent_md, design_md, acceptance_md,
       status, agent, created_at, updated_at, completed_at, 1 AS version
FROM plans;

DROP TABLE plans;
ALTER TABLE plans_new RENAME TO plans;
CREATE INDEX idx_plans_status ON plans(status);

-- 2. tasks: agregar purpose (description_md se mantiene como legacy/extended)
CREATE TABLE tasks_new (
  id INTEGER PRIMARY KEY,
  plan_id INTEGER NOT NULL REFERENCES plans(id),
  slug TEXT NOT NULL,
  title TEXT NOT NULL,
  purpose TEXT NOT NULL DEFAULT '',        -- NUEVO: por qué existe (1-2 frases)
  description_md TEXT,                     -- LEGACY: detalles extendidos, opcional
  acceptance_md TEXT NOT NULL DEFAULT '',  -- ENFORCE: obligatorio (CHECK en aplicación)
  status TEXT DEFAULT 'pending' CHECK(status IN ('pending','in_progress','in_review','approved','resolved','rejected','blocked')),
  priority INTEGER DEFAULT 3,
  owner TEXT,
  blocked_reason TEXT,
  resolution_md TEXT,
  order_index INTEGER DEFAULT 0,
  estimated_minutes INTEGER,
  created_at TEXT,
  updated_at TEXT,
  started_at TEXT,
  resolved_at TEXT,
  UNIQUE(plan_id, slug)
);

INSERT INTO tasks_new (id, plan_id, slug, title, purpose, description_md, acceptance_md,
                       status, priority, owner, blocked_reason, resolution_md,
                       order_index, estimated_minutes, created_at, updated_at, started_at, resolved_at)
SELECT id, plan_id, slug, title, '' AS purpose, description_md, COALESCE(acceptance_md, ''),
       status, priority, owner, blocked_reason, resolution_md,
       order_index, estimated_minutes, created_at, updated_at, started_at, resolved_at
FROM tasks;

DROP TABLE tasks;
ALTER TABLE tasks_new RENAME TO tasks;
CREATE INDEX idx_tasks_plan ON tasks(plan_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_owner ON tasks(owner);

-- 3. Audit triggers en plans (ya existen en tasks, work_in_progress, etc.)
CREATE TRIGGER plans_audit_ai AFTER INSERT ON plans BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'insert', 'plans', new.id,
          json_object('slug', new.slug, 'status', new.status), 'trigger');
END;
CREATE TRIGGER plans_audit_au AFTER UPDATE ON plans BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime('now'), 'system', 'update', 'plans', new.id,
          json_object('slug', new.slug, 'old_status', old.status, 'new_status', new.status, 'version', new.version), 'trigger');
END;

COMMIT;
PRAGMA foreign_keys=ON;

UPDATE schema_meta SET value = '0.7.7' WHERE key = 'version';
```

### Cambios en scripts

| Script | Cambio |
|---|---|
| `teamdb-plan.sh` | Al crear plan, copiar `proposal.intent_md` → `plan.intent_md`. Al insertar task, exigir `purpose` no vacío + `acceptance_md` no vacío (fail-fast con mensaje claro). |
| `teamdb-amend.sh` | Nuevo: UPDATE del plan existente (incrementa `version`, append a `plan_history` con `operation='amended'`). |
| `teamdb-plan.sh` (subcomando) | Agregar `--improve` para que Sol pueda llamar al mismo script en modo UPDATE, no solo CREATE. |
| `teamdb-export-md.sh` | Refrescar header: incluir `purpose` de cada task en `tasks.md`, no solo título. |
| `teamdb-execute-plan.sh` | Si el plan está en `draft`, abortar con error claro: "Plan no aprobado. Status actual: draft. Necesita status='approved' para ejecutar." |

### Cambios en agentes (protocol)

| Agente | Cambio |
|---|---|
| `agents-base/Pol.md` | Regla: "NO escribir archivos `.md` de plan. SOLO INSERT en `proposals`. El `.md` se regenera con `teamdb-export-md.sh`." |
| `agents-base/Sol.md` | Regla: "Cuando recibís un handoff de Pol con `proposal.status='approved'`, hacés UPDATE del plan existente (`teamdb-amend.sh`), NO creás otro. Incrementás `version`. Si necesitás romper compatibilidad, creás un plan nuevo con `status='draft'` y el viejo pasa a `abandoned`." |
| `agents-base/Teo.md` | Regla: "Antes de ejecutar, `teamdb-execute-plan.sh <project> --slug=<slug>`. Si no hay plan activo, ABORT y escalar a Alex. NO inventar plan propio." |
| `agents-base/Luz.md` | Regla: "Verificás cada task contra su `acceptance_md`. Si pasa, marcás `status='approved'` + `resolution_md` con evidencia. Si falla, `status='rejected'` + razón." |
| `agents-base/Alex.md` | Regla: "Cuando derive a Sol, pasá el `proposal_id` o `plan_id` (no el path al `.md`). Sol lee la DB, no el filesystem." |

### Cambios en skills

| Skill | Cambio |
|---|---|
| `skills-base/writing-plans/SKILL.md` | Reescribir para que use `teamdb-plan.sh --improve` y `teamdb-amend.sh`. Eliminar refs a `docs/plans/` o `.opencode/changes/<slug>/design.md` como artefactos primarios. |
| `skills-base/brainstorming/SKILL.md` | Reforzar: el output es INSERT en `proposals`, no archivo. |

## Tasks (ordenadas, con propósito + AC)

### Task 1: Crear migration 009_unique_plan_active.sql
- **purpose**: Permitir el nuevo lifecycle (`approved`, `in_progress`) y agregar columnas `version`, `intent_md`, `created_by`, `updated_by` en `plans`, y `purpose` en `tasks`, sin romper data existente (ALTER TABLE pattern).
- **acceptance_criteria**:
  - [ ] Archivo `sql/migrations/009_unique_plan_active.sql` existe y es idempotente
  - [ ] `bash scripts/teamdb-migrate.sh .` corre sin errores sobre una DB con plans/tasks previos
  - [ ] `teamdb_exec_query .opencode/context/team.db "PRAGMA table_info(plans)"` muestra columnas `intent_md`, `version`, `created_by`, `updated_by`
  - [ ] `teamdb_exec_query .opencode/context/team.db "PRAGMA table_info(tasks)"` muestra columna `purpose`
  - [ ] Audit triggers sobre `plans` existen (`SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='plans'`)
  - [ ] `schema_meta.version = '0.7.7'`
- **depends_on**: —

### Task 2: Actualizar agents-base/Pol.md (no crear archivos de plan)
- **purpose**: Eliminar la tentación de Pol de crear `proposal.md` directamente en `.opencode/changes/<slug>/` cuando arranca un plan.
- **acceptance_criteria**:
  - [ ] Sección "Protocolo DB-primera" en Pol.md menciona explícitamente: "NO escribir `.opencode/changes/<slug>/proposal.md`"
  - [ ] Comando canónico documentado: `teamdb-plan.sh <project> create <slug> <title> --intent-stdin`
  - [ ] Test en `tests/setup.test.sh`: `test_pol_no_md_writes` (busca patrones `write.*\.opencode/changes/.*proposal\.md` en Pol.md → debe dar 0)
  - [ ] Sincronizado a `~/.config/opencode/agents/Pol.md`
- **depends_on**: Task 1

### Task 3: Actualizar agents-base/Sol.md (UPDATE no CREATE)
- **purpose**: Forzar que Sol mejore el plan existente (UPDATE) en lugar de abrir `design.md` aparte.
- **acceptance_criteria**:
  - [ ] Sección "Mejorar plan, no crear otro" en Sol.md menciona: "Cuando `proposals.status='approved'`, usar `teamdb-amend.sh`, NO `teamdb-plan.sh create`"
  - [ ] Comando documentado: `teamdb-amend.sh <project> --slug=<slug> --design-stdin --add-task=<task.json>`
  - [ ] Test: `test_sol_uses_amend` (busca `teamdb-amend.sh` en Sol.md → debe aparecer ≥1 vez)
  - [ ] Sincronizado a `~/.config/opencode/agents/Sol.md`
- **depends_on**: Task 1

### Task 4: Actualizar agents-base/Teo.md (lee DB, no inventa)
- **purpose**: Que Teo consulte el plan activo por slug antes de ejecutar, en vez de improvisar.
- **acceptance_criteria**:
  - [ ] Sección "Pre-ejecución" en Teo.md: "Paso 1: `teamdb-execute-plan.sh <project> --slug=<slug> --dry-run`. Si retorna error 'no active plan', ABORT."
  - [ ] Comando `teamdb-execute-plan.sh` rechazada ejecución si `plans.status NOT IN ('approved','in_progress')`
  - [ ] Test: `test_teo_queries_db_first` (assert Teo.md contiene `teamdb-execute-plan.sh`)
  - [ ] Sincronizado a `~/.config/opencode/agents/Teo.md`
- **depends_on**: Task 1, Task 3

### Task 5: Extender teamdb-plan.sh + crear teamdb-amend.sh
- **purpose**: Dar herramientas bash que enforce "1 plan por slug" y "tasks con purpose+AC".
- **acceptance_criteria**:
  - [ ] `teamdb-plan.sh create`: al crear plan, copia `proposal.intent_md` → `plan.intent_md`. Si task no tiene `purpose` o `acceptance_md`, falla con mensaje claro: "task '<slug>' sin purpose o acceptance_md"
  - [ ] `teamdb-amend.sh <project> --slug=<slug>`: hace UPDATE del plan, incrementa `version`, append a `plan_history` con `operation='amended'`
  - [ ] `teamdb-amend.sh --add-task=<task.json>`: inserta task en plan existente con validación de purpose/AC
  - [ ] Tests: `test_plan_create_copies_intent`, `test_amend_increments_version`, `test_amend_appends_history`
- **depends_on**: Task 1

### Task 6: Tests FIX 1.4 (invariantes "1 plan por slug" + "tasks con propósito+AC")
- **purpose**: Que el sistema falle rápido si alguien rompe los invariantes.
- **acceptance_criteria**:
  - [ ] Test `test_one_active_plan_per_slug`: insertar 2 plans con mismo slug + status activo → debe fallar por UNIQUE constraint
  - [ ] Test `test_task_requires_purpose`: insertar task sin purpose → debe fallar
  - [ ] Test `test_task_requires_acceptance`: insertar task sin acceptance_md → debe fallar
  - [ ] Test `test_plan_lifecycle_transitions`: `draft → approved → in_progress → completed` permitido; `draft → completed` directo NO permitido (validar via trigger o CHECK)
  - [ ] Test `test_md_is_generated`: `.opencode/changes/<slug>/proposal.md` lleva header `<!-- GENERATED -->`
  - [ ] Todos los tests pasan con `bash tests/setup.test.sh`
- **depends_on**: Task 1, Task 5

### Task 7: Skill writing-plans (reescribir para usar teamdb)
- **purpose**: Que la skill enseñe el flujo nuevo, no el viejo de escribir `.md`.
- **acceptance_criteria**:
  - [ ] `skills-base/writing-plans/SKILL.md` menciona `teamdb-plan.sh` y `teamdb-amend.sh` con ejemplos concretos
  - [ ] NO contiene `docs/plans/` ni `.opencode/changes/<slug>/design.md` como paths primarios
  - [ ] Paso "Output" del workflow dice: "INSERT en `proposals` (status='draft'). El export `.md` es secundario."
  - [ ] Sincronizado a `~/.config/opencode/skills/writing-plans/SKILL.md`
- **depends_on**: Task 5

### Task 8: Migrar planes `.md` viejos a la DB
- **purpose**: Eliminar la dualidad source-of-truth para planes existentes.
- **acceptance_criteria**:
  - [ ] Script `scripts/migrate-md-plans-to-db.sh` lee `.opencode/changes/<slug>/proposal.md` + `design.md` + `tasks.md`, INSERT en DB
  - [ ] Si ya existe plan con ese slug en DB, skip + warning
  - [ ] Backup del filesystem antes (`mv .opencode/changes .opencode/changes.bak.$(date +%Y%m%d)`)
  - [ ] Reporte: cuántos planes migrados, cuántos saltados
  - [ ] Run sobre el meta-proyecto: 0 errores, N migrados
- **depends_on**: Task 1, Task 5

## Consecuencias

### Positivas

- **1 source of truth** para planes y tasks. La DB es el contrato; el `.md` es solo legible.
- **Lifecycle explícito y auditable**. `audit_log` registra cada transición `draft → approved → in_progress → completed`. Reproducible.
- **Tasks ejecutables con criterios verificables**. `purpose` + `acceptance_md` obligatorios eliminan el "qué significa hecho?" al momento de Luz verificar.
- **Versionado real**. `plans.version` + `plan_history` permiten ver la evolución sin git archaeology.
- **DAG explícito**. `task_dependencies` (ya existe) permite a Teo ejecutar en orden topológico, no adivinando.
- **Migración al modelo DB-first completa**. Esta propuesta cierra el ciclo abierto por `agentes-db-primera-2026-08-06` y `fix-skills-docs-plans-2026-08-06`.

### Negativas / Riesgos

- **Migración de planes `.md` viejos**. Hay planes existentes en `.opencode/changes/` que deben moverse a la DB (Task 8). Riesgo: si un plan tiene un `.md` desactualizado respecto a la DB, hay que decidir cuál gana.
- **Breaking change en scripts que asumen schema viejo**. Si algún cliente externo lee `team.db` directo y asume que `plans` no tiene `intent_md`, va a fallar. Mitigación: el campo se agrega como nullable, no rompe queries existentes.
- **Curva de aprendizaje**. Sol y Teo tienen que aprender el nuevo flujo (`teamdb-amend.sh` en vez de "abrir otro archivo"). Mitigación: tests FIX 1.4 + skill writing-plans reescrita.
- **Performance del ALTER TABLE**. Para DBs con miles de plans, recrear la tabla toma segundos. Aceptable para meta-proyecto (decenas de planes), problemático para proyectos grandes. Mitigación: si el proyecto tiene >1000 plans, agregar flag `--no-rebuild` que haga ALTER TABLE ADD COLUMN en vez de recreate (SQLite soporta ALTER ADD COLUMN, no DROP COLUMN).

### Related

- `agentes-db-primera-2026-08-06`: ciclo DB-primera en agents-base (predecesor)
- `fix-skills-docs-plans-2026-08-06`: fix de skills brainstorming/writing-plans (predecesor paralelo)
- constitution R6: ubicación canónica `.opencode/changes/<feature-slug>/` (mantener para exports)
- constitution R14: "consultá la DB primero" (esta propuesta la enforce en planes)
- schema v0.7.6 → v0.7.7 (migration 009)

---

<!-- Footer: regenerar desde DB con teamdb-export-md.sh -->