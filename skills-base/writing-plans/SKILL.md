---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
license: MIT
metadata:
  author: skalling-team
  version: "2.0"
---

# Writing Plans (v0.7.7 — Plan único versionado)

## Overview

Write comprehensive implementation plans. Assume the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

## Source of truth: la DB, NO archivos `.md`

A partir de **v0.7.7** los planes viven en `team.db` (tabla `proposals` + `plans` + `tasks` + `task_dependencies` + `plan_history` + audit triggers). Los archivos `.md` en `.opencode/changes/<slug>/` son **EXPORTS legibles para git** y SIEMPRE llevan el header `<!-- GENERATED from teamdb · DO NOT EDIT, regenerate via teamdb-export-md.sh -->`. Editar el `.md` a mano es una violación de contrato.

**Reglas duras:**

1. **Para CREAR un plan nuevo** → `teamdb-plan.sh <project> <slug> <title> <tasks.md> --purpose=... --acceptance=... --strict-contract`. NO escribir `proposal.md` ni `design.md` aparte. El script hace INSERT atómico en `proposals` + `plans` + `tasks` + `task_dependencies` + `plan_history` con un solo `BEGIN IMMEDIATE`.

2. **Para MEJORAR un plan existente** → `teamdb-amend.sh <project> --slug=<slug> [--design-stdin] [--add-task=<task.json>]`. NO crear `design.md` aparte. El script hace UPDATE del plan, incrementa `version`, append a `plan_history` con `operation='amended'`, y exige `--purpose` para cada task agregada.

3. **Para EXPORTAR a `.md` legible** → `teamdb-export-md.sh <project> --slug=<slug>`. Genera `.opencode/changes/<slug>/{proposal.md,design.md,tasks.md}`. Si el contenido no coincide con la DB, la DB gana.

4. **Para EJECUTAR** → `teamdb-execute-plan.sh <project> --slug=<slug>`. Lee `tasks WHERE plan_id=?` ordenado por `order_index`, no interpreta `.md`.

## Contrato de tasks (v0.7.7 — NO NEGOCIABLE)

Cada task debe tener:

- **`purpose`** (1-2 frases): por qué existe la task, qué problema resuelve. NO es un resumen del `title`, es el "para qué".
- **`acceptance_md`** (criterios verificables): lista de checks que Luz puede validar. Típicamente 3-6 bullets en formato `- [ ] <verificable>`.
- **`order_index`** (entero ≥0): orden de ejecución. El DAG via `task_dependencies` (FK a otras tasks del mismo plan) controla el paralelismo real.
- **`title`** descriptivo: verbo + objeto, NO poético. Ejemplos válidos: "Migrar plans.design_md a nullable", "Agregar trigger plans_audit_ai". Ejemplos rechazados: "Gimme Shelter", "Sympathy for the Devil", "Sunshine of Your Love" (4+ palabras en lowercase = poético).

**Si una task no tiene `purpose` o `acceptance_md`, `teamdb-plan.sh --strict-contract` rechaza con error claro y exit 1. NO se crea el plan.**

## Títulos NO poéticos (heurística de rechazo)

`teamdb-plan.sh --strict-contract` aplica la siguiente heurística al título del plan Y al título de cada task:

```
4+ palabras TODO lowercase separadas por espacios
→ rechazado como "poético" (canciones tipo "gimme shelter now please")
```

Ejemplos:

| Título | Resultado |
|---|---|
| `Setup CI pipeline` | OK (2 palabras) |
| `migrate plans to nullable` | OK (4 palabras con mix) |
| `gimme shelter now please` | RECHAZADO (4+ lowercase) |
| `agregar trigger de audit` | OK (mayúscula al inicio) |
| `the house of the rising sun` | RECHAZADO |

## Lifecycle de un plan

```
draft → approved → in_progress → completed
   │                  │
   └────→ abandoned ←─┘  (en cualquier momento, via teamdb-amend.sh)
```

- `draft`: Pol escribió el proposal, todavía no se firmó.
- `approved`: Sol mejoró el plan, user lo aprobó. `teamdb-execute-plan.sh` solo corre en este estado o `in_progress`.
- `in_progress`: Teo empezó a ejecutar tasks. `audit_log` registra el timestamp.
- `completed`: Todas las tasks están `approved` o `resolved`. Pau marca esto al cerrar.
- `abandoned`: Se descartó. Queda en `audit_log` para reproducibilidad.

Las transiciones se registran en `audit_log` via los triggers `plans_audit_ai` (insert) y `plans_audit_au` (update). El campo `plans.version` se incrementa en cada UPDATE (manejado por `teamdb-amend.sh`).

## 1 plan por feature-slug activo

Constraint de unicidad: solo puede haber UN plan activo por `slug` (status en `draft|approved|in_progress`). Si Sol quiere un nuevo intento sobre el mismo slug, debe primero pasar el viejo a `abandoned`. `teamdb-amend.sh --add-task` valida esto antes de hacer INSERT.

## Bite-Sized Task Granularity

**Cada step es una acción (2-5 minutos):**

- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Workflow recomendado

1. **Leer contexto**: `teamdb-search.sh "<query>"` y `teamdb-related.sh <concept-slug>` antes de planear. Si no hay proposal válido, escalar a Alex.
2. **Definir el plan completo** en un `tasks.md` temporal con el formato:
   ```markdown
   - [ ] Título de la task _depends: [task-1, task-2]
   - [ ] Otra task
   ```
