# Spec 01: Snippet canónico `code-intelligence.md`

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then (BDD)
> **Cubre**: Punto 1 del scope (snippet single source con guía de "cuándo usar cada tool").

---

## Escenario 1: El snippet existe como single source

**Given** que la integración de codebase-memory-mcp está aprobada
**When** se crea `templates/agents/snippets/code-intelligence.md`
**Then** el archivo existe en esa ruta exacta
**Y** empieza con un heading `# 🔍 Code Intelligence (snippet canónico)`
**Y** contiene la nota de single source: `> **Este snippet es single source. Las copias en cada agente están sincronizadas por convención.`

---

## Escenario 2: Las 5 tools principales están documentadas con criterio de uso

**Given** que el snippet existe
**When** un agente lo lee para decidir qué tool usar
**Then** el snippet contiene una sección por cada uno de los 5 tools principales, en este orden:

1. **`mcp__codebase-memory-mcp__trace_path`** — para "quién llama a X" / "qué afecta X"
2. **`mcp__codebase-memory-mcp__get_architecture`** — para "cómo funciona Y" / "overview del proyecto"
3. **`mcp__codebase-memory-mcp__search_graph`** — para "buscá función/clase por nombre"
4. **`mcp__codebase-memory-mcp__find_dead_code`** — para "¿esto es código muerto?"
5. **`mcp__codebase-memory-mcp__detect_changes`** — para "¿qué cambia este PR/diff?"

**Y** cada sección tiene al menos un ejemplo concreto de pregunta en lenguaje natural que dispara ese tool
**Y** cada sección indica cuándo **NO** usar el tool (cuándo `grep`/`read` sigue ganando)

---

## Escenario 3: Nota de fallback cuando el MCP no está instalado

**Given** que un proyecto no tiene codebase-memory-mcp instalado
**When** un agente lee el snippet buscando guía
**Then** el snippet contiene una nota explícita con el texto (case-insensitive): `si codebase-memory-mcp NO está instalado`
**Y** la nota instruye al agente a seguir con `grep`/`read` como siempre
**Y** la nota aclara que el snippet NO debe romper proyectos sin el MCP (no debe haber asserts rígidos en otros agentes)

---

## Escenario 4: Nota anti-abuso

**Given** que un agente podría sobre-usar los tools del MCP
**When** lee el snippet antes de tomar una decisión
**Then** el snippet contiene una nota explícita con el texto (case-insensitive): `NO abuses`
**Y** la nota indica que para cambios triviales no vale la pena el query
**Y** la nota sugiere heurística: si la respuesta cabe en 1–2 archivos, `grep` es más rápido que indexar

---

## Escenario 5: Comment block de sincronización al final

**Given** que el snippet es single source
**When** otro agente o desarrollador lo edita
**Then** el snippet termina con un bloque de sincronización con el texto: `SINCRONIZADO CON:`
**Y** el bloque referencia las 8 copias en `agents-base/*.md` que deben actualizarse en el mismo PR

---

## Reglas MUST (obligatorias)

1. El archivo **MUST** existir en `templates/agents/snippets/code-intelligence.md`.
2. El archivo **MUST** documentar los 5 tools: `trace_path`, `get_architecture`, `search_graph`, `find_dead_code`, `detect_changes`.
3. El archivo **MUST** incluir la nota de fallback "si codebase-memory-mcp NO está instalado, seguí con grep/read como siempre".
4. El archivo **MUST** incluir la nota anti-abuso "NO abuses: para cambios triviales no vale la pena el query".
5. El archivo **MUST** terminar con un comment block que contenga `SINCRONIZADO CON:` y la referencia a las 8 copias.
6. El archivo **MUST** estar en español (consistente con el resto de Skalling).

## Reglas SHOULD (recomendadas)

1. Cada tool **SHOULD** tener un ejemplo concreto de pregunta natural que lo dispara (ej: "quién llama a `parseUserInput`" → `trace_path`).
2. El snippet **SHOULD** mencionar que el grafo se construye con `codebase-memory-mcp index` (responsabilidad del usuario, no de Skalling).
3. El snippet **SHOULD** tener ~80 líneas (±20) — guía concisa, no enciclopedia.

## Reglas MAY (opcionales)

1. El snippet **MAY** incluir un ejemplo de output esperado del MCP para uno de los tools (referencia visual).
2. El snippet **MAY** linkear a la documentación externa de codebase-memory-mcp.

---

## Criterios de Aceptación (resumen)

- [ ] `templates/agents/snippets/code-intelligence.md` existe
- [ ] Contiene heading `# 🔍 Code Intelligence`
- [ ] Contiene las 5 menciones de tools: `trace_path`, `get_architecture`, `search_graph`, `find_dead_code`, `detect_changes`
- [ ] Contiene nota fallback (case-insensitive): `si codebase-memory-mcp NO está instalado`
- [ ] Contiene nota anti-abuso (case-insensitive): `NO abuses`
- [ ] Contiene comment block `SINCRONIZADO CON:`
- [ ] Está en español
- [ ] Test `tests/code-intelligence.test.sh` valida todos los puntos anteriores (PASS ≥ 12 acumulado con las otras specs)
- [ ] No hay reglas MUST sin test correspondiente

---

## Out of Spec (explícitamente NO incluido)

- Documentación detallada de los 10 tools secundarios del MCP (no es responsabilidad de Skalling).
- Ejemplos de uso en proyectos específicos (los ejemplos son genéricos).
- Internacionalización (solo español).
- Versión del MCP pinneada — el snippet es agnóstico a la versión del binario.
