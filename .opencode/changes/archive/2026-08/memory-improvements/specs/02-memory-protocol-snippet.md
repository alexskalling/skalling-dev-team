# Spec: Memory Protocol Snippet — inyección en los 8 agentes

> **Status**: Draft
> **Mejora**: #2 de memory-improvements
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then

---

## Escenario 1: Agente cierra una tarea significativa

**Given** que un agente (cualquiera de los 8) terminó una tarea que generó aprendizaje, decisión o cambio de estado
**When** el agente está por cerrar su handoff al siguiente agente (o cerrar su propio ciclo si es terminal)
**Then** el agente SHOULD evaluar si lo que aprendió/decidió merece guardarse en `.opencode/context/trabajo-en-curso/` o en la carpeta correspondiente del bundle OKF
**Y** si merece, el agente MUST crear o actualizar el archivo siguiendo el template `templates/okf/work-in-progress.template.md` (o el template del tipo correspondiente)

---

## Escenario 2: Agente detecta contradicción con memoria existente

**Given** que un agente está por cerrar una tarea y nota que lo que hizo contradice un concept doc existente (decisión, preferencia, workaround)
**When** el agente detecta la contradicción
**Then** el agente MUST agregar al concept doc contradicho (o al final de su propio handoff) una marca `⚠️ CONTRADICE: [path al concept doc] — [razón breve]`
**Y** el agente MUST notificar la contradicción en su handoff al siguiente agente con el campo `contradicciones_detectadas: [lista]`
**Y** el agente NO debe silenciar la contradicción ni proceder como si nada

---

## Escenario 3: Pau inmortaliza trabajo terminado

**Given** que Luz aprobó un feature completo (Quality Gate PASSED) y Pau está por documentar
**When** Pau revisa los entries de `.opencode/context/trabajo-en-curso/` relacionados al feature
**Then** Pau MUST consolidar los entries significativos en concept docs definitivos (siguiendo mejora #1: template What/Why/Where/Learned)
**Y** Pau MUST mover los entries de `trabajo-en-curso/` a `archive/<YYYY-MM>/` si ya están completos (todas las tareas en `[x]`)
**Y** Pau MUST actualizar el frontmatter `supersedes` si el nuevo doc reemplaza uno anterior

---

## Escenario 4: Agente NO guarda trivialidades

**Given** que un agente hizo un cambio trivial (un typo, una variable renombrada, una config ajustada)
**When** el agente evalúa si guardar
**Then** el agente SHOULD NO guardar en `trabajo-en-curso/` (trivialidades no son memoria significativa)
**Y** el agente SHOULD NO marcar contradicciones (no hay contradicción en un rename)
**Y** este filtro de "trivial vs significativo" queda a criterio del agente con la guía del snippet

---

## Escenario 5: Agente olvida el memory protocol

**Given** que un agente termina su tarea sin haber ejecutado el memory protocol (no guardó nada significativo, no marcó contradicciones)
**When** Alex valida el cierre del ciclo
**Then** Alex SHOULD recordar al agente: `🧠 Memory protocol: ¿hay algo significativo para guardar en .opencode/context/trabajo-en-curso/? ¿hay contradicciones con memoria existente?`
**Y** si el agente responde "no hay nada significativo", Alex MUST aceptar la respuesta y avanzar (no debe bloquear el ciclo por memoria vacía)

---

## Reglas MUST (obligatorias)

1. El snippet canónico MUST vivir en `templates/agents/snippets/memory-protocol.md` (archivo nuevo, ruta única).
2. Los 8 archivos en `agents-base/` MUST incluir una sección `## 🧠 Memory Protocol` que referencie el snippet en `templates/agents/snippets/memory-protocol.md` y aplique su contenido al agente correspondiente.
3. Cada agente MUST evaluar antes de cerrar su handoff si hay algo significativo para guardar en `.opencode/context/`.
4. Si un agente detecta contradicción con un concept doc existente, MUST marcarla con `⚠️ CONTRADICE: [path]` en el concept doc o en su handoff.
5. Pau MUST ser la única que consolida trabajo-en-curso terminado en concept docs definitivos y los archiva. Los otros agentes NO archivan ni consolidan — solo dejan rastro en `trabajo-en-curso/`.
6. El snippet MUST ser texto markdown puro, sin dependencias externas (no requiere skill especial para cargarse).

## Reglas SHOULD (recomendadas)

1. El snippet SHOULD diferenciar entre "memoria operativa" (`trabajo-en-curso/`) y "memoria definitiva" (carpetas como `decisiones/`, `preferencias/`, `problemas-conocidos/`). Los agentes deberían guardar en operativa primero; Pau promueve a definitiva.
2. El snippet SHOULD recordar a los agentes que NO guarden secrets, credenciales, ni información sensible (R10 constitucional).
3. El snippet SHOULD mencionar que el bundle OKF es local al proyecto (R12) — no se replica ni sincroniza.
4. Pau SHOULD actualizar `index.md` cada vez que consolida trabajo-en-curso en un concept doc definitivo.

## Reglas MAY (opcionales)

1. Los agentes MAY crear entries en `trabajo-en-curso/` incluso si la tarea es relativamente chica, si aporta contexto futuro (por ejemplo, una decisión de stack que se va a usar 3 sprints más adelante).
2. Un agente MAY delegar la decisión de "guardar o no" a Pau cuando no esté seguro — pero NO MAY saltarse la evaluación.
3. Los agentes MAY usar tags en el frontmatter para facilitar la búsqueda posterior (`tags: [decision-pendiente, refactor-pendiente]`).

---

## Criterios de Aceptación (resumen)

- [ ] `templates/agents/snippets/memory-protocol.md` existe con el texto del snippet canónico.
- [ ] Los 8 archivos en `agents-base/` (`Alex.md`, `Jes.md`, `Jhon.md`, `Luz.md`, `Pau.md`, `Pol.md`, `Sol.md`, `Teo.md`) tienen la sección `## 🧠 Memory Protocol` con referencia al snippet.
- [ ] El snippet instruye explícitamente: (a) cuándo guardar, (b) cómo marcar contradicciones, (c) cuándo NO guardar.
- [ ] En un ciclo SDD simulado, al menos 2 agentes (distintos a Pau) crean entries en `trabajo-en-curso/` durante la implementación.
- [ ] Pau consolida y archiva correctamente al cerrar el feature.
- [ ] Alex incluye en su checklist de cierre la pregunta sobre memory protocol.

---

## Out of Spec (explícitamente NO incluido)

- Crear una skill `skalling-memory-protocol` (overkill ahora — el snippet en texto plano alcanza).
- Captura pasiva automática (hooks post-commit, etc.) — el memory protocol es activo, decisión del agente.
- Sincronización del bundle con servicios externos (git remote, cloud) — ortogonal a esta mejora.
- Cambios en `Alex.md` para que cargue el snippet dinámicamente — el snippet se inyecta como texto en los prompts, no se carga runtime.
- Modificar el comportamiento de Pau más allá de "recibir handoffs con memoria operativa y consolidar" — Pau ya tiene su flujo propio, solo se le agrega la instrucción explícita del memory protocol.
- Forzar a todos los agentes a guardar (la regla es "evaluar y decidir"; el agente decide "no significativo" si corresponde).
