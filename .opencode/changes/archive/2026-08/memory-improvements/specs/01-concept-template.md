# Spec: Concept Template — What / Why / Where / Learned

> **Status**: Draft
> **Mejora**: #1 de memory-improvements
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

---

## Escenario 1: Pau crea un concept doc nuevo

**Given** que Luz aprobó un feature (Quality Gate PASSED) y Pau está documentando
**When** Pau crea un nuevo archivo en `.opencode/context/decisiones/` (o `preferencias/`, `problemas-conocidos/`, etc.)
**Then** el archivo MUST seguir el template `templates/okf/concept.template.md`
**Y** el body MUST contener exactamente 4 secciones con estos encabezados exactos: `## What`, `## Why`, `## Where`, `## Learned`
**Y** cada sección MUST tener al menos una línea de contenido (no se permite sección vacía)

---

## Escenario 2: Pau valida antes de archivar

**Given** que Pau terminó de escribir un concept doc nuevo
**When** Pau intenta mover el change completo a `.opencode/changes/archive/<YYYY-MM>/`
**Then** Pau MUST primero verificar que el concept doc tiene las 4 secciones What/Why/Where/Learned
**Y** si falta alguna, Pau MUST rechazar el archivado y pedirle a Teo (o a sí misma si es owner) que complete las secciones faltantes antes de archivar
**Y** solo después de validar, archiva normalmente

---

## Escenario 3: Concept doc legacy (existente antes del deploy)

**Given** que existe un concept doc en el bundle OKF escrito antes del deploy de esta mejora (sin las 4 secciones What/Why/Where/Learned)
**When** cualquier agente lo lee durante un ciclo SDD
**Then** el doc MUST seguir siendo válido y navegable (no se rechaza, no se exige migración)
**Y** el frontmatter OKF (tipo, título, resource, etc.) MUST seguir siendo válido
**Y** los 5 secciones legacy (Qué es / Cómo se usa / Donde vive / Versiones / Links) MUST seguir funcionando

---

## Escenario 4: Pau detecta un concept doc mal formado

**Given** que Pau recibe un concept doc nuevo incompleto (le falta "Learned")
**When** Pau revisa el archivo
**Then** Pau MUST reportar el faltante con el texto: `⚠️ Concept doc incompleto: falta sección "Learned" en [path]. No archivable hasta completar.`
**Y** Pau NO debe archivar el change asociado hasta que la sección esté presente

---

## Escenario 5: Edge case — sección vacía intencional

**Given** que Pau legítimamente no tiene información para una sección (por ejemplo, no hubo "Learned" porque la feature fue trivial)
**When** Pau escribe el concept doc
**Then** Pau MAY usar el placeholder `_(sin contenido por ahora — completar cuando aplique)_` dentro de la sección vacía
**Y** el doc MUST seguir contando como válido (porque la sección existe, aunque esté marcada como pendiente)
**Y** `supersedes` o `confidence` en el frontmatter NO se ven afectados

---

## Reglas MUST (obligatorias)

1. `templates/okf/concept.template.md` MUST tener las 4 secciones `## What`, `## Why`, `## Where`, `## Learned` como encabezados exactos en el body.
2. Pau MUST rechazar concept docs nuevos que no tengan las 4 secciones antes de archivar el change.
3. Pau MUST usar el template actualizado como única fuente válida para concept docs nuevos.
4. El frontmatter OKF (tipo, título, resource, tags, timestamp, agent, confidence, supersedes) MUST permanecer sin cambios — solo cambia el body.
5. Las secciones MUST estar en este orden: What → Why → Where → Learned. Pau no puede reordenarlas.

## Reglas SHOULD (recomendadas)

1. La sección `## What` SHOULD tener entre 1 y 3 oraciones (qué es, en una línea si es posible).
2. La sección `## Why` SHOULD explicar el dolor concreto que motivó la existencia del concepto (no la feature, el dolor).
3. La sección `## Where` SHOULD listar los paths exactos en el código, con comentarios breves de qué hace cada uno.
4. La sección `## Learned` SHOULD capturar al menos un insight útil (workaround, decisión forzada, gotcha descubierto durante implementación).
5. Si el concept doc reemplaza uno anterior, el frontmatter MUST incluir `supersedes: [path al viejo]` y la sección `## Why` SHOULD mencionar qué cambió respecto al viejo.

## Reglas MAY (opcionales)

1. Concept docs de tipo `Concept` MAY tener un diagrama Mermaid corto dentro de `## What` o `## Where` si ayuda a visualizar.
2. Concept docs de tipo `Workaround` MAY tener la sección `## Learned` más larga (es donde vive la "trampa" del workaround).
3. Pau MAY linkear a issues de git, PRs o commits relevantes desde `## Why` o `## Learned` si aporta trazabilidad.

---

## Criterios de Aceptación (resumen)

- [ ] `templates/okf/concept.template.md` tiene las 4 secciones en el orden correcto.
- [ ] Pau está explícitamente instruida en `agents-base/Pau.md` a rechazar concept docs nuevos sin las 4 secciones.
- [ ] En un bundle sintético de prueba (creado por test), Pau detecta el rechazo cuando falta una sección.
- [ ] En un bundle con concept docs legacy (sin las 4 secciones), Pau los acepta como válidos sin pedir migración.
- [ ] Test bash existe en `tests/concept-template.test.sh` que verifica la estructura del template.
- [ ] No se rompió el flujo de archivado: Pau sigue moviendo `.opencode/changes/<feature>/` a `.opencode/changes/archive/<YYYY-MM>/` correctamente.

---

## Out of Spec (explícitamente NO incluido)

- Migración de concept docs existentes al nuevo template (backward compatibility).
- Cambios en el frontmatter OKF (sigue siendo el schema de OKF v0.2).
- Cambios en otros templates (`decision.template.md`, `workaround.template.md`, etc.) — solo `concept.template.md` se modifica en esta mejora.
- Validación automática por script (la validación es responsabilidad de Pau, no del doctor — la validación automática del bundle vive en la mejora #5).
- Forzar a todos los agentes a usar las 4 secciones en su lectura (cada agente lee como quiera; el cambio es solo al template y a la práctica de Pau).
