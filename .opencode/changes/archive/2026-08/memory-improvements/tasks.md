# PLAN: Memory Improvements — 5 mejoras al sistema de memoria de Skalling

> **Status**: Pending Approval (depende de confirmación del usuario sobre decisiones en design.md §9)
> **Author**: Sol
> **Archivo**: `.opencode/changes/memory-improvements/tasks.md`
> **Design**: `.opencode/changes/memory-improvements/design.md`
> **Proposal**: `.opencode/changes/memory-improvements/proposal.md`
> **Fecha**: 2026-08-03

---

## 1. Objetivo

Mejorar la memoria persistente de Skalling (bundle OKF) en 5 dimensiones: template más escribible (Mejora 1), memory protocol consistente entre agentes (Mejora 2), detección de contradicciones en proposals (Mejora 3), `/skalling-forget` con consolidación real (Mejora 4), y doctor que vigila la salud del bundle (Mejora 5). Resultado: memoria más escribible, trazable, segura y saneable.

## 2. Solución Técnica

Aproximación de "todo de una, dividido en 7 fases + commits discretos":

1. Cambiar el body del template concept (sin tocar frontmatter, backward compat).
2. Crear un snippet canónico de memory protocol e inyectarlo en los 8 agentes.
3. Agregar la fase de "chequeo de conflictos" en Pol antes de cerrar el proposal.
4. Extraer un helper bash compartido (`scripts/lib/lib-memory-check.sh`) con la lógica de detección que consumen Mejora 4 y 5.
5. Crear `scripts/mem-review.sh` y reescribir `command/skalling-forget.md` para invocarlo primero.
6. Agregar `check_memory_health()` al doctor con 5 chequeos (huérfanos, WIP zombie, index desactualizado, duplicados, log.md).
7. Cerrar: CHANGELOG, README, archive.

Justificación de fases: ver `design.md` §4. Cada fase tiene un test bash (R4) verificable por Jhon de forma aislada.

## 3. Criterio de Éxito

Cross-ref a `proposal.md` "Success Criteria":
- 100% de concept docs nuevos siguen el template What/Why/Where/Learned.
- 2+ entradas en `trabajo-en-curso/` durante un ciclo SDD completo.
- 80% de proposals conflictivos tienen la sección `## ⚠️ Conflictos detectados`.
- `/skalling-forget` agrupa en 4 categorías con candidatos.
- `setup-team-doctor.sh --strict` detecta los 3 issues del fixture de bundle problemático.

## 4. Fuera del Alcance

Cross-ref a `proposal.md` "Out of Scope":
- No se introduce engram binario ni sidecar externo.
- No se implementa FTS5 / búsqueda full-text.
- No se migran concept docs existentes.
- No se cambia la constitución.
- No se hace captura pasiva (hooks post-commit).
- No se modifica `docs/`.

---

## 5. Convenciones Globales

### Tests

Cada test es un bash script ejecutable con `set -euo pipefail`, helpers `pass/fail/log`, asserts `assert_file_exists` / `assert_file_contains` / `assert_dir_exists`, y fixtures con `mktemp -d`. Patrón: `tests/setup.test.sh`.

### Handoff

Cada tarea es un handoff Teo → Jhon. Jhon verifica la **definición de "terminada"** específica de la tarea. Si Jhon rechaza, Teo itera (máx 3 veces). Luz audita el plan completo al final.

### Commits

R16: mensajes descriptivos en español. Esperar confirmación del usuario vía Alex antes de `git add` / `git commit`. Ejemplo: `feat(memory): reescribe template concept con secciones What/Why/Where/Learned`.

### Estimación de tamaño

Las tareas fueron dimensionadas para ~30 min de Teo en foco. Si una tarea tarda más, dividirla. Si es trivial, fusionarla con la siguiente.

---

## 6. Checklist de Tareas

### Fase 1 — Template Concept (What/Why/Where/Learned)

