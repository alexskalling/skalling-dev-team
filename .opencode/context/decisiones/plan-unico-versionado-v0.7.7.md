---
title: Plan único versionado (v0.7.7)
slug: plan-unico-versionado-v0.7.7
status: accepted
date: 2026-08-06
agent: pol
decided_by: user
related:
  - agentes-db-primera-2026-08-06
  - fix-skills-docs-plans-2026-08-06
schema_version: 0.7.7
---

# Decisión: Plan único versionado (v0.7.7)

## Contexto

Antes de v0.7.7, los planes vivían mayormente en archivos `.md` bajo `.opencode/changes/<slug>/` y la DB servía solo como espejo parcial. Esto causaba:

- **Dos planes paralelos por feature**: `proposal.md` (Pol) + `design.md` (Sol) sobre el mismo tema.
- **Tasks con títulos poéticos** sin propósito ni criterios de aceptación verificables.
- **Sol CREABA OTRO PLAN en vez de mejorar el existente** cuando necesitaba más detalle.
- **Teo se inventaba planes** en lugar de consultar el plan activo por slug.
- **Dos sources of truth**: las tasks existían en `.md` Y en la tabla `tasks` de `team.db`, divergentes.

## Decisión

Adoptar el modelo **"1 plan semántico por `feature-slug`, viviendo en la DB"** con las siguientes reglas duras:

1. **1 plan activo por `feature-slug`** (en `draft|approved|in_progress`). Constraint: `UNIQUE(slug)`.
2. **Source of truth = DB** (`proposals` + `plans` + `tasks` + `task_dependencies` + `plan_history` + audit triggers). Los `.md` son SOLO exports legibles para git, siempre con header `<!-- GENERATED -->`.
3. **Lifecycle explícito**: `draft → approved → in_progress → completed` (+ `abandoned`).
4. **Tasks con contrato**: `purpose` (1-2 frases) + `acceptance_md` (criterios verificables) + `order_index` + DAG via `task_dependencies`. Títulos NO poéticos (heurística: 4+ palabras lowercase = rechazado).
5. **Pol escribe el `proposal`**, Sol hace `UPDATE` del mismo plan (no crea otro), Teo busca el plan activo por slug en la DB, Luz verifica contra `acceptance_md`, Pau cierra.

## Schema (migration 009)

- `plans`: agrega `intent_md` (copia del `proposal.intent_md`), `version` (entero, bumpeado en cada UPDATE), `created_by`, `updated_by`.
- `plans.status`: nueva CHECK constraint reemplaza `active` por `in_progress`.
- `tasks`: agrega `purpose TEXT NOT NULL DEFAULT ''`.
- 2 audit triggers sobre `plans` (insert + update) registran en `audit_log`.
- `schema_meta.version = '0.7.7'`.

## Scripts

- `teamdb-plan.sh --strict-contract --purpose=... --acceptance=...`: crea plan atómicamente, rechaza tasks sin propósito/AC, rechaza títulos poéticos.
- `teamdb-amend.sh --slug=<slug> [--add-task=<json>] [--design-stdin]`: UPDATE del plan, bumpea `version`, append a `plan_history` con `operation='amended'`. `--add-task` exige `--purpose`.
- `teamdb-execute-plan.sh`: rechaza ejecución si `status NOT IN ('approved','in_progress')`.

## Agentes

- `Pol.md`: regla explícita "NO escribir archivos `.md` de plan. SOLO INSERT en `proposals` via `teamdb-plan.sh`."
- `Sol.md`: regla "Cuando recibís handoff de Pol con `proposals.status='approved'`, hacés UPDATE del plan existente (`teamdb-amend.sh`), NO creás otro."
- `Teo.md`: regla "Antes de ejecutar, `teamdb-execute-plan.sh --slug=<slug> --dry-run`. NO inventar plan propio."
- `Luz.md`: regla "Verificás cada task contra su `acceptance_md`. Marcás `approved` con evidencia o `rejected` con razón."

## Skills

- `skills-base/writing-plans/SKILL.md` reescrita para v0.7.7. Ahora referencia `teamdb-plan.sh --strict-contract` y `teamdb-amend.sh`. Títulos poéticos y tasks sin propósito/AC son rechazados.

## Consecuencias

### Positivas

- 1 source of truth (la DB). Los `.md` son export.
- Lifecycle auditable via `audit_log` + `plan_history.version`.
- Tasks ejecutables con criterios verificables (Luz puede validar objetivamente).
- DAG explícito via `task_dependencies` (ya existía, ahora se usa consistentemente).
- Curva de aprendizaje: tests FIX 1.3/1.4/1.5/1.6 garantizan que las reglas se cumplen.

### Negativas / Riesgos

- Migración de planes `.md` viejos a la DB (Bloque 4): los `.md` ya existentes en `.opencode/changes/` se importan con sufijo `-legacy-imported` y `decided_by='legacy-import'`. Idempotente.
- Breaking change para clientes que leían `team.db` directo asumiendo schema viejo. Mitigación: columnas nuevas son nullable, no rompe queries existentes.
- Performance del ALTER TABLE recreate para DBs con miles de plans. Mitigación: aceptable para meta-proyecto (decenas), problemático para >1000 plans (futuro: flag `--no-rebuild` con ADD COLUMN en lugar de recreate).

## Related

- `agentes-db-primera-2026-08-06`: ciclo DB-primera en agents-base (predecesor).
- `fix-skills-docs-plans-2026-08-06`: fix de skills brainstorming/writing-plans (predecesor paralelo).
- constitution R6: ubicación canónica `.opencode/changes/<feature-slug>/` (mantener para exports).
- constitution R14: "consultá la DB primero" (esta propuesta la enforce en planes).
- schema v0.7.6 → v0.7.7 (migration 009).

## Implementación

5 commits secuenciales:

1. `feat(skills): reescribir writing-plans para v0.7.7`
2. `feat(migration): script para migrar planes .md viejos a la DB`
3. `feat(db): migration 009 plan_contract (v0.7.7)`
4. `docs(contexto): decision plan-unico-versionado v0.7.7` ← este archivo
5. `chore(db): persistencia de los 3 nuevos proposals + export legible`
