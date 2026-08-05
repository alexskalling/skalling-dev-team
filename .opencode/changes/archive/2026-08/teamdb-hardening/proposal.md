# Proposal: TeamDB Hardening v0.7.2

**Slug:** `teamdb-hardening`
**Owner:** Pol (spec author)
**Status:** Approved by user (via Alex)
**Date:** 2026-08-05
**Target version:** 0.7.2
**Source of truth declaration:** TeamDB (libSQL) es la **fuente canónica** para estado, versiones, planes y ejecución de trabajo. Markdown (`.opencode/context/**/*.md`) es **representación legible exportada** para Git, no fuente independiente. Toda escritura DEBE pasar por `teamdb_write_project` (o `_global`). Toda lectura DEBE preferir `teamdb_query_*` antes que parsear `.md`.

---

## Context

La rama `teamdb` introduce libSQL como fuente de verdad del proyecto (v0.7.0). Una auditoría del estado actual reveló **23 hallazgos** en 9 áreas: seguridad, instalación, versionado, cobertura de tablas, scripts faltantes, escrituras no-portables, integración parcial en agentes, snippets duplicados, y validación de runtime insuficiente.

Este change cierra esos hallazgos con TDD estricto, sin commits automáticos, en una sola entrega realista pero completa.

---

## Objectives

### OBJ-1 — Eliminar SQL injection en scripts interactivos
Cerrar toda interpolación no-parametrizada en `teamdb-search.sh` y `teamdb-related.sh` usando `sqlite3` con parameters (`?` placeholders) o helper `teamdb_safe_query()` que escapa + valida.

### OBJ-2 — Hacer TeamDB realmente instalable
`install-global.sh` debe instalar todos los scripts teamdb y los hooks deben tener paths absolutos funcionando desde `.git/hooks/`.

### OBJ-3 — Sincronizar versiones en una sola fuente
Una sola declaración de versión. `VERSION` es el único archivo de verdad; schema DB y README derivan de él (o viceversa, con CI que falle en mismatch).

### OBJ-4 — Conectar las tablas del ciclo completo
Las tablas `proposals`, `plans`, `specs`, `design_notes`, `tasks` ya existen en `project-schema.sql` (v0.7.1 interno) pero ningún script las usa. Crear scripts de lectura/escritura para que Pol, Sol, Teo, Jhon, Luz y Pau operen sobre el ciclo completo en DB.

### OBJ-5 — Hacer las escrituras seguras y portables
Toda escritura debe pasar por `teamdb_write_project` (con `flock`) o `teamdb_write_global` (nuevo, simétrico). Sin `|| true` silenciadores. Sin paths relativos en hooks.

### OBJ-6 — Integrar TeamDB en los 8 agentes
Alex (Session Start Protocol) y Jes (PASO 0) deben consultar TeamDB antes que el bundle legacy markdown. Pau y Pol ya lo hacen.

### OBJ-7 — Reducir duplicación de snippets
Eliminar el copy-paste literal de Code Intelligence y Memory Protocol en los 8 agentes. Single source real, sin "disciplina manual".

### OBJ-8 — Hacer audit_log confiable
Triggers deben registrar el agente real (no `system`). Debe sobrevivir export/import (ya está en DB pero `teamdb-export.sh` no lo exporta — fix).

### OBJ-9 — Validar handoffs en runtime
`templates/handoff.schema.json` debe marcar `project_context` y `verification` como `required` cuando `to` es Teo/Luz (cualquier agente de ingeniería). Agregar test que valide el schema rechaza handoffs inválidos.

### OBJ-10 — CI cubre TeamDB
`.github/workflows/tests.yml` debe correr `tests/teamdb.test.sh` en la matriz bash 3/4/5 + suite de handoffs schema + suite de search/related post-fix.

---

## Source of Truth (DECLARACIÓN EXPLÍCITA — NO NEGOCIABLE)

