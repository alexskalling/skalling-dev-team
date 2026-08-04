# Proposal: Integración opt-in de codebase-memory-mcp

> **Status**: Approved
> **Author**: Pol
> **Created**: 2026-08-04
> **Approved**: 2026-08-04 (by user)
> **Scope**: Skalling v0.4.0

## Why

Los agentes de Skalling (Sol, Teo, Jhon, Luz, Pau) gastan una proporción alta de tokens **leyendo código** cuando necesitan entender impacto, dependencias o estructura de un codebase grande. Hoy el flujo es `grep` + `read` sobre docenas de archivos, lo que:

- **Infla el contexto** de cada handoff (10–30 archivos leídos solo para "qué afecta X").
- **Retrasa decisiones** de Sol y Teo que podrían tomarse con un grafo de llamadas precomputado.
- **Limita a Pau y Jhon** al revisar PRs — no tienen visibilidad de blast radius sin leer todo el repo.

`codebase-memory-mcp` ([DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)) es un servidor MCP de **inteligencia estructural de código**: binario estático que indexa codebases en un grafo de funciones/clases/calls y expone 15 tools (`trace_path`, `get_architecture`, `search_graph`, `find_dead_code`, `detect_changes`, etc.). En lugar de leer 20 archivos, Sol hace 1 query y obtiene el call graph.

**Opt-in, no dependencia dura.** Skalling mantiene su promesa de "zero deps" para el 95% de usuarios. Quien quiera el boost de inteligencia estructural lo activa explícitamente en `/skalling-init`. Quien no, sigue con `grep`/`read` exactamente igual que hoy.

**Cuándo, no solo qué.** Agregar tools sin guía de uso es feature creep inútil. Los agentes deben aprender **cuándo** cada tool vale el query (y cuándo `grep` sigue ganando). Eso se logra con un snippet canónico en system prompt — el mismo patrón que `memory-protocol.md`.

## What Changes

1. **Nuevo snippet canónico `templates/agents/snippets/code-intelligence.md`**: single source que define cuándo usar cada uno de los 5 tools principales de codebase-memory-mcp. Incluye nota explícita "si codebase-memory-mcp NO está instalado, seguí con grep/read como siempre" para no romper proyectos sin el MCP, y nota "NO abuses: para cambios triviales no vale la pena el query" para evitar overhead.

2. **Inyección del snippet en los 8 agentes** (`agents-base/{Alex,Pau,Pol,Jes,Sol,Teo,Jhon,Luz}.md`): cada uno gana una sección `## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp` con el contenido del snippet **copiado** + comment block `<!-- SINCRONIZADO CON: templates/agents/snippets/code-intelligence.md -->`. La inserción va **antes** del `## 🧠 Memory Protocol` (orden: Code Intelligence primero, Memory Protocol segundo) — sigue el patrón de `memory-improvements` ya existente.

3. **Test `tests/code-intelligence.test.sh`**: bash TDD siguiendo el patrón de `tests/memory-protocol.test.sh`. Verifica que el snippet existe y tiene las 5 tools mencionadas + nota "si NO está instalado", que cada uno de los 8 agentes tiene la sección + comment block `SINCRONIZADO CON:.*code-intelligence`. PASS objetivo: ≥ 12.

4. **Paso 5 opt-in en `/skalling-init`** (`command/skalling-init.md`): al final del flujo actual (después del paso 4.5 find-skills), nuevo paso que pregunta al usuario "¿Querés instalar codebase-memory-mcp? (Sí/No)". Si dice Sí: muestra el comando `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash`, pide confirmación explícita, ejecuta, y verifica que el MCP aparece registrado en `~/.config/opencode/opencode.jsonc`. Si verificó OK, recuerda al usuario que el snippet en los agentes ya está activo (porque lo agregamos en tareas 1–3). Si dice No, init sigue normal sin cambios.

