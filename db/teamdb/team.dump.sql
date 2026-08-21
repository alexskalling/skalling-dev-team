-- teamdb dump v1
-- Generado por teamdb-dump.sh. NO editar a mano; el diff se mergea por fila.
-- Source of truth: .opencode/context/team.db (la DB local). Este archivo es su fotografía.
INSERT INTO "concepts" ("id","slug","title","body_md","category","has_ui","updated_at") VALUES (1,'teamdb','TeamDB v0.7.2 — ciclo de planificación en DB','
# TeamDB v0.7.2

## What

TeamDB es la capa de persistencia de Skalling basada en libSQL (SQLite + FTS5), con dos bases: una global (`~/.config/opencode/team.db`) y una por proyecto (`<proyecto>/.opencode/context/team.db`). Desde v0.7.2 es la **fuente canónica** de estado, versiones, planes y ejecución de trabajo: el ciclo SDD completo (proposals → plans → tasks) vive en la DB, y el markdown exportado es solo representación legible para Git.

## Why

v0.7.0 introdujo las DBs pero el ciclo de trabajo seguía operando sobre markdown (`.opencode/changes/`, `.jsonl` legacy). La auditoría que originó este change encontró 23 hallazgos: SQL injection en `teamdb-search.sh`/`teamdb-related.sh`, escrituras no portables, snippets duplicados en los 8 agentes, audit log sin atribución real (`agent=''system''`), handoffs sin validación en runtime y cero cobertura CI de teamdb. El dolor central: no se podía confiar en el estado ni en la seguridad de las escrituras.

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

- **Escape manual no es destino final**: la primera iteración de `teamdb_safe_query` escapaba `''` con `sed "s/''/''''/g"`; el round 2 la reemplazó por `scripts/teamdb_exec.py` con bound params reales (Python `sqlite3`). El CLI `sqlite3` no soporta bind portablemente; Python sí. `teamdb_safe_query` quedó exportada como deprecated para no romper los tests de Fase 1.
- **flock → transacciones SQLite**: las escrituras concurrentes se resolvieron con `BEGIN IMMEDIATE` + WAL + `busy_timeout` en vez de `flock` (más portable y atómico a nivel DB).
- **Triggers no pueden leer variables de entorno**: el audit log real sale del helper (`actor_source=''helper''` con el actor vía `TEAMDB_ACTOR`); los triggers registran `actor_source=''trigger''` con `''system''`. Los lectores filtran por `actor_source` para atribución real.
- **El bundle `.opencode/context/` de este repo estaba vacío durante el change**: el proposal registró "bundle corrupto, saltando check"; los concept docs se consolidaron recién al cierre (este doc es el primero). No hay contradictores.
- **Deuda detectada y no resuelta en este change**: `tests/spec-memory-link.test.sh` asume VERSION 0.6.2 (fallaba ya antes del bump 0.7.x, riesgo R-F2-6 documentado en receipt de Fase 2); `receipt_fase2_teo.json` quedó con JSON malformado en la línea 177 (verificación de Jhon fue manual, no parseó el archivo).','concept',0,'2026-08-05T20:28:57Z');
INSERT INTO "decisions" ("id","slug","title","body_md","status","decided_at","decided_by") VALUES (1,'grafo-wip-y-decisions-v0.7.6','Grafo de memoria ahora incluye WIP y auto-link decisions→concepts','
# v0.7.6 — Grafo de memoria con WIP y auto-link decisions→concepts

## Contexto

Antes de v0.7.6, el grafo de memoria (`memory_links` + concepts/decisions) NO incluía features/tasks activas de `work_in_progress`. Pol/Teo no veían si una feature ya estaba en curso y duplicaban trabajo.

Además, las decisions no estaban linkeadas automáticamente a los concepts que referenciaban en su `body_md`. Para entender "por qué elegimos PostgreSQL" había que leer todas las decisions y buscar manualmente.

## Decisión

### 1. Incluir WIP en el grafo

- Cada WIP con `type IN (''feature'',''task'')` y `parent_id IS NOT NULL` aparece como nodo en el grafo
- Link `part_of` entre WIP hijo y su parent (task→feature, feature→plan)
- Visible en `/api/graph` del dashboard

### 2. Auto-link decisions → concepts

- Si el `body_md` de una decision menciona el slug de un concept (substring match), se crea link `decision → concept` con `link_type=''references''`, `confidence=0.9`
- Idempotente (no duplica links existentes)
- Riesgo bajo: si un slug contiene `%` o `_` (wildcards de LIKE), podría haber falsos positivos. Por convención los slugs son kebab-case.

### 3. Comando unificado

`teamdb-graph-refresh.sh` corre ambos refreshes (memoria + código) en un solo comando.

### 4. R14 en constitución — ahorro de tokens

R14 ahora formaliza que los 8 agentes DEBEN consultar grafos antes de proponer cambios. Ejemplo cuantificado: Teo ahorra 75% de tokens si consulta el grafo antes de implementar.

## Consecuencias

### Positivas

- Pol/Teo/Jes pueden ver features activas sin abrir la DB
- Pau auto-linkea decisions al consolidar
- Dashboard muestra grafo completo (29 nodos en Infra de muestra)
- Comando `/skalling-graph-refresh` unificado para refresh on-demand

### Negativas / Riesgos

- LIKE substring search es O(n*m) — aceptable porque decisions son pocas
- Schema migration 008 puede ser frágil si se interrumpe a mitad (mitigado por `|| true` en init)
- Link huérfano histórico detectado y limpiado (id=56, preservado en backup)

## Tests

- `tests/teamdb-link.test.sh`: 11/11 PASS
- Caso C10 nuevo: "R4 no crea part_of entre concepts" — invariante R4

## Artefactos

- `sql/migrations/008_extend_link_types.sql`
- `scripts/teamdb-link.sh` (R4 + R5)
- `scripts/teamdb-graph-refresh.sh` (nuevo)
- `scripts/dashboard-server.py` (refactor)
- `command/skalling-graph-refresh.md` (nuevo)
- `constitucion/constitucion.md` (R14 ampliado)
- `agents-base/*.md` (8 archivos con sección de grafos)','accepted','2026-08-05','Pau (consolidación v0.7.6)');
INSERT INTO "decisions" ("id","slug","title","body_md","status","decided_at","decided_by") VALUES (2,'plan-unico-versionado-v0.7.7','Plan único versionado (v0.7.7)','
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
- `tasks`: agrega `purpose TEXT NOT NULL DEFAULT ''''`.
- 2 audit triggers sobre `plans` (insert + update) registran en `audit_log`.
- `schema_meta.version = ''0.7.7''`.

## Scripts

- `teamdb-plan.sh --strict-contract --purpose=... --acceptance=...`: crea plan atómicamente, rechaza tasks sin propósito/AC, rechaza títulos poéticos.
- `teamdb-amend.sh --slug=<slug> [--add-task=<json>] [--design-stdin]`: UPDATE del plan, bumpea `version`, append a `plan_history` con `operation=''amended''`. `--add-task` exige `--purpose`.
- `teamdb-execute-plan.sh`: rechaza ejecución si `status NOT IN (''approved'',''in_progress'')`.

## Agentes

- `Pol.md`: regla explícita "NO escribir archivos `.md` de plan. SOLO INSERT en `proposals` via `teamdb-plan.sh`."
- `Sol.md`: regla "Cuando recibís handoff de Pol con `proposals.status=''approved''`, hacés UPDATE del plan existente (`teamdb-amend.sh`), NO creás otro."
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

- Migración de planes `.md` viejos a la DB (Bloque 4): los `.md` ya existentes en `.opencode/changes/` se importan con sufijo `-legacy-imported` y `decided_by=''legacy-import''`. Idempotente.
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
5. `chore(db): persistencia de los 3 nuevos proposals + export legible`','accepted','','user');
INSERT INTO "preferences" ("id","slug","scope","scope_value","body_md","confidence","source") VALUES (1,'slugs-kebab-case','project',NULL,'
# Slugs siempre en kebab-case

Convención del proyecto: todos los slugs de concepts/decisions/preferences/problems/wip son kebab-case (lowercase + guiones). Ejemplos:
- ✅ `modulo-app`, `stack-postgres`, `auth-jwt`, `feat-login-jwt`
- ❌ `moduloApp`, `modulo_app`, `ModuloApp`, `modulo.app`

## Por qué

1. **SQL safe**: kebab-case no contiene `%`, `_` ni otros wildcards de LIKE. Importante para R5 de `teamdb-link.sh` que hace substring match.
2. **URL safe**: kebab-case es la convención para URLs y slugs.
3. **Multi-lenguaje**: funciona en bash, python, JS sin quoting especial.

## Regla

Si vas a crear un slug nuevo, usá solo letras minúsculas, números y guiones.','','Preference');
INSERT INTO "known_problems" ("id","slug","title","symptom_md","workaround_md","status","discovered_at","resolved_at") VALUES (1,'like-substring-false-positives','LIKE substring match puede generar falsos positivos en auto-link decisions→concepts','
# LIKE substring match — riesgo de falsos positivos

## Síntoma

R5 de `teamdb-link.sh` usa `body_md LIKE ''%'' || slug || ''%''` para detectar menciones de concepts en decisions. Si un slug contiene `%` o `_` (wildcards de SQL LIKE), podría matchear con texto que no es realmente una mención.

## Causa raíz

SQL LIKE trata `%` (cualquier secuencia) y `_` (cualquier carácter) como wildcards. La query actual no los escapa.

## Workaround

Convención del proyecto: todos los slugs son kebab-case (ej: `modulo-app`, `stack-postgres`, `auth-jwt`). No se usan `%`, `_` ni otros caracteres especiales en slugs.

## Fix futuro (no aplicado)

Cambiar la query a `instr(body_md, slug) > 0` (substring search sin wildcards) o escapar con `replace(replace(slug, ''%'', ''\%''), ''_'', ''\_'')`.

## Severidad

Baja. No bloqueante. Solo aplica si alguien rompe la convención de slugs.','|','open','2026-08-05',NULL);
INSERT INTO "work_in_progress" ("id","slug","type","parent_id","title","description","status","priority","owner","body_md","acceptance_md","resolution_md","created_at","updated_at","resolved_at") VALUES (1,'followup-v0.6.0','plan',NULL,'Follow-ups para v0.6.0','# Follow-ups para v0.6.0

Hallazgos menores pendientes del Quality Gate de v0.5.0 (drift detection).

## Pendientes

1. **`setup.sh:31` tiene `SKALLING_VERSION="0.1.0"` stale.** Bumpear a `"0.5.0"` (o','open',3,NULL,'# Follow-ups para v0.6.0

Hallazgos menores pendientes del Quality Gate de v0.5.0 (drift detection).

## Pendientes

1. **`setup.sh:31` tiene `SKALLING_VERSION="0.1.0"` stale.** Bumpear a `"0.5.0"` (o versión actual al momento del fix). No afecta funcionalidad, solo display.

## Origen

Luz — Quality Gate del release v0.5.0 (drift detection), release commit `ff7f4e1`.

## Estado del release

- Tag: `v0.5.0` pusheado contra origin
- 458 tests PASS, doctor exit 0
- Quality Gate: PASSED',NULL,NULL,'2026-08-20T15:36:43Z','2026-08-20T15:36:43Z',NULL);
INSERT INTO "work_in_progress" ("id","slug","type","parent_id","title","description","status","priority","owner","body_md","acceptance_md","resolution_md","created_at","updated_at","resolved_at") VALUES (2,'followup-v0.7.2','plan',NULL,'Follow-ups para v0.7.2','# Follow-ups para v0.7.2

Hallazgos menores pendientes del Quality Gate de v0.7.2 (teamdb-hardening) y observaciones de cierre.

## Pendientes

1. **`templates/handoff.schema.json` — `verification: ','open',3,NULL,'# Follow-ups para v0.7.2

Hallazgos menores pendientes del Quality Gate de v0.7.2 (teamdb-hardening) y observaciones de cierre.

## Pendientes

1. **`templates/handoff.schema.json` — `verification: {}` vacío sigue siendo aceptado.** Requerir `type`/`command`/`exit_code` internos para que la validación de handoffs sea estricta de verdad.
2. **`scripts/teamdb-search.sh:26` — validación de tipo con `grep -q " $ARG2 "` (regex).** `[a-z]` como ARG2 matchea inesperadamente. Usar `case` o `grep -F`.
3. **`scripts/teamdb-search.sh:83` — sanitización FTS5 blacklist incompleta.** Sin riesgo real: los params van bound.
4. **`install-global.sh:220` — `printf ''%s\n''` agrega newline extra** si el contenido ya termina en newline (cosmético).
5. **`receipt_fase2_teo.json` (en `.opencode/changes/archive/2026-08/teamdb-hardening/receipts/`) está malformado** — JSON inválido (error de delimitador ~línea 177). Regenerar en próxima iteración (no bloqueó: Jhon verificó manualmente).
6. **CHANGELOG salta de v0.7.0 a v0.7.2** — el commit `7701af3` dice "teamdb v0.7.1" pero no hay entrada v0.7.1 en CHANGELOG ni tags v0.7.0/v0.7.1. Decidir si agregar entrada retroactiva.
7. **Mantenimiento (Luz, no urgente): `teamdb-amend.sh` invoca python3 4 veces por operación** (3 × json.dumps + 1 heredoc). Si se optimiza, NO volver a `IFS=''|''`; el patrón JSON es el correcto.

## Origen

Luz — re-auditoría del release v0.7.2 (teamdb-hardening) + observaciones de cierre de Pau.

## Estado del release

- Commits: `9d3f120`, `84226b3`, `cfbf3f3`, `6ad8944`, `9e56b79` en rama `teamdb`
- Regresión: 45/45
- Quality Gate: PASSED',NULL,NULL,'2026-08-20T15:36:43Z','2026-08-20T15:36:43Z',NULL);
INSERT INTO "memory_links" ("id","from_table","from_id","to_table","to_id","link_type","confidence") VALUES (1,'decisions',1,'concepts',1,'references',0.9);
INSERT INTO "memory_links" ("id","from_table","from_id","to_table","to_id","link_type","confidence") VALUES (2,'decisions',2,'concepts',1,'references',0.9);
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (1,'agentes-db-primera-2026-08-06-legacy-imported','Protocolo DB-primera: agentes consultan team.db antes de leer el proyecto','# Protocolo DB-primera: agentes consultan team.db antes de leer el proyecto

**Slug:** agentes-db-primera-2026-08-06
**Status:** approved
**Agent:** pol
**Fecha:** 2026-08-06 13:19:03

## Contexto

Hoy cuando un usuario pide un plan, los agentes Alex/Pol/Sol/Teo leen 5-10 archivos del proyecto para entender qué existe, en lugar de consultar la tabla concepts de team.db. Aunque hay una regla soft en constitución R14 "consultá la DB primero", no se enforce.

## Causa raíz

Los agentes LLMs ignoran instrucciones narrativas cuando tienen un read/grep tentador disponible. La DB requiere esfuerzo explícito (`teamdb-search.sh "<query>"`), leer un archivo requiere 1 click.

## Decisión

Reemplazamos la sección soft "Grafos del proyecto — cómo y cuándo consultarlos" en los 4 agentes del ciclo SDD (Alex, Pol, Sol, Teo) por un **protocolo numerado concreto**:

1. **Pasos bash numerados**: Paso 1 = `bash teamdb-search.sh "<query>" concept|decision`, Paso 2 = leer `teamdb-related.sh` de slugs relevantes, Paso 3 (opcional) = `curl /api/codegraph`.
2. **Regla de oro**: si la DB alcanzó, NO leer más.
3. **CITA obligatoria**: en el artefacto/handoff (proposal.md, tasks.md, commit), el agente debe citar textualmente el resultado de la consulta DB (cuántos concepts, cuántos decisions, qué encontró).

## Tasks completadas

- [x] Reescribir sección de cada agente con protocolo numerado (Teo, 4 agentes)
- [x] Agregar test FIX 1.3 con 12 asserts en setup.test.sh (Teo)
- [x] Sincronizar agentes a ~/.config/opencode/agents/ (Teo)
- [x] Inicializar team.db en meta-proyecto (con backup + dry-run)
- [x] Persistir propuesta en DB (este INSERT)

## Consecuencias

### Positivas
- Ahorro de tokens estimado: 60-75% por plan
- Consistencia: el sistema usa la memoria que ya documentamos
- Tests verifican que cada agente tiene el protocolo (12 asserts FIX 1.3)

### Negativas / Riesgos
- Si la DB está vacía, los agentes igualmente intentan leer código (esperado, es el fallback)
- Tests no garantizan que el LLM siga el protocolo al pie de la letra (es soft-enforcement)
- Hay 3 menciones de superpowers:* restantes en systematic-debugging/SKILL.md que requieren evaluación caso por caso',NULL,'draft','pol','legacy-import','2026-08-20T15:36:46Z','2026-08-20T15:36:46Z',NULL);
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (2,'fix-skills-docs-plans-2026-08-06-legacy-imported','Proposal: fix-skills-docs-plans-2026-08-06','<!-- GENERATED from teamdb on 2026-08-06T05:01:40Z. DO NOT EDIT. Source of truth: .opencode/context/team.db.
     Bidirectional is PROHIBITED. To update DB: sqlite3 $DB (proposals table).
     To regenerate: bash scripts/teamdb-export-md.sh . -->

# Proposal: fix-skills-docs-plans-2026-08-06

- **Slug:** fix-skills-docs-plans-2026-08-06
- **Title:** Fix: skills brainstorming y writing-plans deben guardar en DB, no en docs/plans/
- **Status:** draft
- **Agent:** pol
- **Created:** 2026-08-06 05:01:08

## Intent

## Contexto

Las 2 skills copiadas de Superpowers (brainstorming, writing-plans) todavía tienen paths legacy (`docs/plans/`) y referencias externas (`superpowers:*`). El protocolo Skalling v0.7+ exige que TODO se guarde en la DB (`.opencode/context/team.db`) como source of truth, y SOLO se exporte a `.md` cuando es para git legible.

## Causa raíz

- Skills copiadas parcialmente en versiones tempranas
- Mismo bug que Sol.md/Teo.md tenían pre-0.6.2 (ya parcheado, ver CHANGELOG)
- Nunca se extendió el fix a las skills
- Tests/setup.test.sh Tier 1 FIX 1.1 lo valida para agentes pero no para skills

## Solución propuesta

### Skill 1: brainstorming/SKILL.md
- ELIMINAR: "Write the validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`"
- ELIMINAR: refs a `superpowers:using-git-worktrees`, `superpowers:writing-plans`
- REEMPLAZAR por: "Pol devuelve proposal validado a Alex. Source of truth: tabla `proposals` en team.db (vía `teamdb_write_project`). El export `.md` se genera on-demand con `teamdb_export_md`, no es storage primario."

### Skill 2: writing-plans/SKILL.md
- ELIMINAR: refs a `docs/plans/` (líneas 18, 101)
- ELIMINAR: refs a `superpowers:*` (líneas 36, 110, 116)
- REEMPLAZAR por: "Sol escribe `design.md` y `tasks.md` después de INSERT en DB vía `teamdb-plan.sh`. Source of truth: tabla `plans` + `tasks` en team.db."

### Tests nuevos (en tests/setup.test.sh)
- `test_skills_no_docs_plans`: assert NO `docs/plans` en ninguna SKILL.md
- `test_skills_no_superpowers`: assert NO `superpowers:` (excepto whitelist explícita)
- `test_brainstorming_uses_db`: assert que menciona `team.db` o `teamdb_write_project`

## Tasks

- [ ] Reescribir brainstorming/SKILL.md
- [ ] Reescribir writing-plans/SKILL.md
- [ ] Agregar 3 tests en tests/setup.test.sh
- [ ] Correr `bash install-global.sh --force` para distribuir
- [ ] Verificar que ningún proyecto use el path legacy

## Consecuencias

### Positivas
- TODO el flujo de brainstorming va a la DB, no al filesystem
- Consistencia con el resto del sistema
- Rastreable, versionado, auditable
- Backup automático ya aplica (v0.7.6)

### Negativas / Riesgos
- Si algún proyecto cliente tiene archivos en `docs/plans/` viejos, hay que migrarlos manualmente con `teamdb-plan.sh` por cada uno
- Hay 3 menciones de `superpowers:` en `systematic-debugging/SKILL.md` que hay que evaluar caso por caso

## Related

- CHANGELOG 0.6.2: fix similar aplicado a Sol.md/Teo.md
- tests/setup.test.sh FIX 1.1: patrón Tier 1 a replicar
- constitution R6: ubicación canónica `.opencode/changes/<feature-slug>/`


<!-- Footer: regenerar desde DB con scripts/teamdb-export-md.sh -->',NULL,'draft','pol','legacy-import','2026-08-20T15:36:46Z','2026-08-20T15:36:46Z',NULL);
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (3,'plan-unico-versionado-2026-08-06-legacy-imported','Plan único versionado: 1 proposal → 1 plan → N tasks ejecutables, todo en DB','# Plan único versionado: 1 proposal → 1 plan → N tasks ejecutables, todo en DB

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

1. **1 plan por feature-slug**. Constraint: `UNIQUE(slug WHERE status IN (''draft'',''approved'',''in_progress''))` — solo puede haber UNO activo a la vez. Si se quiere un nuevo intento, el viejo pasa a `abandoned` (no se borra; queda en `audit_log`).
2. **Source of truth = DB**. El artefacto canónico es la fila de la tabla (`proposals`, `plans`, `tasks`). El `.md` en `.opencode/changes/<slug>/` se regenera con `teamdb-export-md.sh` y SIEMPRE lleva header `<!-- GENERATED -->`. Editar el `.md` está prohibido y se detecta con diff contra la DB.
3. **Lifecycle explícito**: `draft → approved → in_progress → completed`. Transiciones registradas en `audit_log` (ya hay triggers en `tasks`, falta en `plans`).
4. **Pol escribe el `proposal`** (intención validada, no muy detallado). Status inicial: `draft`.
5. **Sol hace UPDATE del mismo plan**, no crea otro. Cuando necesita más detalle técnico, edita `plans.design_md` + agrega `specs` + `design_notes`. El plan pasa a `approved` cuando Pol/user lo firma.
6. **Pol NO borra el plan de Sol**. Solo puede agregar otra versión (incrementar `plans.version`, append a `plan_history` con `operation=''amended''`).
7. **Teo busca el plan activo por slug en la DB y lo sigue**. Comando: `teamdb-execute-plan.sh <project> --slug=<slug>`. NO inventa otro. NO lee `.md` para "interpretar".
8. **Tasks con contrato**: cada task tiene `purpose` (1-2 frases por qué existe) + `acceptance_md` (criterios verificables) + `order_index` (entero, orden de ejecución) + DAG via `task_dependencies` (FK a otras tasks del mismo plan). Títulos NO poéticos: `"Migrar plans.design_md a nullable"` no `"Gimme Shelter"`.

### Responsabilidades por agente

| Agente | Responsabilidad | Acción sobre la DB |
|---|---|---|
| **Pol** | Validar intent, escribir `proposal` | `INSERT proposals(status=''draft'')`. No toca `plans`. |
| **Sol** | Mejorar plan técnico, definir tasks | `UPDATE plans(design_md, version+=1)`, `INSERT specs`, `INSERT tasks`, `INSERT task_dependencies`. Status: `draft → approved`. |
| **Teo** | Ejecutar tasks | `SELECT tasks WHERE plan_id=? ORDER BY order_index`, claim con `task_claims`, `UPDATE tasks(status=''in_progress'')`. |
| **Luz** | Verificar AC de cada task | `UPDATE tasks(status=''in_review'', resolution_md=''...'')`. |
| **Pau** | Cerrar feature | `UPDATE plans(status=''completed'')` cuando todas las tasks están `approved`. |

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
  design_md TEXT NOT NULL DEFAULT '''',
  acceptance_md TEXT,
  status TEXT DEFAULT ''draft'' CHECK(status IN (''draft'',''approved'',''in_progress'',''completed'',''abandoned'')),
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
  purpose TEXT NOT NULL DEFAULT '''',        -- NUEVO: por qué existe (1-2 frases)
  description_md TEXT,                     -- LEGACY: detalles extendidos, opcional
  acceptance_md TEXT NOT NULL DEFAULT '''',  -- ENFORCE: obligatorio (CHECK en aplicación)
  status TEXT DEFAULT ''pending'' CHECK(status IN (''pending'',''in_progress'',''in_review'',''approved'',''resolved'',''rejected'',''blocked'')),
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
SELECT id, plan_id, slug, title, '''' AS purpose, description_md, COALESCE(acceptance_md, ''''),
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
  VALUES (datetime(''now''), ''system'', ''insert'', ''plans'', new.id,
          json_object(''slug'', new.slug, ''status'', new.status), ''trigger'');
END;
CREATE TRIGGER plans_audit_au AFTER UPDATE ON plans BEGIN
  INSERT INTO audit_log (ts, agent, action, table_name, row_id, details, actor_source)
  VALUES (datetime(''now''), ''system'', ''update'', ''plans'', new.id,
          json_object(''slug'', new.slug, ''old_status'', old.status, ''new_status'', new.status, ''version'', new.version), ''trigger'');
END;

COMMIT;
PRAGMA foreign_keys=ON;

UPDATE schema_meta SET value = ''0.7.7'' WHERE key = ''version'';
```

### Cambios en scripts

| Script | Cambio |
|---|---|
| `teamdb-plan.sh` | Al crear plan, copiar `proposal.intent_md` → `plan.intent_md`. Al insertar task, exigir `purpose` no vacío + `acceptance_md` no vacío (fail-fast con mensaje claro). |
| `teamdb-amend.sh` | Nuevo: UPDATE del plan existente (incrementa `version`, append a `plan_history` con `operation=''amended''`). |
| `teamdb-plan.sh` (subcomando) | Agregar `--improve` para que Sol pueda llamar al mismo script en modo UPDATE, no solo CREATE. |
| `teamdb-export-md.sh` | Refrescar header: incluir `purpose` de cada task en `tasks.md`, no solo título. |
| `teamdb-execute-plan.sh` | Si el plan está en `draft`, abortar con error claro: "Plan no aprobado. Status actual: draft. Necesita status=''approved'' para ejecutar." |

### Cambios en agentes (protocol)

| Agente | Cambio |
|---|---|
| `agents-base/Pol.md` | Regla: "NO escribir archivos `.md` de plan. SOLO INSERT en `proposals`. El `.md` se regenera con `teamdb-export-md.sh`." |
| `agents-base/Sol.md` | Regla: "Cuando recibís un handoff de Pol con `proposal.status=''approved''`, hacés UPDATE del plan existente (`teamdb-amend.sh`), NO creás otro. Incrementás `version`. Si necesitás romper compatibilidad, creás un plan nuevo con `status=''draft''` y el viejo pasa a `abandoned`." |
| `agents-base/Teo.md` | Regla: "Antes de ejecutar, `teamdb-execute-plan.sh <project> --slug=<slug>`. Si no hay plan activo, ABORT y escalar a Alex. NO inventar plan propio." |
| `agents-base/Luz.md` | Regla: "Verificás cada task contra su `acceptance_md`. Si pasa, marcás `status=''approved''` + `resolution_md` con evidencia. Si falla, `status=''rejected''` + razón." |
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
  - [ ] Audit triggers sobre `plans` existen (`SELECT name FROM sqlite_master WHERE type=''trigger'' AND tbl_name=''plans''`)
  - [ ] `schema_meta.version = ''0.7.7''`
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
  - [ ] Sección "Mejorar plan, no crear otro" en Sol.md menciona: "Cuando `proposals.status=''approved''`, usar `teamdb-amend.sh`, NO `teamdb-plan.sh create`"
  - [ ] Comando documentado: `teamdb-amend.sh <project> --slug=<slug> --design-stdin --add-task=<task.json>`
  - [ ] Test: `test_sol_uses_amend` (busca `teamdb-amend.sh` en Sol.md → debe aparecer ≥1 vez)
  - [ ] Sincronizado a `~/.config/opencode/agents/Sol.md`
- **depends_on**: Task 1

### Task 4: Actualizar agents-base/Teo.md (lee DB, no inventa)
- **purpose**: Que Teo consulte el plan activo por slug antes de ejecutar, en vez de improvisar.
- **acceptance_criteria**:
  - [ ] Sección "Pre-ejecución" en Teo.md: "Paso 1: `teamdb-execute-plan.sh <project> --slug=<slug> --dry-run`. Si retorna error ''no active plan'', ABORT."
  - [ ] Comando `teamdb-execute-plan.sh` rechazada ejecución si `plans.status NOT IN (''approved'',''in_progress'')`
  - [ ] Test: `test_teo_queries_db_first` (assert Teo.md contiene `teamdb-execute-plan.sh`)
  - [ ] Sincronizado a `~/.config/opencode/agents/Teo.md`
- **depends_on**: Task 1, Task 3

### Task 5: Extender teamdb-plan.sh + crear teamdb-amend.sh
- **purpose**: Dar herramientas bash que enforce "1 plan por slug" y "tasks con purpose+AC".
- **acceptance_criteria**:
  - [ ] `teamdb-plan.sh create`: al crear plan, copia `proposal.intent_md` → `plan.intent_md`. Si task no tiene `purpose` o `acceptance_md`, falla con mensaje claro: "task ''<slug>'' sin purpose o acceptance_md"
  - [ ] `teamdb-amend.sh <project> --slug=<slug>`: hace UPDATE del plan, incrementa `version`, append a `plan_history` con `operation=''amended''`
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
  - [ ] Paso "Output" del workflow dice: "INSERT en `proposals` (status=''draft''). El export `.md` es secundario."
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

<!-- Footer: regenerar desde DB con teamdb-export-md.sh -->',NULL,'draft','pol','legacy-import','2026-08-20T15:36:47Z','2026-08-20T15:36:47Z',NULL);
INSERT INTO "plans" ("id","slug","title","proposal_id","design_md","acceptance_md","status","agent","created_at","updated_at","completed_at","intent_md","version","created_by","updated_by") VALUES (1,'audit-v0.9.3','Audit fixes v0.9.3',NULL,'System audit fixes',NULL,'completed','system','2026-08-20 15:49:21','2026-08-20 15:49:21',NULL,NULL,1,'system',NULL);
INSERT INTO "tasks" ("id","plan_id","slug","title","description_md","acceptance_md","status","priority","owner","blocked_reason","resolution_md","order_index","estimated_minutes","due_date","created_at","updated_at","started_at","resolved_at","version","locked_by","locked_at","last_modified_by","purpose") VALUES (1,1,'audit-fix-v0.9.3','Audit fixes v0.9.3',NULL,'All violations fixed','resolved',3,'system',NULL,NULL,0,NULL,NULL,'2026-08-20 15:49:21','2026-08-20 15:49:21',NULL,NULL,1,NULL,NULL,NULL,'Fix DB-first compliance, install hooks, migrate .md to DB, optimize N+1 queries');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('audit-fix-20260820114921','1','system','audit-fixes',0,NULL,'2026-08-20 15:49:21','1377f76c6380ec93');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('db-verification-20260821083400','1','system','db-verification',0,NULL,'2026-08-21 12:34:00','06ee42a4f6655e7e');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('rcpt_1787317371_64271','review','luz','review --lens all',0,'{"risk":{"blocker":0,"warning":0},"resilience":{"blocker":0,"warning":0},"readability":{"blocker":0,"warning":0},"reliability":{"blocker":0,"warning":0},"total":0,"tree_hash":"d2c11151a604d8d1"}','2026-08-21 13:02:51','d2c11151a604d8d1');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('rcpt_1787317449_64891','review','luz','review --lens all',0,'{"risk":{"blocker":0,"warning":0},"resilience":{"blocker":0,"warning":1},"readability":{"blocker":0,"warning":2},"reliability":{"blocker":0,"warning":0},"total":3,"tree_hash":"7be15a6ac6a44a15"}','2026-08-21 13:04:10','e3b0c44298fc1c14');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('rcpt_1787322766_15449','db-fix','alex','db-first-permissions-fix',0,'{"fix":"permissions deny var-folders, routing DB-first, plan stdin"}','2026-08-21 14:32:46','6be4697999acd4c5');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('rcpt_1787322784_15771','db-fix2','alex','db-first-fix-commit',0,'{"fix":"permissions deny var-folders, routing DB-first, plan stdin"}','2026-08-21 14:33:04','f0988045e7741db0');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('setup-fix-20260820122521','1','system','setup-install-test',0,NULL,'2026-08-20 16:25:21','4b502a1f3c7498c1');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('setup-v093-20260821082814','1','system','setup-v093',0,NULL,'2026-08-21 12:28:14','801bcbf8bbc8769b');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('setup-v093-20260821082821','1','system','setup-v093',0,NULL,'2026-08-21 12:28:21','801bcbf8bbc8769b');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('setup-v093-20260821082827','1','system','setup-v093',0,NULL,'2026-08-21 12:28:27','88e1871349a7a631');
