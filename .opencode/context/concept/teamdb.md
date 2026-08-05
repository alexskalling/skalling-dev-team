---
type: Concept
title: TeamDB v0.7.2 — ciclo de planificación en DB
description: TeamDB (libSQL) como fuente canónica de estado, versiones y ejecución de planes; ciclo SDD completo en DB con SQL parametrizado, DAG, claims y amendments atómicos.
resource: .opencode/changes/archive/2026-08/teamdb-hardening/
tags: [teamdb, libsql, planes, dag, claims, sqli, audit]
timestamp: 2026-08-05T20:28:57Z
agent: pau
confidence: 0.95
---

# TeamDB v0.7.2

## What

TeamDB es la capa de persistencia de Skalling basada en libSQL (SQLite + FTS5), con dos bases: una global (`~/.config/opencode/team.db`) y una por proyecto (`<proyecto>/.opencode/context/team.db`). Desde v0.7.2 es la **fuente canónica** de estado, versiones, planes y ejecución de trabajo: el ciclo SDD completo (proposals → plans → tasks) vive en la DB, y el markdown exportado es solo representación legible para Git.

## Why

v0.7.0 introdujo las DBs pero el ciclo de trabajo seguía operando sobre markdown (`.opencode/changes/`, `.jsonl` legacy). La auditoría que originó este change encontró 23 hallazgos: SQL injection en `teamdb-search.sh`/`teamdb-related.sh`, escrituras no portables, snippets duplicados en los 8 agentes, audit log sin atribución real (`agent='system'`), handoffs sin validación en runtime y cero cobertura CI de teamdb. El dolor central: no se podía confiar en el estado ni en la seguridad de las escrituras.

## Where

- `.opencode/changes/archive/2026-08/teamdb-hardening/` — plan completo (proposal, spec, design, tasks, receipts) que implementó v0.7.2
- `sql/project-schema.sql` / `sql/global-schema.sql` — esquemas; v0.7.2 agrega `task_dependencies`, `task_claims`, `plan_history`, `task_context_capsules`, `problems_fts` y `audit_log.actor_source`
- `scripts/lib/lib-teamdb.sh` — helpers `teamdb_exec_query`/`teamdb_exec_write` (wrappers de `scripts/teamdb_exec.py`, SQL con bound params reales); `teamdb_safe_query` quedó deprecated
- `scripts/teamdb-{plan,status,amend,execute-plan,resume,deps,claim,context,export-md}.sh` — ciclo de planificación en DB (amendment atómico con version/historial; DAG con detección de ciclos; claims con lease/attempt/input_hash; execute-plan solo orquesta, no ejecuta shell — DC-3)
- `templates/agents/snippets/{code-intelligence,memory-protocol}.md` — single source; los 8 agentes usan markers `@include-snippet` resueltos build-time por `install-global.sh` (DC-2)
- `templates/handoff.schema.json` — `allOf` if/then: `project_context` required si `to` ∈ {TEO, LUZ}; `verification` required si `to` ∈ {JHON, LUZ} o emisor de ingeniería
- `.github/workflows/{tests,teamdb-sqli,handoffs,teamdb-dag-claims}.yml` — 4 workflows de CI
- `tests/teamdb-hardening-suite.sh` — suite agregadora (regresión 45/45)

## Learned

- **Escape manual no es destino final**: la primera iteración de `teamdb_safe_query` escapaba `'` con `sed "s/'/''/g"`; el round 2 la reemplazó por `scripts/teamdb_exec.py` con bound params reales (Python `sqlite3`). El CLI `sqlite3` no soporta bind portablemente; Python sí. `teamdb_safe_query` quedó exportada como deprecated para no romper los tests de Fase 1.
- **flock → transacciones SQLite**: las escrituras concurrentes se resolvieron con `BEGIN IMMEDIATE` + WAL + `busy_timeout` en vez de `flock` (más portable y atómico a nivel DB).
- **Triggers no pueden leer variables de entorno**: el audit log real sale del helper (`actor_source='helper'` con el actor vía `TEAMDB_ACTOR`); los triggers registran `actor_source='trigger'` con `'system'`. Los lectores filtran por `actor_source` para atribución real.
- **El bundle `.opencode/context/` de este repo estaba vacío durante el change**: el proposal registró "bundle corrupto, saltando check"; los concept docs se consolidaron recién al cierre (este doc es el primero). No hay contradictores.
- **Deuda detectada y no resuelta en este change**: `tests/spec-memory-link.test.sh` asume VERSION 0.6.2 (fallaba ya antes del bump 0.7.x, riesgo R-F2-6 documentado en receipt de Fase 2); `receipt_fase2_teo.json` quedó con JSON malformado en la línea 177 (verificación de Jhon fue manual, no parseó el archivo).