> **TeamDB (libSQL) es la fuente canónica para estado, versiones y ejecución de planes.**
>
> Markdown (`.opencode/context/**/*.md`, `*.jsonl`) es **representación legible exportada para Git** (vía `teamdb-export.sh` y `gitattributes` con `merge=union`). NO es fuente independiente.
>
> **Reglas derivadas:**
> 1. **Toda escritura** a estado, planes, decisiones, problems, WIP, audit, tags, links → `teamdb_write_project` / `teamdb_write_global` con `flock`.
> 2. **Toda lectura** de estado → `teamdb_query_project` / `teamdb_query_global` con SQL parametrizado.
> 3. **Markdown se regenera** desde DB si hay drift (script `teamdb-sync-md.sh` opcional, no en este change).
> 4. **Tests de DB** son la verdad; tests de MD son secundarios (cubren export/import round-trip).
> 5. **El bundle legacy `.jsonl`** se considera obsoleto. `teamdb-migrate.sh` lo absorbe una vez y mueve a `legacy/`. Después de este change, ningún script lee `.jsonl`.

---

## Out of Scope

| # | Item | Por qué fuera |
|---|---|---|
| OOS-1 | Migración automática del contenido del bundle legacy `.md` (concept docs con frontmatter) a filas en `concepts` | Riesgo de pérdida semántica; requiere decisión de Pau por doc. Se deja como propuesta separada. |
| OOS-2 | Reemplazar `.gitattributes` `merge=union` por una estrategia más sofisticada | Funciona correctamente; no es bloqueante. |
| OOS-3 | Reescribir `wip-tree.sh` para usar tablas `plans`/`tasks` en vez de `work_in_progress` | Cambio estructural mayor; queda para v0.7.3+. Por ahora, ambos coexisten (legacy para visualización, nuevas tablas para SDD formal). |
| OOS-4 | Cliente libSQL nativo en TypeScript/Python | Out-of-band; este change es bash + sqlite3. |
| OOS-5 | Reemplazar `bootstrap-context.sh` entero por un flujo DB-first | Cambio cross-cutting que afecta init. Se hace en change aparte. |
| OOS-6 | Documentación masiva de cada tabla y campo | `proposal.md`/`spec.md`/`design.md` ya documentan; manual extendido queda para `docs/`. |
| OOS-7 | Mejoras de UX en `teamdb-graph.sh` (formatos adicionales: cytoscape, d3) | Funciona con text/mermaid/dot; suficiente. |
| OOS-8 | Auditoría de las 268+ tests de `setup.test.sh` para sumarlas a CI matrix | Solo `tests/teamdb.test.sh` se agrega; el resto ya corre. |
| OOS-9 | Internacionalización de mensajes de error | Mensajes en español consistente con el proyecto; i18n queda para fase posterior. |
| OOS-10 | Refactor de `bootstrap-context.sh` para generar concept docs via teamdb en vez de templates markdown | Cross-cutting con init; tratado en change aparte. |

---

## Invariants

1. **INV-SQLI-1**: Ningún script bajo `scripts/` debe interpolar variables de usuario directamente en SQL. Toda entrada externa pasa por helper `teamdb_safe_query` (parameterized) o validación + escape documentado.
2. **INV-INSTALL-1**: Después de `bash install-global.sh`, todos los scripts `scripts/teamdb-*.sh` Y `scripts/lib/lib-teamdb.sh` deben estar en `~/.config/opencode/scripts/`.
3. **INV-INSTALL-2**: Después de `bash install-global.sh`, los hooks `pre-commit` y `post-merge` deben estar en `~/.config/opencode/hooks/` Y ejecutables.
4. **INV-VERSION-1**: Hay exactamente una declaración de versión en el repo: `VERSION`. README, schema DB, y changelog la derivan.
5. **INV-WRITE-1**: Toda función que ejecute `INSERT`/`UPDATE`/`DELETE` en teamdb DEBE usar `teamdb_write_project` o `teamdb_write_global`. Excepción documentada: tests.
6. **INV-WRITE-2**: Si `flock` está disponible, escrituras DEBEN usarlo. Si no, el script debe advertir y continuar con riesgo de race condition explícito (no silenciar).
7. **INV-PORTABILITY-1**: Scripts deben correr en bash 3.2 (default macOS). Sin `[[ -v ]]`, sin `declare -A`, sin `readarray`.
8. **INV-TEST-1**: Toda tarea de código tiene al menos un test que falla antes y pasa después. Sin excepciones.
9. **INV-CYCLE-1**: Toda mutación de `work_in_progress`, `tasks`, `plans`, `proposals` debe ir por `teamdb_write_*` para que `audit_log` registre el agente correcto.
10. **INV-AUDIT-1**: `audit_log.agent` refleja el agente que invocó el cambio, no un literal. Mecanismo: variable `TEAMDB_ACTOR` exportada por el caller o parámetro explícito en `teamdb_write_*`.
11. **INV-SCHEMA-1**: `schema_meta.version` del proyecto debe matchear `schema_meta.version` esperado por el código. Si no matchea → doctor warn + script de auto-fix opcional.

