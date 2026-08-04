# Proposal: Memory Improvements — 5 ideas tipo engram dentro de Skalling

> **Status**: Approved
> **Author**: Pol
> **Created**: 2026-08-03
> **Approved**: 2026-08-03 (by user — discusión previa cerrada)
> **Archived**: pendiente (lo archiva Pau al cerrar el plan)

## Why

El sistema de memoria de Skalling (bundle OKF en `.opencode/context/`) tiene tres problemas reales que hoy se manifiestan como fricción operativa:

1. **Concept docs sin estructura común.** Cada Pau los escribe a su criterio. Cuando Sol o Teo los leen meses después, no saben dónde mirar — si el "qué es", el "por qué" o el "qué aprendimos" está en cualquier parte. El template actual (`templates/okf/concept.template.md`) tiene 5 secciones (Qué es / Cómo se usa / Donde vive / Versiones / Links) pero ninguna garantiza captura del "por qué" ni de "qué aprendimos en el camino".

2. **Memoria voluntaria e inconsistente.** Hoy cada agente decide por su cuenta si guarda algo en `.opencode/context/trabajo-en-curso/` cuando termina una tarea. En la práctica: Pol a veces guarda, Sol a veces guarda, Teo casi nunca. Resultado: cuando volvés al proyecto en 3 semanas, no hay trail de qué se hizo, qué se decidió en el camino, ni qué bloqueos hubo.

3. **Sin detección de contradicciones.** Pol escribe un proposal hoy y puede contradecir una decisión del bundle OKF (`.opencode/context/decisiones/`) sin que nadie lo levante hasta que Teo intenta implementar y choca. Eso es R5 (Calidad Total) fallando en el origen.

4. **`/skalling-forget` está flojo.** El comando existe pero su lógica es básicamente "listar superseded → archivar". No detecta duplicados, no consolida trabajo-en-curso viejo, no marca "revisar vigencia" para entries sin usar hace meses. La política de olvido de la constitución (Pau consolida cada 6 meses, marca `⚠️ revisar vigencia` a los 12 meses sin referenciar) está documentada pero no implementada.

5. **El doctor no mira la memoria.** `setup-team-doctor.sh` valida ambiente, instalación global, instalación per-project, frontmatter, constitución, design-system, cambios. Pero no valida el bundle OKF más allá de "existe". Un proyecto con 50 concept docs huérfanos, sin `index.md` actualizado o con `trabajo-en-curso/` lleno de features zombie pasa el doctor en verde.

**Qué se gana**: memoria más escribible (template claro), más consistente (protocolo inyectado), más segura (contradicciones se levantan antes de aprobar), más sana (`/skalling-forget` con consolidación real y doctor que la vigila). Todo dentro del framework — sin binario externo, sin romper R12 (memoria por proyecto, bundle OKF).

**Por qué AHORA**: la memoria de Skalling está en su infancia (pocos proyectos con bundle maduro). Es el momento de establecer las prácticas antes de que la deuda se acumule. El framework todavía no salió al público — los adopters reciben estas mejoras desde el primer día.

## What Changes

Cinco mejoras concretas, todas dentro de Skalling (cero binarios externos):

### 1. Template What / Why / Where / Learned para concept docs

- Reemplazar el body del template `templates/okf/concept.template.md` por las 4 secciones fijas: **What** (qué es), **Why** (por qué existe / qué problema resuelve), **Where** (dónde vive en el código), **Learned** (qué aprendimos — incluye gotchas, workarounds descubiertos, decisiones forzadas por el contexto).
- Pau adopta este template como único válido para concept docs nuevos.
- Validación previa al commit/archivado: Pau rechaza concept docs nuevos que no tengan las 4 secciones.
- Concept docs existentes NO requieren migración (backward compatible — siguen siendo válidos; el template nuevo aplica solo a docs nuevos).

### 2. Memory Protocol — snippet inyectado en los 8 agentes

- Crear un snippet canónico en `templates/agents/snippets/memory-protocol.md` (archivo nuevo) con el texto estándar que cada agente recibe.
- El snippet instruye a cada agente: al cerrar una tarea significativa, guardar el estado en `.opencode/context/trabajo-en-curso/` con el formato del template `work-in-progress.template.md`; si detectás algo que contradice una decisión existente, marcarlo con `⚠️ CONTRADICE: <path>` antes de cerrar.
- Inyectar el snippet en los 8 agentes (`agents-base/Alex.md`, `Jes.md`, `Jhon.md`, `Luz.md`, `Pau.md`, `Pol.md`, `Sol.md`, `Teo.md`) mediante una sección común "🧠 MEMORY PROTOCOL" que referencie el snippet.

### 3. Detección de conflictos antes de aprobar un plan