3. **Ejecutar `teamdb-plan.sh`** con `--strict-contract`:
   ```bash
   teamdb-plan.sh "$PROJECT" "<slug>" "<title>" /tmp/tasks.md \
     --purpose="Feature global purpose" \
     --acceptance="AC global (override per-task si hace falta)" \
     --strict-contract \
     --by=pol
   ```
4. **Verificar** con `teamdb-execute-plan.sh --slug=<slug> --dry-run`.
5. **Exportar** a `.md` legible: `teamdb-export-md.sh --slug=<slug>`.
6. **Commitear** el export (no la DB) a git.

## Estructura del `tasks.md` (input de `teamdb-plan.sh`)

```markdown
# Tasks para <feature-name>

- [ ] Crear archivo X
- [ ] Crear test para X _depends: [task-crear-archivo-x]
- [ ] Implementar X para pasar el test _depends: [task-crear-test-x]
- [ ] Commit
```

Cada `- [ ] <title>` se convierte en una task con `purpose` y `acceptance_md` default (los pasados por `--purpose` y `--acceptance`). Si querés AC por-task, usá `teamdb-amend.sh --add-task=<json>` después del INSERT inicial.

## Task Structure en el design.md (export legible)

```markdown
### Task N: [Component Name]

**Purpose:** [1-2 frases — por qué existe]

**Acceptance criteria:**
- [ ] criterio verificable 1
- [ ] criterio verificable 2

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

**Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

**Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: agregar comportamiento específico"
```
```

## Remember

- **Source of truth = DB**. El `.md` es export.
- **1 plan activo por `feature-slug`**. No dupliques.
- **Tasks con `purpose` + `acceptance_md`**. El script rechaza sin esos campos.
- **Títulos descriptivos (verbo + objeto)**. Heurística rechaza 4+ palabras lowercase.
- **Exact file paths always**.
- **Complete code in plan (not "add validation")**.
- **Exact commands with expected output**.
- **Reference relevant skills with @ syntax**.
- **DRY, YAGNI, TDD, frequent commits**.
- **Cero comentarios en código (R8)**.
- **Mensajes de commit en español (R16)**.

## Execution Handoff

Después de INSERT en DB y export del `.md`, ofrecer opciones de ejecución Skalling:

**"Plan insertado en team.db (slug: `<feature-slug>`) y exportado a `.opencode/changes/<feature-slug>/{design.md,tasks.md}`. Dos opciones de ejecución:**

**1. Misma sesión (Alex → Teo)** — Handoff vía `skalling-handoff` (mismo flujo Alex↔Teo↔Jhon↔Luz↔Pau). Iteración rápida entre tareas, mismo contexto.

**2. Sub-session dedicada (`skalling-cycle`)** — Spawn de nueva sesión con `skalling-cycle` para ejecución batch con checkpoints por fase.

**¿Qué flujo preferís?"**

**Si opción 1 (misma sesión):**
- Alex emite handoff JSON a Teo (validado con `handoff.schema.json`).
- Teo implementa con TDD, emite receipt a Jhon tras cada tarea.
- Jhon revisa, escala a Alex si rechaza 3 veces (R16/constitución).

**Si opción 2 (sub-session):**
- Alex invoca la skill `skalling-cycle` en nueva sesión.
- El sub-ciclo sigue el flujo nativo (Teo → Jhon → Luz → Pau).
- Pau archiva al cerrar: `.opencode/changes/archive/<YYYY-MM>/<slug>/` (R6).

## Anti-patterns (rechazados con feedback claro)

| Anti-pattern | Por qué se rechaza | Qué hacer en su lugar |
|---|---|---|
| Escribir `proposal.md` directo al filesystem | Es espejo de la DB, no contrato | `teamdb-plan.sh --strict-contract` |
| Crear `design.md` aparte cuando se necesita más detalle | Genera 2 planes divergentes | `teamdb-amend.sh --slug=<slug> --design-stdin` |
| Título de task: "Gimme Shelter" | Sin verbos ni objeto, no es ejecutable | "Implementar validación de slug único" |
| Task sin `purpose` | Luz no puede validar "qué significa hecho" | Agregar 1-2 frases de propósito |
| Task sin `acceptance_md` | No hay criterios verificables | Lista de 3-6 checks binarios |
| Inventar plan propio al ejecutar | Teo no respeta la source of truth | `teamdb-execute-plan.sh --slug=<slug>` |
| 2 planes activos del mismo slug | Rompe el invariante 1-plan-por-slug | Pasar viejo a `abandoned` antes de crear nuevo |

## v0.7.7 — Plan único versionado

A partir de v0.7.7 los planes siguen este contrato:

- **1 plan por `feature-slug` activo** (en `draft`, `approved` o `in_progress`).
- **Lifecycle**: `draft → approved → in_progress → completed` (más `abandoned`).
- **Las tasks requieren `purpose` y `acceptance_md` no vacíos** (enforced por `--strict-contract`).
- **Títulos NO poéticos** (4+ palabras lowercase = rechazado).
- **Para crear**: `teamdb-plan.sh --strict-contract --purpose="..." --acceptance="..."`.
- **Para mejorar**: `teamdb-amend.sh --slug=<slug>`, NO crees otro `design.md`.
- **Audit log** registra cada INSERT/UPDATE de `plans` via triggers.
- **Versioning**: `plans.version` se incrementa en cada `teamdb-amend.sh`.

Si el usuario te da un plan que parece poético o sin propósito, **REPORTALO, no lo inventes**.