| # | Tarea | Quién | Validación (Jhon) |
|---|---|---|---|
| 1.1 | Reescribir el body de `templates/okf/concept.template.md`: mantener frontmatter intacto, reemplazar las 5 secciones legacy (Qué es / Cómo se usa / Donde vive / Versiones / Links) por las 4 nuevas (What / Why / Where / Learned) en el orden exacto. Usar el formato letra-por-letra de `design.md` §3.1. | Teo | `grep -E "^## (What\|Why\|Where\|Learned)$" templates/okf/concept.template.md` retorna 4 líneas en el orden correcto. Frontmatter intacto (verificar `^type: Concept` sigue presente). |
| 1.2 | Actualizar `agents-base/Pau.md`: agregar instrucción explícita de que Pau **rechaza** concept docs nuevos sin las 4 secciones antes de archivar. Pegar el texto estándar del spec 01 escenario 4 ("⚠️ Concept doc incompleto: falta sección 'Learned' en [path]..."). | Teo | `grep -q "rechaza\|incompleto" agents-base/Pau.md` retorna true. `grep -q "What.*Why.*Where.*Learned" agents-base/Pau.md` (regex permisivo) encuentra referencia a las 4 secciones. |
| 1.3 | Crear `tests/concept-template.test.sh` con el patrón R4: valida que las 4 secciones están en el template en el orden correcto, en el body (no en comentarios). Fixture no necesaria (es estática). | Teo | `bash tests/concept-template.test.sh` exit 0. Reporta PASS >= 4 (uno por sección). |

### Fase 2 — Memory Protocol Snippet

| # | Tarea | Quién | Validación (Jhon) |
|---|---|---|---|
| 2.1 | Crear `templates/agents/snippets/memory-protocol.md` con el contenido del snippet canónico letra-por-letra de `design.md` §3.2. Crear el directorio `templates/agents/snippets/` si no existe. | Teo | `test -f templates/agents/snippets/memory-protocol.md`. Las 4 secciones clave presentes: `## Cuándo evaluar guardar`, `## Dónde guardar`, `## Cómo marcar contradicciones`, `## Qué NO guardar (R10)`. |
| 2.2 | Inyectar la sección `## 🧠 Memory Protocol` en `agents-base/Pau.md` con la **versión extendida** (snippet + bloque de "consolidación"). Pegar bloque completo con comment block SINCRONIZADO al inicio. Mantener la sección existente de "Memoria" si ya hay una (no duplicar). | Teo | `grep -q "^## 🧠 Memory Protocol" agents-base/Pau.md`. `grep -q "consolidación\|consolidar trabajo" agents-base/Pau.md`. El comment block de "SINCRONIZADO CON" está presente. |
| 2.3 | Inyectar la sección `## 🧠 Memory Protocol` en los 7 agentes restantes: Alex, Pol, Jes, Sol, Teo, Jhon, Luz. Contenido: snippet literal de 2.1 (sin la parte de consolidación), con comment block SINCRONIZADO al inicio. Ubicar la sección antes de "🗣️ MI PERSONALIDAD" o "📋 INSTRUCCIONES PARA EL USUARIO". | Teo | Los 7 archivos tienen la sección. `grep -q "^## 🧠 Memory Protocol" agents-base/{Alex,Pol,Jes,Sol,Teo,Jhon,Luz}.md` retorna 7 matches. Cada uno tiene el comment block de "SINCRONIZADO CON". |
| 2.4 | Crear `tests/memory-protocol.test.sh` (R4): valida que los 8 agentes tienen la sección, que el snippet canónico existe, y que los 3 puntos clave están presentes en al menos 1 agente (sanity check de que no quedó vacío). | Teo | `bash tests/memory-protocol.test.sh` exit 0. PASS >= 12 (1 snippet existe + 8 secciones + 3 puntos clave). |

### Fase 3 — Detección de conflictos en Pol (Mejora 3)

| # | Tarea | Quién | Validación (Jhon) |
|---|---|---|---|
| 3.1 | Agregar la **FASE 5 — Chequeo de conflictos contra memoria existente** en `agents-base/Pol.md`, ubicada entre la FASE 4 (Pase a Sol) y el cierre del archivo. Pegar el texto letra-por-letra de `design.md` §3.3. | Teo | `grep -q "FASE 5\|Chequeo de conflictos" agents-base/Pol.md`. La sección cubre los 3 escenarios (sin conflictos / con conflictos / bundle corrupto). La regla "un proposal sin sección es inválido" está presente. |
| 3.2 | Crear `tests/conflict-detection.test.sh` (R4): valida que Pol.md contiene la fase con los 3 escenarios, las áreas consultadas (decisiones/preferencias/problemas-conocidos), y los formatos de las dos secciones (`## ⚠️ Conflictos` y `## ✅ Sin conflictos`). | Teo | `bash tests/conflict-detection.test.sh` exit 0. PASS >= 6 (fase presente, 3 escenarios, 2 formatos). |

### Fase 4 — Helper lib-memory-check.sh (compartido entre Mejoras 4 y 5)

