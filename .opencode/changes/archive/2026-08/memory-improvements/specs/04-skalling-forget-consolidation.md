# Spec: `/skalling-forget` mejorado con consolidación (`mem_review`)

> **Status**: Draft
> **Mejora**: #4 de memory-improvements
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

---

## Escenario 1: Usuario corre `/skalling-forget` con bundle sano

**Given** que el usuario corrió `/skalling-forget` y existe `.opencode/context/` con varios concept docs
**When** el comando arranca
**Then** el comando MUST ejecutar primero la pasada de `mem_review` (script `scripts/mem-review.sh`) ANTES de presentar cualquier candidato a purga
**Y** el output MUST estar agrupado en 4 categorías: **Duplicados**, **Trabajo-en-curso zombie**, **Vigencia (>6 meses sin ref)**, **Superseded**

---

## Escenario 2: `mem_review` detecta duplicados

**Given** que existen 2 o más concept docs en la misma carpeta con `title:` en frontmatter idéntico o muy similar (mismo nombre normalizado)
**When** `scripts/mem-review.sh` corre la pasada de duplicados
**Then** el script MUST listar los pares duplicados con sus paths
**Y** cada par MUST aparecer en la categoría "Duplicados" del output de `/skalling-forget`
**Y** el comando MUST proponer la opción "A) Merge (consolidar en uno y marcar el otro con `supersedes:`)"

---

## Escenario 3: `mem_review` detecta trabajo-en-curso zombie

**Given** que existe un archivo en `.opencode/context/trabajo-en-curso/` con `timestamp` en frontmatter de hace más de 30 días Y todas las tareas en el body marcadas con `[x]`
**When** `scripts/mem-review.sh` corre la pasada de WIP zombie
**Then** el script MUST listarlo como candidato zombie con su path, timestamp y última actualización
**Y** el comando MUST proponer la opción "A) Archivar a `.opencode/context/archive/<YYYY-MM>/`"

---

## Escenario 4: `mem_review` detecta concept docs sin referenciar por >6 meses

**Given** que existe un concept doc (cualquier tipo) sin referenciar desde `index.md` u otros docs por más de 6 meses (basado en `timestamp` y cross-references en el cuerpo)
**When** `scripts/mem-review.sh` corre la pasada de vigencia
**Then** el script MUST listarlo como candidato a "revisar vigencia"
**Y** el comando MUST proponer opciones: "A) Marcar con `⚠️ revisar vigencia` en el frontmatter", "B) Archivar", "C) Conservar"

---

## Escenario 5: `mem_review` detecta superseded

**Given** que existen concept docs con frontmatter `supersedes: [path a versión anterior]`
**When** el comando corre
**Then** la lógica existente de superseded MUST seguir funcionando (mantiene compatibilidad con `/skalling-forget` legacy)
**Y** los superseded detectados MUST listarse en la categoría "Superseded" del output

---

## Escenario 6: Usuario decide por candidato (no en bloque)