---

## Acceptance Criteria (verificables)

Cada criterio tiene un comando de verificación. Todos deben pasar antes de cerrar el change.

### AC-SEGURIDAD (5 criterios)
- **AC-1.1**: `bash tests/teamdb-search-sqli.test.sh` pasa (input con `'`, `;`, `--`, `DROP TABLE` no rompe DB ni permite ejecución).
- **AC-1.2**: `bash tests/teamdb-related-sqli.test.sh` pasa.
- **AC-1.3**: `bash scripts/teamdb-search.sh "anything" problems /tmp/proj` retorna solo filas de `known_problems` (verifica con `known_problems.id IN (SELECT rowid FROM problems_fts ...)` O fallback a `LIKE` puro si no hay FTS5 para problems).
- **AC-1.4**: `grep -rn "sqlite3.*\\\\\$" scripts/teamdb-search.sh scripts/teamdb-related.sh` retorna **0 matches** (sin interpolación).
- **AC-1.5**: `shellcheck scripts/teamdb-search.sh scripts/teamdb-related.sh` retorna 0 errores.

### AC-INSTALACIÓN (3 criterios)
- **AC-2.1**: Después de `bash install-global.sh --dry-run`, los siguientes paths aparecen: `~/.config/opencode/scripts/teamdb-search.sh`, `teamdb-related.sh`, `teamdb-graph.sh`, `lib/lib-teamdb.sh`, `hooks/pre-commit`, `hooks/post-merge`.
- **AC-2.2**: Los hooks instalados usan `git rev-parse --show-toplevel` para resolver path absoluto, NO `$SCRIPT_DIR/../`.
- **AC-2.3**: `bash install-global.sh` + commit dummy + `git status` muestra `.opencode/context/teamdb/data_*.sql` actualizado por el pre-commit.

### AC-VERSIONADO (2 criterios)
- **AC-3.1**: `grep -E "0\.[0-9]+\.[0-9]+" README.md` retorna solo la línea de "Versión actual: $VERSION" leída dinámicamente (no hardcodeada).
- **AC-3.2**: `tests/version-coherence.test.sh` valida que `VERSION`, `schema_meta.version` (de `teamdb-export.sh`-generado), y `README` mentionan la misma versión. Falla si difieren.

### AC-TABLAS Y SCRIPTS (5 criterios)
- **AC-4.1**: Existe `scripts/teamdb-amend.sh`, `scripts/teamdb-resume.sh`, `scripts/teamdb-execute-plan.sh`, ejecutables, con al menos un test cada uno.
- **AC-4.2**: `scripts/teamdb-plan.sh` crea filas en `proposals`, `plans`, `tasks` (no en `work_in_progress`).
- **AC-4.3**: `scripts/teamdb-status.sh` resume el estado del plan activo (próxima task, owner, blockers).
- **AC-4.4**: Ningún script nuevo usa `work_in_progress` (legacy) salvo `wip-tree.sh` (visualización).
- **AC-4.5**: `tests/teamdb-cycle.test.sh` valida flujo completo: crear proposal → crear plan → crear 3 tasks → resolver 1 → status muestra 2 pendientes.