| # | Tarea | Quién | Validación (Jhon) |
|---|---|---|---|
| 4.1 | Crear `scripts/lib/lib-memory-check.sh` con las 6 funciones exportadas según API de `design.md` §2.1. Cada función: `set -euo pipefail`, docstring al inicio, sourceable (`# shellcheck disable=...`). El parser YAML usa regex; `yq` como accelerator opcional. Helpers privados prefijados con `_`. Sourceable desde el dir actual (path relativo). | Teo | `bash -n scripts/lib/lib-memory-check.sh` syntax OK. `grep -c "^skalling_" scripts/lib/lib-memory-check.sh` retorna 6 (las funciones exportadas). `bash -c "source scripts/lib/lib-memory-check.sh; type skalling_find_orphans"` retorna definición. |
| 4.2 | Crear `tests/lib-memory-check.test.sh` (R4): construye 4 fixtures sintéticas (1 huérfano, 1 WIP zombie, 2 duplicados, 1 stale, 1 superseded) en `mktemp -d` y verifica que cada función del helper detecta el caso esperado. | Teo | `bash tests/lib-memory-check.test.sh` exit 0. PASS >= 5 (uno por función). Cada fixture se limpia con `rm -rf` al final. |

### Fase 5 — `/skalling-forget` con consolidación (`mem-review`) (Mejora 4)

| # | Tarea | Quién | Validación (Jhon) |
|---|---|---|---|
| 5.1 | Crear `scripts/mem-review.sh`. Sourcea `scripts/lib/lib-memory-check.sh`. Implementa la detección de las 4 categorías (Duplicados / WIP Zombie / Vigencia / Superseded) en el orden fijo. Output en stdout con formato legible (categoría como header, candidatos con path + timestamp + razón). Acepta `--target <dir>` y `--dry-run`. Lee env vars `SKALLING_WIP_ZOMBIE_DAYS` y `SKALLING_STALE_MONTHS` con defaults 30 y 6. | Teo | `bash -n scripts/mem-review.sh` syntax OK. Correr sobre un fixture con 4 categorías llenas → output tiene 4 secciones en el orden correcto. `bash scripts/mem-review.sh --help` exit 0. |
| 5.2 | Reescribir `command/skalling-forget.md`. PASO 1: invocar `scripts/mem-review.sh`. PASO 2: agrupar output en 4 categorías. PASO 3: por cada candidato, presentar opciones A/B/C/D individualmente. PASO 5: loggear en `.opencode/context/log.md` con el formato del spec 04 escenario 7. PASO 6: correr `bash setup-team-doctor.sh --strict` y advertir si hay issues nuevos. Conservar las advertencias existentes (no tocar constitución, index.md, README.md, log.md, .opencode/changes/, docs/, .opencode/state/). | Teo | `grep -q "mem-review.sh" command/skalling-forget.md`. Las 4 categorías están listadas en el orden correcto. Las opciones A/B/C/D están por candidato (no en bloque). El formato de log.md de spec 04 esc. 7 está pegado. |
| 5.3 | Crear `tests/mem-review.test.sh` (R4): fixture con 2 docs duplicados, 1 WIP zombie (timestamp > 30 días, todas las tareas `[x]`), 1 concept doc sin referenciar > 6 meses, 1 superseded. Crea `.opencode/context/index.md` para validar parados. Asserts: mem-review detecta los 4, los agrupa en el orden correcto, los duplicados son errore (no warning). | Teo | `bash tests/mem-review.test.sh` exit 0. PASS >= 8 (4 detecciones + 1 orden + 3 detalles de formato). |
| 5.4 | Crear `tests/skalling-forget.test.sh` (R4): test de integración end-to-end. Fixture: bundle con los 4 tipos de candidato. Stub el agente decisiones (no interactivo) con respuestas pre-cargadas (A: archivar, B: borrar, C: conservar). Invoca el comando completo. Asserts: archivos se mueven correctamente, `log.md` se actualiza con el formato esperado, doctor post-purga corre. | Teo | `bash tests/skalling-forget.test.sh` exit 0. PASS >= 5 (1 flujo completo + 4 verificaciones: archivo movido, log actualizado, doctor corriço, warnings respetados). |

### Fase 6 — Sección Memoria en `setup-team-doctor.sh` (Mejora 5)