- Pol, antes de cerrar el `proposal.md`, MUST leer los concept docs relevantes del bundle OKF: `.opencode/context/decisiones/` (ADRs activos), `.opencode/context/preferencias/` (convenciones) y `.opencode/context/problemas-conocidos/` (workarounds activos).
- Si Pol encuentra contradicción entre la propuesta y algún concept doc existente, MUST agregar al final del `proposal.md` una sección `## ⚠️ Conflictos detectados` con link al concept doc contradicho y razón de la contradicción.
- Si NO hay contradicción, MUST declarar al final del `proposal.md`: `## ✅ Sin conflictos con memoria existente`.
- Esto aplica para la ruta SDD. Para fast-track e inline, Pol hace un chequeo light (una sola pregunta al usuario si detecta contradicción obvia).

### 4. `/skalling-forget` mejorado con consolidación (`mem_review`)

- Reescribir `command/skalling-forget.md` para que, antes de purgar, ejecute una pasada de **`mem_review`** que:
  1. Detecta **duplicados** (concept docs con título o tags muy similares en la misma carpeta) y propone merge con link `supersedes:`.
  2. Detecta **trabajo-en-curso zombie** (entries con todas las tareas en `[x]` y `timestamp` > 30 días) y propone archivar a `.opencode/context/archive/<YYYY-MM>/`.
  3. Detecta **concept docs sin referenciar** por más de 6 meses y los marca con `⚠️ revisar vigencia`.
  4. Mantiene la lógica existente de superseded, workarounds cerrados y WorkInProgress completos.
- La presentación al usuario es agrupada por categoría (Duplicados / Zombie WIP / Vigencia / Superseded), con opciones A) archivar B) borrar C) conservar D) ver antes de decidir, **por candidato**, no en bloque.
- Agregar script de soporte `scripts/mem-review.sh` que automatiza la detección (las opciones A/B/C/D siguen siendo interactivas).

### 5. Sección "Memoria" en `setup-team-doctor.sh`

- Agregar la función `check_memory_health()` en `setup-team-doctor.sh`, invocada desde `check_project_install()` cuando existe `.opencode/context/`.
- Checks que MUST ejecutar:
  1. **`index.md` coherente**: todos los `concept docs/*.md` (excluyendo `index.md`, `log.md`, `README.md`) están referenciados desde algún `index.md` de su área. Huérfanos → warn con lista.
  2. **`trabajo-en-curso` sin cerrar hace > 30 días** → warn con lista de features zombie (basado en `timestamp` del frontmatter).
  3. **`index.md` desactualizado**: la cantidad de docs listados en `index.md` no coincide con la cantidad real de archivos `.md`. Discrepancia → warn.
  4. **`log.md` presente** → ok; si falta → info (no es crítico).
  5. **Duplicados obvios**: dos concept docs en la misma carpeta con el mismo `title` en frontmatter → err (es señal de copy-paste).
- `command/skalling-doctor.md` MUST actualizarse para reflejar la nueva sección "Memoria (bundle OKF)" en su tabla de output.

## Out of Scope

Explícitamente NO se hace en esta tanda:

- **No se introduce el binario engram** ni ningún sidecar externo. Toda la lógica vive dentro de Skalling (templates + agents + command + script bash).
- **No se implementa FTS5 ni búsqueda full-text** sobre el bundle OKF. Búsqueda sigue siendo `grep`/`find` (es lo que ya hace Pau y los agentes). Si más adelante hace falta, va en otro change.
- **No se agrega cloud sync ni replicación del bundle.** Memoria sigue siendo local al proyecto (R12). El backup es responsabilidad del usuario (`git`, snapshots).
- **No se implementa captura pasiva automática** (por ejemplo, hook post-commit que guarde cada diff en memoria). El memory protocol es activo: cada agente decide explícitamente cuándo guardar. La captura pasiva es orthogonal y tiene costos (ruido) que no queremos asumir.
- **No se migran concept docs existentes al nuevo template.** Aplica solo a docs nuevos. Los existentes siguen siendo válidos (backward compatibility).
- **No se modifica el ciclo SDD** (Pol → Sol → Teo ↔ Jhon → Luz → Pau). Solo se agrega el chequeo de conflictos en Pol y el memory protocol como comportamiento de los agentes.
- **No se cambia la constitución.** Las reglas R12 (memoria por proyecto), R13 (design-system.md), R16 (commits con consentimiento) se mantienen tal cual. Esta tanda es operativa, no constitucional.
- **No se reescribe el memory protocol como skill.** Es un snippet de texto en los prompts de los agentes. Convertirlo en skill es otro change (overkill ahora).

## Rollback Plan