### AC-ESCRITURAS (3 criterios)
- **AC-5.1**: `grep -L "teamdb_write" scripts/teamdb-*.sh` retorna solo `teamdb-search.sh` y `teamdb-related.sh` (que son read-only por diseño).
- **AC-5.2**: `lib-teamdb.sh` define `teamdb_write_global` simétrico a `teamdb_write_project`, con `flock` y validación de DB path.
- **AC-5.3**: `grep -rn "|| true" scripts/` retorna solo líneas donde `|| true` es comportamiento explícito documentado (no silencio genérico).

### AC-INTEGRACIÓN AGENTES (3 criterios)
- **AC-6.1**: `agents-base/Alex.md` sección "Session Start Protocol" usa `teamdb_query_project` para cargar memorias relevantes.
- **AC-6.2**: `agents-base/Jes.md` PASO 0 usa `teamdb_query_project` para contextualizar.
- **AC-6.3**: `tests/agents-teamdb-integration.test.sh` valida que cada uno de los 8 agentes menciona `teamdb_query_*` o documenta explícitamente por qué no (Teo/Jhon/Luz/Pau/Pol/Sol ya lo hacen; Alex/Jes deben agregarlo).

### AC-SNIPPETS (2 criterios)
- **AC-7.1**: Los 8 agentes NO contienen el cuerpo del Code Intelligence snippet. En su lugar, tienen una línea `<!-- @include templates/agents/snippets/code-intelligence.md -->` o similar referencia resoluble en build time.
- **AC-7.2**: `tests/snippets-sync.test.sh` falla si las 8 copias del snippet Code Intelligence o Memory Protocol difieren del canónico byte-a-byte.

### AC-AUDIT (2 criterios)
- **AC-8.1**: Triggers de `audit_log` registran `agent` desde variable de sesión (`@actor`) o parámetro `TEAMDB_ACTOR` del cliente, no literal `'system'`.
- **AC-8.2**: `teamdb-export.sh` exporta `audit_log` Y `schema_meta` además de las 6 tablas actuales. `teamdb-import.sh` los importa idempotentemente.

### AC-RUNTIME (3 criterios)
- **AC-9.1**: `templates/handoff.schema.json` define `allOf` con condición: si `to` ∈ {TEO, LUZ}, `project_context` es required. Si `to` ∈ {JHON, LUZ}, `verification` es required.
- **AC-9.2**: `tests/handoff-schema-validation.test.sh` valida que un handoff TEO→JHON sin `project_context` falla la validación.
- **AC-9.3**: `tests/handoff-schema-validation.test.sh` valida que un handoff JHON→LUZ sin `verification` falla.

### AC-CI (3 criterios)
- **AC-10.1**: `.github/workflows/tests.yml` job `test` corre `bash tests/teamdb.test.sh` además de `tests/setup.test.sh`.
- **AC-10.2**: Workflow nuevo `validate-handoffs` corre `tests/handoff-schema-validation.test.sh` en cada PR.
- **AC-10.3**: Workflow nuevo `teamdb-search-sqli` corre `tests/teamdb-search-sqli.test.sh` y `tests/teamdb-related-sqli.test.sh` en cada PR.

### AC-MIGRACIÓN (2 criterios)
- **AC-11.1**: `teamdb-migrate.sh` extrae frontmatter YAML de `concept/*.md` y popula `concepts.body_md` + metadata en `memory_tags` o columna adicional.
- **AC-11.2**: Si no hay `.jsonl`, `teamdb-migrate.sh` termina con exit 0 y warning explícito (no falla silenciosamente).

### AC-PORTABILIDAD (1 criterio)
- **AC-12.1**: `tests/portability-bash32.test.sh` corre `scripts/teamdb-*.sh` con `bash 3.2` (mockeando `BASH_VERSINFO[0]=3`) y verifica exit 0.

**Total: 32 criterios de aceptación, todos con comando de verificación.**

---

## Risks

| # | Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|---|
| R-1 | Fix de SQLi cambia comportamiento de search/related y rompe consumers | Media | Alto | Tests AC-1.1/1.2/1.3 cubren comportamiento equivalente. Cambiar query con `LIKE '%X%'` como fallback si FTS5 falla. |
| R-2 | Refactor de hooks rompe flujos de commit/merge existentes | Baja | Alto | Hooks nuevos son backward-compatible: export/import es no-op si DB no existe. Tests E2E de git workflow. |
| R-3 | Tests de search-sqli son flaky por timing en fixtures grandes | Baja | Medio | Usar `mktemp -d` para DBs frescas por test, sin estado compartido. |
| R-4 | Snippet deduplication rompe el modelo de archivos .md independientes (los agentes son archivos completos hoy) | Media | Medio | Mantener el snippet inline como fallback si no hay mecanismo de include en runtime de opencode. Documentar el include como "best effort". |
| R-5 | Migrar `concept/*.md` con frontmatter a DB pierde semántica | Alta | Alto | AC-11.1 cubre preservación de body_md; tags y confidence se preservan en `memory_tags`/`concepts.category`. NO borrar los `.md` hasta validar round-trip. |
| R-6 | Tests bash 3.2 fallan por incompatibilidad real (declare -A, etc.) | Media | Bajo | Code review pre-merge busca estos patrones. Si se detectan, refactor inmediato. |
| R-7 | El doctor (`setup-team-doctor.sh`) genera falsos positivos por la nueva lógica de check_teamdb | Baja | Medio | Tests del doctor (no incluidos en este change, OOS-8). |
| R-8 | Conflictos con la rama principal si hay cambios paralelos | Media | Medio | Este change está aislado en `teamdb` branch; merge a main se hace después de QA. |
| R-9 | El cambio de audit_log agent rompe consumers que asumen 'system' | Baja | Alto | Grep en repo: si no hay consumers (tests los únicos), el riesgo es 0. Documentar en CHANGELOG. |
| R-10 | Tests E2E lentos por crear DB múltiples veces | Baja | Bajo | Tests paralelos via `&` no son confiables; usar timeout 5s y fallback a skip con warning si es lento. |

---

## Implementation Strategy (3 fases)

### FASE 1 — Seguridad + Instalación (crítico, bloqueante)
**Tareas:** AC-1.1 a AC-1.5, AC-2.1 a AC-2.3.
**Criterio de fase:** `bash tests/teamdb-search-sqli.test.sh && bash tests/teamdb-related-sqli.test.sh && bash install-global.sh --dry-run && bash tests/install.test.sh` todo verde.
**Por qué primero:** SQLi es CVE potencial. Instalación rota significa que `teamdb-search.sh` no llega a la máquina del usuario (lo que magnifica el riesgo de R-1).

### FASE 2 — Versión + Ciclo + Escrituras (estructura)
**Tareas:** AC-3.1 a AC-3.2, AC-4.1 a AC-4.5, AC-5.1 a AC-5.3, AC-11.1 a AC-11.2.
**Criterio de fase:** `bash tests/teamdb-cycle.test.sh && bash tests/version-coherence.test.sh && bash tests/portability-bash32.test.sh` todo verde.
**Por qué segundo:** Sin scripts de ciclo, no se pueden escribir/consultar planes. Sin versiones coherentes, no se puede confiar en `schema_meta.version`.

### FASE 3 — Agentes + Snippets + Audit + Runtime + CI (consolidación)
**Tareas:** AC-6.1 a AC-6.3, AC-7.1 a AC-7.2, AC-8.1 a AC-8.2, AC-9.1 a AC-9.3, AC-10.1 a AC-10.3, AC-12.1.
**Criterio de fase:** Workflow CI completo verde. `bash tests/teamdb-hardening-suite.sh` (aggregator) verde.
**Por qué último:** Estas tareas dependen de las fases 1 y 2 (los agentes referencian scripts que ya existen).

---

## ⚠️ Conflictos detectados

**Bundle corrupto, saltando check.**

El bundle `.opencode/context/` no existe en esta rama. No hay concept docs para leer ni `trabajo-en-curso/` activos que puedan solaparse. La Fase 5 del protocolo Pol (chequeo de contradicciones) se omite por bundle ausente. El flujo continúa sin bloquear.