| # | Tarea | Quién | Validación (Jhon) |
|---|---|---|---|
| 6.1 | Agregar la función `check_memory_health()` en `setup-team-doctor.sh`, copiada letra-por-letra de `design.md` §3.5. Sourcea `scripts/lib/lib-memory-check.sh` al inicio de la función. Header de sección: `section "Memoria (bundle OKF)"`. Mantiene el formato de `ok/warn/err/info` con los colores existentes. | Teo | `bash -n setup-team-doctor.sh` syntax OK. `grep -q "check_memory_health()" setup-team-doctor.sh` (la función está definida). `grep -q "Memoria (bundle OKF)" setup-team-doctor.sh` (el header). |
| 6.2 | Modificar `check_project_install()` en `setup-team-doctor.sh` para invocar `check_memory_health` después del chequeo de `project.yaml` y antes del chequeo de "Changes (SDD)". Mantiene el flujo de skip si no hay `.opencode/`. | Teo | `grep -q "check_memory_health" setup-team-doctor.sh` retorna 2 matches (definición + invocación). El orden de invocación es correcto. |
| 6.3 | Actualizar `command/skalling-doctor.md`: agregar la fila "Memoria (bundle OKF)" a la tabla de output (después de "REGLA #13"). Documentar los 4 tipos de findings (huérfanos, WIP zombie, index desactualizado, duplicados). Mantener el formato de la tabla. | Teo | `grep -q "Memoria (bundle OKF)" command/skalling-doctor.md`. Las 4 descripciones de findings están mencionadas. |
| 6.4 | Crear `tests/doctor-memory.test.sh` (R4): mktemp -d con bundle problemático (1 huérfano + 1 WIP zombie + 1 index desactualizado + 2 duplicados). Crea los archivos con frontmatter válido. Correr `bash setup-team-doctor.sh --strict --project <fixture>`. Asserts: detecta los 4 issues, severidades respetadas (duplicado = error, exit 1 con --strict). | Teo | `bash tests/doctor-memory.test.sh` exit 0. PASS >= 8 (5 chequeos + 3 severidades). El fixture se limpia con `rm -rf`. |

### Fase 7 — Cierre (CHANGELOG, README, archive)

| # | Tarea | Quién | Validación (Jhon) |
|---|---|---|---|
| 7.1 | Agregar entrada en `CHANGELOG.md` bajo `[Unreleased]` con el formato Keep a Changelog. 5 sub-secciones `### Added` (una por mejora). Lenguaje descriptivo, no bullets técnicos secos. | Teo | `grep -q "Memory Improvements\|memory-improvements" CHANGELOG.md`. Las 5 mejoras mencionadas. El formato `[Unreleased]` se mantiene. |
| 7.2 | Agregar un párrafo en `README.md` (sección "Memory" si existe, o nueva sección) describiendo el bundle OKF, el memory protocol, y `/skalling-forget`. Lenguaje simple, 1 párrafo (no sección larga). | Teo | `grep -q -i "memory\|memoria" README.md`. El párrafo es contiguo (no fragmentado). |
| 7.3 | Modificar `install-global.sh` para copiar `scripts/lib/lib-memory-check.sh` a `$OPENCODE_DIR/scripts/lib/` (similar a como copia `merge-helper.sh`). Esto es necesario para que el doctor y mem-review funcionen en la instalación global del usuario. | Teo | `grep -q "lib-memory-check.sh" install-global.sh`. La copia es condicional al flag `--dry-run` (igual que el resto). |
| 7.4 | Actualizar `tests/setup.test.sh` para verificar que los 6 nuevos archivos de test (`concept-template`, `memory-protocol`, `conflict-detection`, `lib-memory-check`, `mem-review`, `skalling-forget`, `doctor-memory`) existen y son ejecutables. Agregar también un check de que el snippet canónico existe. | Teo | `bash tests/setup.test.sh` exit 0. PASS incluye los nuevos asserts. |
| 7.5 | Verificar el handoff de regresión completo: correr `bash tests/setup.test.sh` + todos los nuevos tests. Output: todos PASS. Emite handoff a Luz con `verification` (comando + exit code + PASS count). | Teo | `bash tests/setup.test.sh && for t in tests/*.test.sh; do bash "$t"; done` exit 0. Reporte incluye counts por test. |
| 7.6 | **Auditoría de Luz** sobre el plan completo. Revisa cumplimiento de las 5 specs, ejecuta el doctor con bundle problemático, audita `setup.sh` contra constitution. Si PASA → Quality Gate PASSED. Si FALLA → rechazo con motivos. | Luz | Quality Gate PASSED con evidencia (exit codes de tests + doctor). |
| 7.7 | Pau archiva el change: `mv .opencode/changes/memory-improvements/ .opencode/changes/archive/2026-08/memory-improvements/`. Mueve los receipts si hay. Actualiza `index.md` del archive. | Pau | El change está en `archive/2026-08/`. `ls .opencode/changes/memory-improvements/` retorna "No such file". |

---

## 7. Plan de PRs (sugerido para adopción gradual)