5. **Sección informativa en `setup-team-doctor.sh`**: nueva función `check_code_intelligence()` que verifica (a) si el binario está en PATH (`which codebase-memory-mcp`) y (b) si está configurado como MCP server (`grep codebase-memory-mcp ~/.config/opencode/opencode.jsonc`). Reporta como `info` (azul, ℹ) — **no bloquea**, **no es error ni warning**, solo informativo. El doctor no obliga a tenerlo instalado.

6. **Release v0.4.0**: bump `VERSION` de `0.3.0` a `0.4.0`, nueva sección `[0.4.0]` en `CHANGELOG.md` bajo `### Added`, párrafo explicativo en `README.md` describiendo la nueva feature opt-in y cómo activarla. `install-global.sh` **sin cambios** — codebase-memory-mcp no es parte de la instalación global, es opt-in per-project.

## Impact

**Archivos a tocar:**

| # | Path | Acción |
|---|---|---|
| 1 | `templates/agents/snippets/code-intelligence.md` | **crear** — single source (~80 líneas) |
| 2 | `agents-base/Alex.md` | editar — insertar sección antes de `## 🧠 Memory Protocol` |
| 3 | `agents-base/Pol.md` | editar — idem |
| 4 | `agents-base/Jes.md` | editar — idem |
| 5 | `agents-base/Sol.md` | editar — idem |
| 6 | `agents-base/Teo.md` | editar — idem |
| 7 | `agents-base/Jhon.md` | editar — idem |
| 8 | `agents-base/Luz.md` | editar — idem |
| 9 | `agents-base/Pau.md` | editar — idem |
| 10 | `tests/code-intelligence.test.sh` | **crear** — bash test, ~150 líneas |
| 11 | `command/skalling-init.md` | editar — agregar paso 5 opt-in |
| 12 | `setup-team-doctor.sh` | editar — agregar `check_code_intelligence()` |
| 13 | `VERSION` | editar — `0.3.0` → `0.4.0` |
| 14 | `CHANGELOG.md` | editar — nueva sección `[0.4.0]` con `### Added` |
| 15 | `README.md` | editar — párrafo sobre la nueva feature opt-in |

**Archivos NO tocados (confirmación explícita):**

- `install-global.sh` / `install-global.ps1` — codebase-memory-mcp es opt-in per-project, no se instala globalmente.
- `templates/agents/snippets/memory-protocol.md` — el snippet de memoria sigue intacto; Code Intelligence va aparte.
- `templates/handoff.schema.json` — no se modifica schema; los tools del MCP se invocan vía system prompt, no vía handoff JSON.
- `constitution/constitucion.md` — no se agrega regla nueva (Code Intelligence no es regla de gobernanza, es guidance operativa).

## Out of Scope

Explícitamente **NO** incluido en esta iteración:

- **Dependencia dura**: codebase-memory-mcp NO se instala automáticamente con `install-global.sh` ni con `/skalling-init` por default. Rompe la promesa "zero deps" — solo opt-in.
- **Reescritura de agentes**: NO se modifica el comportamiento base de los agentes (decision trees, handoff schemas, role definitions). Solo se **agrega** una sección nueva. Los prompts de cada agente siguen siendo los mismos en todo lo demás.
- **Cloud sync / index remoto**: codebase-memory-mcp indexa localmente; Skalling NO se integra con sync remoto ni index centralizado.
- **Captura pasiva automática**: los agentes NO indexan el codebase en background. El usuario corre `codebase-memory-mcp index` manualmente si quiere.
- **Modificación del handoff schema**: los tools del MCP se invocan desde system prompt del agente, NO se agregan como campos del JSON de handoff.
- **Tests E2E del MCP**: el test verifica que la integración textual (snippet + sección + comment block) existe; NO se prueba que el binario funcione. Probar el binario es responsabilidad del usuario al instalarlo.
- **Documentación de cada tool**: el snippet cubre los 5 principales. Los otros 10 tools del MCP se descubren por documentación externa; no es trabajo de Skalling explicarlos.
- **Auto-update del MCP**: si DeusData publica una nueva versión, Skalling no la baja automáticamente.

