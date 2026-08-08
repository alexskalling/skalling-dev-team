-- teamdb dump v1
-- Generado por teamdb-dump.sh. NO editar a mano; el diff se mergea por fila.
-- Source of truth: .opencode/context/team.db (la DB local). Este archivo es su fotografía.
INSERT INTO "decisions" ("id","slug","title","body_md","status","decided_at","decided_by") VALUES (1,'protocolo-db-primera-2026-08-06','DB-primera: agentes consultan team.db antes de leer el proyecto','## Contexto

Antes, los agentes leían 5-10 archivos del proyecto para entender qué existe. Las reglas soft no se enforced.

## Decisión

Reemplazamos la sección soft "Grafos del proyecto" en los 4 agentes por un protocolo numerado concreto:

- Pasos bash numerados (Paso 1 = teamdb-search, Paso 2 = teamdb-related)
- Regla de oro: si la DB alcanzó, NO leer más
- CITA obligatoria del resultado en el artefacto

## Tasks verificadas

- ✅ Reescribir 4 agentes con protocolo numerado
- ✅ Test FIX 1.3 con 12 asserts (192/192 PASS)
- ✅ Sincronizar a ~/.config/opencode/agents/

## Consecuencias

- Ahorro de tokens: 60-75% por plan
- Consistencia con memoria indexada
- Tests no pueden enforced que el LLM siga el protocolo (soft-enforcement)','accepted','2026-08-06 13:20:19','pau');
INSERT INTO "preferences" ("id","slug","scope","scope_value","body_md","confidence","source") VALUES (1,'protocolo-db-primera-preferido','agents-sdd','alex,pol,sol,teo','Todos los agentes del ciclo SDD (Alex/Pol/Sol/Teo) deben seguir el protocolo DB-primera documentado en agents-base/. La DB es la fuente de verdad. El código se lee SOLO si la DB no alcanza.',0.9,'protocolo-db-primera-2026-08-06');
INSERT INTO "preferences" ("id","slug","scope","scope_value","body_md","confidence","source") VALUES (2,'agentes-eficientes-y-criticos-2026-08-06','agents-sdd','alex,pol,jes,sol,teo,jhon,luz,pau','## Principios operativos no negociables (feedback usuario 2026-08-06)

### Ser inteligente, crítico y analítico ANTES de actuar

Antes de empezar cualquier tarea, el agente DEBE:

1. **Entender el problema a fondo**. No asumir lo que el usuario quiere. Si hay ambigüedad en el pedido, hacer 1 pregunta concreta con opciones A/B/C — NO salir a tocar 10 archivos.

2. **Clasificar el scope correctamente**:
   - Cambio de 1 línea → entrega de 1 línea (1 delegación, máximo)
   - Cambio chico (3-5 archivos, scope claro) → INLINE route (delegación directa a Teo)
   - Feature grande (sin aclarar) → preguntar al usuario antes de arrancar
   - "Auditoría" o "Revisión completa" → SOLO si el usuario lo pide EXPLÍCITAMENTE

3. **Pensar antes de gastar tokens**. Cada tool call, cada delegación al LLM, cada lectura de archivo consume el dinero del usuario. Si una acción NO contribuye directamente a entregar lo que el usuario pidió en este turno, es desperdicio.

4. **Ser crítico con la propia propuesta**. Antes de delegar, el agente DEBE auto-cuestionarse: "¿esto es lo mínimo necesario? ¿estoy agregando cosas que no me pidieron? ¿estoy asumiendo?". Si la respuesta es sí a cualquiera, PARA y reformula.

5. **Reconocer la propia ignorancia**. Si el agente no entendió el pedido, NO inventar. Preguntar con opciones concretas. Decir "no sé qué archivo" en vez de grep-ar todo el proyecto.

### Patrón Scope Lock (obligatorio en cada delegación)

ANTES de delegar al sub-agente, escribir literalmente estas 2 líneas:

```
Scope: voy a hacer [X].
No voy a hacer: [Y, Z, W].
```

Cada tool call posterior DEBE estar en [X]. Si no está → parar y avisar al usuario.

Si el sub-agente (Teo, Pol, Sol) hace algo fuera de [X] → ABORT y avisar.

### Orden de trabajo

1. Implementar el cambio concreto (lo que el usuario pidió)
2. Probar que funciona (test) — OBLIGATORIO antes de cualquier otra cosa
3. Si pasa el test → ahí SÍ: documentar, migrar, sincronizar, commitear, pushear — CADA UNO solo si el usuario lo pidió explícitamente

No se acepta: cambio → saltar test → directo a docs/commits → "ya está todo verde"

### Anti-patrones explícitos

- ❌ Auditar el sistema completo cuando el usuario pidió agregar 1 filtro
- ❌ Crear migraciones de DB para cambios de UI
- ❌ Reescribir otros agentes o skills "de paso"
- ❌ Commitear y pushear sin que el usuario lo pida (R17)
- ❌ Sobredimensionar: tratar 1 línea como proyecto de 2 horas
- ❌ "De paso aprovecho para...": CADA acción extra debe ser solicitada explícitamente
- ❌ Inventar archivos de preflight, hooks, o cualquier cosa auxiliar sin que el usuario lo apruebe',0.95,'feedback-usuario-2026-08-06-sobredimension');
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (1,'fix-skills-docs-plans-2026-08-06','Fix: skills brainstorming y writing-plans deben guardar en DB, no en docs/plans/','## Contexto

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
',NULL,'draft','pol',NULL,'2026-08-06 05:01:08','2026-08-06 05:01:08',NULL);
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (2,'agentes-db-primera-2026-08-06','Protocolo DB-primera: agentes consultan team.db antes de leer el proyecto','## Contexto

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
- Hay 3 menciones de superpowers:* restantes en systematic-debugging/SKILL.md que requieren evaluación caso por caso',NULL,'approved','pol',NULL,'2026-08-06 13:19:03','2026-08-06 13:19:03',NULL);
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (3,'plan-unico-versionado-2026-08-06','Plan único versionado: 1 proposal → 1 plan → N tasks ejecutables, todo en DB','# Plan único versionado: 1 proposal → 1 plan → N tasks ejecutables, todo en DB

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

- **Falta enforcement de "1 plan por slug activo"**. `plans.slug` es `UNIQUE`, pero nada impide que haya un plan `draft` y otro `active` para el mismo slug simultáneamente.
- **No hay lifecycle formal**. `plans.status` acepta `draft|active|completed|abandoned`. Falta `approved` e `in_progress` para representar el flujo real.
- **`tasks.purpose` no existe**. Solo hay `title` + `description_md`.
- **`plans.intent_md` no existe**. Solo `design_md`. La intención validada por Pol queda huérfana del plan una vez que Sol lo "toma".
- **`plans.version` no existe**. `plan_history` tiene `version` pero `plans` no.

## Decisión

**Un solo plan semántico por feature-slug, viviendo en la DB. Los archivos `.md` son SOLO exports legibles para git, no contratos.**

### Reglas duras

1. **1 plan por feature-slug activo**. Solo puede haber UNO en estado `draft|approved|in_progress` simultáneamente. Si se quiere un nuevo intento, el viejo pasa a `abandoned`.
2. **Source of truth = DB**. La fila es el contrato. El `.md` se regenera con `teamdb-export-md.sh` y lleva header `<!-- GENERATED -->`.
3. **Lifecycle explícito**: `draft → approved → in_progress → completed`. Transiciones en `audit_log`.
4. **Pol escribe el `proposal`** (intención validada). Status: `draft`.
5. **Sol hace UPDATE del mismo plan** (no crea OTRO). Status: `draft → approved`.
6. **Pol NO borra el plan de Sol**. Solo puede agregar otra versión (`plan_history`, `operation=amended`).
7. **Teo busca el plan activo por slug** vía `teamdb-execute-plan.sh --slug=<slug>`. NO inventa otro. NO lee `.md` para "interpretar".
8. **Tasks con contrato**: `purpose` (1-2 frases) + `acceptance_md` (criterios verificables) + `order_index` + DAG via `task_dependencies`. Títulos NO poéticos.

### Schema propuesto (migration 009)

> Las tablas `plans` y `tasks` YA EXISTEN (migration 002). Approach: ALTER TABLE + nuevas constraints.

La migration agrega a `plans`: `intent_md`, `version`, `created_by`, `updated_by`, y cambia `status` a CHECK con los 5 estados del lifecycle (incluyendo `in_progress` en lugar de `active`).

A `tasks` le agrega: `purpose` (NOT NULL después de la migration, con valor por defecto razonable para rows existentes), y constraint CHECK sobre `status` con todos los estados posibles (open, in_progress, in_review, completed, abandoned).

### Responsabilidades por agente

| Agente | Acción sobre la DB |
|---|---|
| **Pol** | INSERT proposals(status=draft). No toca plans. |
| **Sol** | UPDATE plans(design_md, version+=1), INSERT specs, INSERT tasks, INSERT task_dependencies. Status: draft → approved. |
| **Teo** | SELECT tasks WHERE plan_id=? ORDER BY order_index, claim con task_claims. |
| **Luz** | UPDATE tasks(status=in_review → approved/rejected). |
| **Pau** | UPDATE plans(status=completed) cuando todas las tasks están approved. |

### Cambios en scripts

| Script | Cambio |
|---|---|
| `teamdb-plan.sh` | Al crear, copiar `proposal.intent_md` → `plan.intent_md`. Validar `purpose` y `acceptance_md` no vacíos. |
| `teamdb-amend.sh` (nuevo) | UPDATE del plan existente, incrementa `version`, append a `plan_history` con `operation=amended`. |
| `teamdb-plan.sh --improve` | Nuevo subcomando para que Sol use el mismo script en modo UPDATE. |
| `teamdb-export-md.sh` | Incluir `purpose` de cada task en `tasks.md`. |
| `teamdb-execute-plan.sh` | Rechazar si `plans.status NOT IN (approved, in_progress)`. |

### Cambios en agentes

- **Pol.md**: "NO escribir `.opencode/changes/<slug>/proposal.md`. Solo INSERT en `proposals`."
- **Sol.md**: "Cuando `proposals.status=approved`, usar `teamdb-amend.sh`, NO `teamdb-plan.sh create`."
- **Teo.md**: "Paso 1: `teamdb-execute-plan.sh --dry-run --slug=<slug>`. Si retorna error, ABORT."
- **Luz.md**: "Verificar cada task contra `acceptance_md`."
- **Alex.md**: "Pasar `proposal_id` o `plan_id` a Sol, no el path al `.md`."

### Cambios en skills

- `skills-base/writing-plans/SKILL.md`: reescribir para usar `teamdb-plan.sh --improve` y `teamdb-amend.sh`. Sin refs a `docs/plans/`.
- `skills-base/brainstorming/SKILL.md`: reforzar que el output es INSERT en `proposals`.

## Tasks (ordenadas)

1. **Crear migration 009** (`plans.intent_md`, `plans.version`, `tasks.purpose`, audit triggers).
2. **Actualizar Pol.md**: no crear archivos `.md` de plan.
3. **Actualizar Sol.md**: UPDATE no CREATE.
4. **Actualizar Teo.md**: lee DB, no inventa.
5. **Extender `teamdb-plan.sh`** + crear **`teamdb-amend.sh`**.
6. **Tests FIX 1.4**: invariantes (1 plan activo por slug, tasks con purpose+AC, lifecycle).
7. **Skill `writing-plans`**: reescribir para usar teamdb.
8. **Migrar planes `.md` viejos** a la DB.

(Detalle completo de cada task con purpose + acceptance_criteria + depends_on en proposal.md)

## Consecuencias

### Positivas
- 1 source of truth (DB).
- Lifecycle explícito y auditable.
- Tasks ejecutables con criterios verificables.
- Versionado real (`plans.version` + `plan_history`).
- DAG explícito (`task_dependencies`).
- Cierra el ciclo abierto por `agentes-db-primera-2026-08-06` y `fix-skills-docs-plans-2026-08-06`.

### Negativas / Riesgos
- Migración de planes `.md` viejos (Task 8).
- Breaking change si clientes externos asumen schema viejo (mitigado: columnas nullable).
- Curva de aprendizaje para Sol/Teo (mitigado: tests + skill reescrita).
- Performance del ALTER TABLE para DBs grandes (>1000 plans).

### Related
- `agentes-db-primera-2026-08-06` (predecesor)
- `fix-skills-docs-plans-2026-08-06` (predecesor paralelo)
- constitution R6, R14
- schema v0.7.6 → v0.7.7',NULL,'approved','pol','user','2026-08-06 13:52:26','2026-08-06 13:52:26','2026-08-06 13:52:26');
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (4,'agentes-db-primera-2026-08-06-legacy-imported','Protocolo DB-primera: agentes consultan team.db antes de leer el proyecto','# Protocolo DB-primera: agentes consultan team.db antes de leer el proyecto

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
- Hay 3 menciones de superpowers:* restantes en systematic-debugging/SKILL.md que requieren evaluación caso por caso',NULL,'draft','pol','legacy-import','2026-08-06T14:25:14Z','2026-08-06T14:25:14Z',NULL);
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (5,'fix-skills-docs-plans-2026-08-06-legacy-imported','Proposal: fix-skills-docs-plans-2026-08-06','<!-- GENERATED from teamdb on 2026-08-06T05:01:40Z. DO NOT EDIT. Source of truth: .opencode/context/team.db.
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


<!-- Footer: regenerar desde DB con scripts/teamdb-export-md.sh -->',NULL,'draft','pol','legacy-import','2026-08-06T14:25:15Z','2026-08-06T14:25:15Z',NULL);
INSERT INTO "proposals" ("id","slug","title","intent_md","questions_json","status","agent","decided_by","created_at","updated_at","decided_at") VALUES (6,'plan-unico-versionado-2026-08-06-legacy-imported','Plan único versionado: 1 proposal → 1 plan → N tasks ejecutables, todo en DB','# Plan único versionado: 1 proposal → 1 plan → N tasks ejecutables, todo en DB

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

<!-- Footer: regenerar desde DB con teamdb-export-md.sh -->',NULL,'draft','pol','legacy-import','2026-08-06T14:25:15Z','2026-08-06T14:25:15Z',NULL);
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('rcpt_1786150845_5220','1000','teo','review-seal',0,'','2026-08-08 01:00:45','ef2d4380aed49030');
INSERT INTO "receipts" ("id","task_id","agent","command","exit_code","output_summary","ts","tree_hash") VALUES ('rcpt_1786151556_51426','1001','teo','review-seal',0,'','2026-08-08 01:12:36','9df021410071a179');