**Given** que el comando mostró candidatos en las 4 categorías
**When** el usuario revisa
**Then** las opciones A) archivar / B) borrar / C) conservar / D) ver antes de decidir MUST presentarse **por cada candidato individualmente**, NO en bloque
**Y** el usuario puede mezclar decisiones (archivar el #1, borrar el #2, conservar el #3) sin tener que comprometerse con una sola política para todos

---

## Escenario 7: Loggeo de la purga

**Given** que el usuario completó sus decisiones
**When** el comando aplica archivados/borrados/conservados
**Then** el comando MUST appendar a `.opencode/context/log.md`:
```markdown
## YYYY-MM-DD HH:MM — `/skalling-forget` consolidación
**Por:** alex (forget)
**Categoría Duplicados:**
  - Merge propuesto: [paths] (Aceptado/Rechazado)
  - ...
**Categoría WIP Zombie:**
  - Archivado: [paths]
  - Conservado: [paths]
  - ...
**Categoría Vigencia:**
  - Marcado ⚠️: [paths]
  - Archivado: [paths]
  - ...
**Categoría Superseded:**
  - Archivado: [paths]
  - Borrado: [paths]
  - ...
**Razón:** mem_review pre-purga (duplicados + zombie + vigencia + superseded)
```

---

## Escenario 8: Validación post-purga

**Given** que el comando terminó de aplicar decisiones
**When** el usuario ejecuta la post-validación
**Then** el comando SHOULD correr `bash setup-team-doctor.sh --strict` automáticamente
**Y** si el doctor detecta issues (huérfanos nuevos por archivar mal un index), MUST advertir antes de cerrar

---

## Reglas MUST (obligatorias)

1. `command/skalling-forget.md` MUST reescribirse para que el primer paso sea invocar `scripts/mem-review.sh`.
2. `scripts/mem-review.sh` MUST existir como archivo ejecutable y MUST detectar: duplicados por `title`, WIP zombie (timestamp >30d + todas las tareas `[x]`), vigencia sin referenciar >6 meses, y superseded existentes.
3. El output de `/skalling-forget` MUST estar agrupado en 4 categorías en este orden: Duplicados → WIP Zombie → Vigencia → Superseded.
4. Cada candidato MUST presentarse individualmente con sus opciones A/B/C/D, no en bloque.
5. La decisión del usuario MUST loggearse en `.opencode/context/log.md` con detalle por categoría.
6. El comando MUST mantener la política "preferir archivar sobre borrar" (la historia es valiosa).
7. El comando MUST respetar las advertencias existentes: nunca borrar constitución, nunca borrar `index.md`/`README.md`/`log.md`.
8. El comando NO debe tocar `.opencode/changes/` (SDD), `docs/` (público), ni `.opencode/state/` (workflow state).

## Reglas SHOULD (recomendadas)

1. `mem_review` SHOULD usar `find`, `grep` y parsing de frontmatter YAML con regex (sin dependencias externas; opcionalmente `yq` si está disponible).
2. Las opciones SHOULD presentarse con defaults razonables (por ejemplo, "Duplicados → default es merge; WIP zombie → default es archivar; Vigencia → default es marcar").
3. El comando SHOULD permitir al usuario correr `mem_review` sin aplicar decisiones (modo "dry-run" para inspección).
4. El log SHOULD incluir el timestamp de cada candidato para auditoría.

## Reglas MAY (opcionales)

1. `mem_review` MAY detectar también "tags huérfanos" (tags en frontmatter que no se usan en ningún otro doc).
2. El comando MAY permitir configurar el umbral de "WIP zombie" (default 30 días) y "vigencia" (default 6 meses) por variable de entorno.
3. El comando MAY sugerir `supersedes:` automático cuando detecta duplicados (pre-llenar la opción A con el path destino).

---

## Criterios de Aceptación (resumen)

- [ ] `command/skalling-forget.md` reescrito con la pasada de `mem_review` como primer paso.
- [ ] `scripts/mem-review.sh` existe, es ejecutable, y detecta las 4 categorías.
- [ ] Test bash en `tests/mem-review.test.sh` cubre: detección de duplicados por title, WIP zombie, vigencia >6m, superseded.
- [ ] Test bash en `tests/skalling-forget.test.sh` cubre el flujo end-to-end (bundle sintético → comando → decisiones → log.md actualizado).
- [ ] El output está agrupado en las 4 categorías en el orden correcto.
- [ ] Las decisiones se loggean en `.opencode/context/log.md` con detalle por categoría.
- [ ] El comando respeta las advertencias existentes (no borra constitución, no toca SDD/docs/state).
- [ ] El doctor post-purga detecta issues si el archivado dejó huérfanos.

---

## Out of Spec (explícitamente NO incluido)

- Borrado automático sin confirmación del usuario (la consolidación es siempre supervisada).
- Sincronización del archive con git remotes o cloud (ortogonal; el commit/archivo se hace vía flujo normal del usuario).
- Modificación de la constitución para cambiar los umbrales (los defaults 30d/6m son configurables por env var, no por regla constitucional).
- Reescritura completa del bundle (esto es mantenimiento, no reescritura).
- Detección de contradicciones semánticas entre concept docs (eso es trabajo de Pol o del memory protocol, no del forget).
- Integración con el memory protocol de la mejora #2 (el forget es independiente del memory protocol operativo).