A pesar de que el design recomienda "todo de una", los commits pueden separarse en 3 PRs para reducir el riesgo de review:

| PR | Fases | Justificación |
|---|---|---|
| **PR #1** (bajo riesgo) | Fase 1 + Fase 2 + Fase 3 | Solo cambios en `templates/`, `agents-base/`, `CHANGELOG.md`. Cero scripts. Cero riesgo de romper pipelines. |
| **PR #2** (riesgo medio) | Fase 4 + Fase 5 + Fase 6 | Cambia scripts: helper nuevo, mem-review, doctor, install-global. Requiere testing manual con bundle sintético. |
| **PR #3** (bajo riesgo) | Fase 7 (todo el cierre) | Después de Luz PASSED. Changelog, README, archive. |

Cada PR es mergeable independientemente. Si PR #2 tiene issues, PR #1 sigue funcionando.

---

## 8. Archivos a Tocar (consolidado)

### Nuevos

- `templates/agents/snippets/memory-protocol.md`
- `scripts/lib/lib-memory-check.sh`
- `scripts/mem-review.sh`
- `tests/concept-template.test.sh`
- `tests/memory-protocol.test.sh`
- `tests/conflict-detection.test.sh`
- `tests/lib-memory-check.test.sh`
- `tests/mem-review.test.sh`
- `tests/skalling-forget.test.sh`
- `tests/doctor-memory.test.sh`

### Modificados

- `templates/okf/concept.template.md` (body reescrito)
- `agents-base/Alex.md` (sección agregada)
- `agents-base/Pol.md` (sección + FASE 5)
- `agents-base/Jes.md` (sección agregada)
- `agents-base/Sol.md` (sección agregada)
- `agents-base/Teo.md` (sección agregada)
- `agents-base/Jhon.md` (sección agregada)
- `agents-base/Luz.md` (sección agregada)
- `agents-base/Pau.md` (sección extendida + instrucción de rechazo)
- `command/skalling-forget.md` (rewriter)
- `command/skalling-doctor.md` (tabla actualizada)
- `setup-team-doctor.sh` (función + invocación)
- `install-global.sh` (copia nuevo helper)
- `tests/setup.test.sh` (regresión agrega asserts)
- `CHANGELOG.md` (entrada en [Unreleased])
- `README.md` (párrafo memoria)

### NO tocados (verificado)

- `constitution/constitucion.md` ❌
- `docs/**` ❌
- Otros templates OKF ❌
- `.opencode/context/` del repo ❌

---

## 9. Open Questions (para confirmar antes de ejecutar)

### Q1 — Forma de inyección del memory protocol (Mejora 2)

**Default propuesto**:Option A (single source + copia con pointer en cada agente).

Ver `design.md` §9.1. Si el usuario prefiere Option B (solo referencia al path) o C (inline sin pointer), ajustar tareas 2.1-2.3 antes de ejecutar.

### Q2 — Umbrales por defecto

| Umbral | Default | Env var |
|---|---|---|
| WIP zombie | 30 días | `SKALLING_WIP_ZOMBIE_DAYS` |
| Vigencia | 6 meses | `SKALLING_STALE_MONTHS` |

Si el usuario quiere otros defaults, ajustar tareas 5.1 y 4.1.

### Q3 — Orden de PRs

El plan asume "todo de una, dividido en 3 PRs". Si el usuario prefiere shipear solo la Fase 1 primero (template, sin memory protocol), lo divido en PR #1a (solo Fase 1) + PR #1b (Fase 2 + 3).

---

## 10. Success Criteria (Verificación Final)

Cuando todas las tareas estén en DONE + Luz PASSED:

- [ ] `bash tests/setup.test.sh` exit 0 con el count incrementado.
- [ ] Los 6 nuevos tests exit 0.
- [ ] `bash setup-team-doctor.sh --strict --project <fixture-con-bundle-problemático>` exit 1 con los 3 issues detectados.
- [ ] `bash scripts/mem-review.sh --target <fixture-con-4-categorias>` agrupa en 4 secciones en el orden correcto.
- [ ] Los 8 agentes tienen la sección `## 🧠 Memory Protocol`.
- [ ] `agents-base/Pau.md` rechaza explícitamente concept docs sin las 4 secciones.
- [ ] `CHANGELOG.md` tiene entrada en `[Unreleased]` con las 5 mejoras.
- [ ] `README.md` menciona el bundle OKF y el memory protocol.
- [ ] Change archivado en `.opencode/changes/archive/2026-08/memory-improvements/`.

---

**Listo para handoff a Teo** una vez aprobado el design (con respuesta a Q1-Q3).