- **Migración reversible**: sí. Todo cambio es modificable en `templates/`, `agents-base/`, `command/`, `setup-team-doctor.sh`, `scripts/`. No hay migración de datos ni schema nuevo en el bundle OKF.
- **Feature flag**: no aplica (no hay runtime condicional — los agentes simplemente adoptan las nuevas instrucciones).
- **Pasos de rollback**:
  1. `git revert` del PR que introduce las 5 mejoras.
  2. `bash setup-team-doctor.sh --strict` para validar que el rollback no rompe la instalación base.
  3. Pau limpia cualquier concept doc nuevo que se haya creado con la nueva estructura (los existentes no se tocan).
  4. Si se agregó `scripts/mem-review.sh`, borrar.
- **Datos afectados**: ninguno. Solo cambia comportamiento y templates. El bundle OKF existente sigue intacto.

## Success Criteria

Cómo medimos que esta tanda funcionó:

- **Adopción del template (mejora 1)**: 100% de los concept docs nuevos creados por Pau después del deploy siguen el template What/Why/Where/Learned. Verificable por inspección de los commits de Pau.
- **Aplicación del memory protocol (mejora 2)**: en un ciclo SDD completo (Pol → Sol → Teo → Jhon → Luz → Pau), al menos 2 entradas se guardan en `.opencode/context/trabajo-en-curso/` durante la implementación (en lugar de 0 o 1 errática como antes). Verificable por inspección del bundle después de un feature real.
- **Detección de conflictos (mejora 3)**: cuando Pol escribe un proposal que contradice una decisión existente, la sección `⚠️ Conflictos detectados` aparece en al menos el 80% de los proposals conflictivos. Verificable por inspección de `.opencode/changes/<feature>/proposal.md` después de un feature real (puede requerir tests de regresión artificial si no hay features conflictivos en el corto plazo).
- **`/skalling-forget` con consolidación (mejora 4)**: tras correr el comando sobre un bundle con al menos 5 concept docs, el output muestra al menos 3 categorías (Duplicados / Vigencia / Zombie WIP) con candidatos detectados. Verificable manualmente con un bundle sintético.
- **Doctor con sección memoria (mejora 5)**: `bash setup-team-doctor.sh --strict` sobre un proyecto con bundle problemático (1 huérfano + 1 WIP zombie + 1 index desactualizado) detecta los 3 issues. Verificable con un fixture de prueba.

## Affected Areas

Archivos y áreas que se tocan (estimativa — Sol afinará en `design.md`):

**Templates**:
- `templates/okf/concept.template.md` — body reescrito con 4 secciones What/Why/Where/Learned.
- `templates/agents/snippets/memory-protocol.md` — archivo nuevo con el snippet canónico.

**Agentes** (`agents-base/`):
- `Alex.md` — agregar sección "🧠 MEMORY PROTOCOL".
- `Jes.md` — idem.
- `Jhon.md` — idem.
- `Luz.md` — idem.
- `Pau.md` — idem + adoptar el template nuevo explícitamente.
- `Pol.md` — idem + nueva fase "Chequeo de conflictos" antes de cerrar proposal.
- `Sol.md` — idem.
- `Teo.md` — idem.

**Comandos** (`command/`):
- `skalling-forget.md` — reescrito con pasada de `mem_review`.
- `skalling-doctor.md` — tabla de output actualizada con sección "Memoria".

**Scripts** (`scripts/`):
- `scripts/mem-review.sh` — script nuevo (soporte a `/skalling-forget`).
- `setup-team-doctor.sh` — nueva función `check_memory_health()`.

**Tests** (`tests/`):
- `tests/mem-review.test.sh` — tests bash para `scripts/mem-review.sh` (R4: lógica nueva con test).
- `tests/doctor-memory.test.sh` — tests bash para la nueva sección del doctor.

**Documentación**:
- `README.md` — mención breve de las nuevas prácticas (1 párrafo en sección "Memory").
- `CHANGELOG.md` — entrada bajo próxima versión.

**NO se tocan**:
- `constitution/constitucion.md` — sin cambios (las reglas R12/R13/R16 siguen igual).
- `docs/` — sin cambios (la doc pública de Skalling no necesita actualizarse en esta tanda; es detalle operativo).
- `.opencode/context/` del repo actual — sin cambios (es memoria de runtime, no del framework).

## Dependencies

- **Bloqueado por**: nada. Esta tanda es independiente.
- **Bloquea a**: nada concreto. Cambios futuros podrían aprovechar el memory protocol (por ejemplo, una skill de "context recall"), pero eso es ortogonal.
- **Dependencias externas**: ninguna. Solo herramientas que ya están en el repo (bash >= 4, `grep`, `find`, `yq` opcional para parsear YAML si Sol lo decide).

## Stakeholders

- **Requester**: usuario (Akizuki).
- **Reviewers**: Pol (esta proposal+specs), Sol (design+tasks), Teo (implementación), Jhon (tests), Pau (documentación).
- **Approver**: usuario final (confirmación vía Alex relay).
