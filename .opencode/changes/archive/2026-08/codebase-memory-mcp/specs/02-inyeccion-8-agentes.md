# Spec 02: Inyección del snippet en los 8 agentes

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then (BDD)
> **Cubre**: Punto 2 del scope (cada agente gana sección `## 🔍 Code Intelligence`).

---

## Escenario 1: Cada agente tiene la sección Code Intelligence

**Given** que el snippet canónico `templates/agents/snippets/code-intelligence.md` existe
**When** se actualizan los 8 agentes en `agents-base/`
**Then** los 8 archivos — `Alex.md`, `Pol.md`, `Jes.md`, `Sol.md`, `Teo.md`, `Jhon.md`, `Luz.md`, `Pau.md` — tienen una sección que arranca con `## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp`
**Y** los 8 archivos usan exactamente el mismo heading (consistencia)

---

## Escenario 2: El contenido está copiado del snippet

**Given** que el snippet canónico tiene contenido X
**When** un agente tiene la sección Code Intelligence
**Then** el contenido de la sección en ese agente **es el mismo** que el contenido del snippet canónico (copia literal)
**Y** la única diferencia permitida es el sub-heading `## 🔍 Code Intelligence` (en lugar de `# 🔍 Code Intelligence`) y los `###` en lugar de `##` para mantener la jerarquía interna del agente
**Y** NO hay resumen, paráfrasis ni versión "resumida" — copy-paste literal, porque sino se desincroniza

---

## Escenario 3: Comment block `SINCRONIZADO CON` presente en cada agente

**Given** que cada agente tiene la sección Code Intelligence
**When** se detecta drift del snippet canónico
**Then** cada agente tiene un comment block HTML con el texto exacto: `<!-- SINCRONIZADO CON: templates/agents/snippets/code-intelligence.md`
**Y** el bloque está inmediatamente antes del heading `## 🔍 Code Intelligence`
**Y** el bloque referencia al snippet canónico para auditoría humana

---

## Escenario 4: Orden de las secciones en cada agente

**Given** que cada agente tiene Memory Protocol + la nueva sección Code Intelligence
**When** se lee la estructura del agente
**Then** la sección `## 🔍 Code Intelligence` aparece **antes** de la sección `## 🧠 Memory Protocol`
**Y** la separación entre ambas es un `---` horizontal
**Y** no se reordena ninguna otra sección del agente (las reglas de oro, la personalidad, el ciclo, etc. siguen en su lugar original)

---

## Escenario 5: La inserción no rompe el frontmatter ni las reglas base

**Given** que cada agente tiene frontmatter (mode, permission) y reglas de oro
**When** se inserta la sección Code Intelligence
**Then** el frontmatter del agente **sigue intacto** en la primera línea del archivo
**Y** las "Reglas de oro" / personalidad del agente siguen donde estaban
**Y** la sección Code Intelligence no agrega permisos nuevos (los tools del MCP se invocan si el MCP está instalado; no requiere cambio de `permission:`)

---

## Reglas MUST (obligatorias)

1. Los 8 agentes **MUST** tener la sección `## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp`.
2. Los 8 agentes **MUST** tener el comment block `<!-- SINCRONIZADO CON: templates/agents/snippets/code-intelligence.md`.
3. La sección **MUST** estar ubicada **antes** de `## 🧠 Memory Protocol` en cada agente.
4. El contenido de la sección en cada agente **MUST** ser una copia del snippet canónico (mismas 5 tools, misma nota fallback, misma nota anti-abuso).
5. Los 8 agentes son: `Alex`, `Pol`, `Jes`, `Sol`, `Teo`, `Jhon`, `Luz`, `Pau`. **MUST** incluir los 8 — no se saltea ninguno.
6. La inserción **MUST NOT** modificar el frontmatter ni las reglas base de cada agente.

## Reglas SHOULD (recomendadas)

1. Cada agente **SHOULD** usar el mismo sub-heading interno (consistencia visual entre agentes al hacer `grep`).
2. La separación entre Code Intelligence y Memory Protocol **SHOULD** ser `---` (horizontal rule) — consistente con el patrón memory-improvements.

## Reglas MAY (opcionales)

1. Algún agente específico **MAY** agregar una nota contextual corta al final de la sección si su rol lo amerita (ej: "Sol usá `get_architecture` cuando planifiques features nuevas"). Estas notas son **excepciones documentadas**, no la norma.

---

## Criterios de Aceptación (resumen)

- [ ] `agents-base/Alex.md` tiene sección `## 🔍 Code Intelligence` + comment block
- [ ] `agents-base/Pol.md` tiene sección + comment block
- [ ] `agents-base/Jes.md` tiene sección + comment block
- [ ] `agents-base/Sol.md` tiene sección + comment block
- [ ] `agents-base/Teo.md` tiene sección + comment block
- [ ] `agents-base/Jhon.md` tiene sección + comment block
- [ ] `agents-base/Luz.md` tiene sección + comment block
- [ ] `agents-base/Pau.md` tiene sección + comment block
- [ ] En los 8 agentes, Code Intelligence aparece antes que Memory Protocol
- [ ] Test `tests/code-intelligence.test.sh` valida todos los puntos anteriores
- [ ] El frontmatter de los 8 agentes está intacto (regression check vía diff)

---

## Out of Spec (explícitamente NO incluido)

- Modificar la personalidad, ciclo o reglas base de cada agente (eso es scope de memory-improvements, no de este change).
- Agregar permisos nuevos al frontmatter para invocar tools del MCP (no es necesario si el MCP está configurado globalmente).
- Reescribir el Memory Protocol en simultáneo (cambio separado si se necesita).
- Adaptar el snippet a roles específicos (todos los agentes reciben el mismo contenido; excepciones MAY son notas cortas opcionales).