Si durante la ejecución de Teo se detecta una contradicción con un concept doc existente (no debería, dado que el bundle está vacío), Teo lo marca en el handoff con `contradicciones_detectadas` y Pau lo resuelve al cierre.

---

## Stakeholders

- **Pol** (spec author): escribió este proposal. Cierra su rol al pasarlo a Sol.
- **Sol** (planner): convierte esto en `tasks.md` ejecutable. Decide orden fino dentro de cada fase.
- **Teo** (engineer): ejecuta cada tarea con TDD. Red→Green→Refactor.
- **Jhon** (verifier): valida tests de cada tarea + regresión completa al final de cada fase.
- **Luz** (auditor): corre quality gate al final de cada fase (security check + clean code + R13 si UI).
- **Pau** (documentalist): actualiza CHANGELOG.md, README, y consolida memoria operativa al cierre.

---

## Decisiones confirmadas por el usuario (NO-NEGOCIABLES — agregado por Sol)

Estas decisiones llegaron del usuario vía Alex y **prevalecen sobre cualquier ambigüedad del proposal**:

1. **DC-1 — TeamDB es la fuente canónica de estado/versiones/ejecución de planes.** Markdown (`.opencode/context/**/*.md`, export `.sql`) es **representación legible exportada** que NO se borra. Se regenera desde DB (drift), pero la persistencia real vive en la DB.
   - Implicación directa: `teamdb-migrate.sh` línea 96-100 NO debe mover `.md` a `legacy/`. Solo mover `.jsonl` a `legacy/` (lo que ya estaba obsoleto). TASK-2.8 corrige esto.
2. **DC-2 — Snippets compartidos (`code-intelligence.md`, `memory-protocol.md`) se expanden build-time durante la instalación**, no en runtime. La resolución la hace `install-global.sh::install_agents()` al copiar los agentes a `~/.config/opencode/agents/`. La fuente única canónica vive en `templates/agents/snippets/*.md`. TASK-3.3 (markers en agentes) + TASK-3.4 (resolver en install) lo implementan.
3. **DC-3 — `teamdb-execute-plan.sh` solo descubre/orquesta la siguiente tarea y registra estados.** NO ejecuta shell arbitrario desde la DB. Teo (con TDD real) hace el trabajo de ingeniería. La DB puede contener `tasks.description_md` (qué hacer) y `tasks.status`, pero **NO** un campo `shell_command` o equivalente. TASK-2.6 implementa esto explícitamente.

---

## Inconsistencias detectadas por Sol (para que Pol las cierre en su próxima pasada)

- **INC-1**: AD-4 original proponía regenerar `sql/*.sql` enteros → sobre-alcance. Corregido en `design.md` AD-4 (versión corregida: solo se estampa la fila `schema_meta.version`). Spec VER-1 debe aclarar que `build-schema.sh` solo estampa esa fila, no el schema entero.
- **INC-2**: SPEC.MIG-1.1 dice "no remove .md" pero el script `teamdb-migrate.sh` actual **sí las mueve**. La implementación contradice la spec. TASK-2.8 corrige el script. Spec MIG-1.1 queda válido, solo hay que asegurar que el script lo cumpla.
- **INC-3**: SPEC.HAN-1.1 propone `if/then` con `to ∈ {TEO, LUZ}`, pero el caso real requiere también `from ∈ {TEO, JHON, LUZ}` para `verification` cuando el emisor es ingeniería y debe llevar evidencia (ver `skalling-receipt`). Aclarar al implementar HAN-1.1 (TASK-3.6).
- **INC-4**: AC-10.1 asume `.github/workflows/tests.yml` existente; **no existe** en esta rama. Las 3 workflows (CI-1.1, CI-1.2, CI-1.3) se crean desde cero. Aclarado en TASK-3.8.

---

## Out-of-Band (decisiones que NO son de Pol)

---

*Generado por Pol el 2026-08-05 en la rama `teamdb`.*
*Source of truth: este archivo en `.opencode/changes/teamdb-hardening/proposal.md`.*