## Rollback Plan

- **Reversible**: sí. Toda la integración es aditiva.
- **Feature flag**: implícito — el snippet en system prompt se activa solo si codebase-memory-mcp está instalado; los agentes siguen funcionando con `grep`/`read` sin él.
- **Pasos de rollback** (si se quiere revertir la integración completamente):
  1. Borrar `templates/agents/snippets/code-intelligence.md`.
  2. En cada `agents-base/*.md`, borrar el bloque desde el comment block `SINCRONIZADO CON: templates/agents/snippets/code-intelligence.md` hasta justo antes de `<!-- SINCRONIZADO CON: templates/agents/snippets/memory-protocol.md`.
  3. Borrar `tests/code-intelligence.test.sh`.
  4. Revertir el paso 5 agregado a `command/skalling-init.md`.
  5. Borrar la función `check_code_intelligence()` de `setup-team-doctor.sh`.
  6. Revertir `VERSION` a `0.3.0`, quitar sección `[0.4.0]` de `CHANGELOG.md`, quitar párrafo de `README.md`.
- **Datos afectados**: ninguno. No se crea estado persistente nuevo en el bundle OKF ni en `.opencode/`. Lo único externo es el binario `codebase-memory-mcp` que el usuario instaló (desinstalar es `rm` del binario + entrada en `opencode.jsonc`).

## Success Criteria

- **Funcional**:
  - En un proyecto donde codebase-memory-mcp está instalado, Sol tarda menos tokens para responder "qué afecta la función X" (medible por el tamaño del handoff a Teo: si Sol hace 1 query al MCP en vez de leer 15 archivos, el handoff baja).
  - En un proyecto donde codebase-memory-mcp NO está instalado, los 8 agentes funcionan idéntico a antes (no hay degradación).
- **Mantenibilidad**:
  - `tests/code-intelligence.test.sh` pasa con PASS ≥ 12.
  - Editar el snippet canónico y propagar a las 8 copias es trivial (1 snippet + 8 sed replaces).
- **UX**:
  - Usuario que corre `/skalling-init` ve el opt-in claramente como pregunta Sí/No, no como paso obligatorio.
  - Usuario que corre `setup-team-doctor.sh` ve su estado de codebase-memory-mcp como `info` (azul), no como error ni warning.
- **Test que lo verifica**: `tests/code-intelligence.test.sh` (PASS ≥ 12) + regresión del resto de tests sigue verde.

## Affected Areas

Resumen por área:

- **`.opencode/changes/codebase-memory-mcp/`** (nuevo): proposal + 6 specs (este change).
- **`templates/agents/snippets/`**: nuevo archivo `code-intelligence.md`.
- **`agents-base/`**: 8 archivos editados (todos los agentes ganan la misma sección).
- **`tests/`**: nuevo `code-intelligence.test.sh`.
- **`command/`**: `skalling-init.md` editado.
- **Root**: `setup-team-doctor.sh`, `VERSION`, `CHANGELOG.md`, `README.md`.

## Dependencies

- **Bloqueado por**: ninguno. Es aditivo.
- **Bloquea a**: ninguno directamente, pero futuros cambios que agreguen más tools MCP pueden extender este patrón.
- **Dependencias externas**:
  - `codebase-memory-mcp` (binario externo del usuario, NO se distribuye con Skalling).
  - `curl` (para el install command del paso 5 de init — ya disponible en macOS/Linux).
  - `~/.config/opencode/opencode.jsonc` (existente, ya usado por `install-global.sh`).

## Stakeholders

- **Requester**: usuario (aprobado el 2026-08-04).
- **Reviewers**: Sol (validar que las specs son implementables), Teo (validar que el snippet tiene sentido en implementaciones reales), Luz (validar que el test bash cubre los casos).
- **Approver**: usuario final (vos).
