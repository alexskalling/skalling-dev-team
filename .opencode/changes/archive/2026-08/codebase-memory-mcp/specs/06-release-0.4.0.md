# Spec 06: Release v0.4.0 — docs y versionado

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then (BDD)
> **Cubre**: Punto 6 del scope (release: README, CHANGELOG, VERSION).

---

## Escenario 1: VERSION bumped a 0.4.0

**Given** que la versión actual es `0.3.0`
**When** se prepara el release v0.4.0
**Then** el archivo `VERSION` contiene `__version__ = "0.4.0"`
**Y** el archivo sigue el formato actual (literal Python-style)

---

## Escenario 2: CHANGELOG.md tiene nueva sección [0.4.0]

**Given** que el CHANGELOG actual termina con `[0.3.0] — 2026-08-04`
**When** se agrega la sección de v0.4.0
**Then** aparece una nueva sección `## [0.4.0] — 2026-08-04` **arriba** de `[0.3.0]` (orden cronológico inverso)
**Y** la sección tiene sub-sección `### Added` (consistente con releases previos)
**Y** la sección lista los 6 puntos del scope como bullets con detalles breves
**Y** la sección mantiene el formato Keep a Changelog + SemVer (consistente con el resto del archivo)

---

## Escenario 3: README.md explica la feature opt-in

**Given** que el README actual describe Skalling sin mencionar codebase-memory-mcp
**When** se actualiza para v0.4.0
**Then** aparece un nuevo párrafo (o sub-sección) que describe la integración opt-in de codebase-memory-mcp
**Y** el párrafo menciona:
  - Qué es (inteligencia estructural de código via MCP).
  - Que es **opt-in** (no se instala por default).
  - Cómo activarlo (responder Sí en el paso 5 de `/skalling-init`).
  - Qué pasa si NO se activa (los agentes siguen funcionando con `grep`/`read`).
**Y** el párrafo está en español (consistente con el resto del README)

---

## Escenario 4: `install-global.sh` NO se modifica

**Given** que la promesa de Skalling es "zero deps" en la instalación global
**When** se prepara el release v0.4.0
**Then** el archivo `install-global.sh` queda **intacto** (sin diff)
**Y** codebase-memory-mcp se ofrece **solo** vía `/skalling-init` opt-in (per-project)
**Y** `install-global.ps1` (wrapper Windows) tampoco se modifica

---

## Escenario 5: Links de comparación actualizados al final del CHANGELOG

**Given** que el CHANGELOG tiene links de comparación al final (`[Unreleased]`, `[0.3.0]`, etc.)
**When** se agrega `[0.4.0]`
**Then** aparece una nueva línea `[0.4.0]: https://github.com/tu-usuario/skalling-dev-team/compare/v0.3.0...v0.4.0`
**Y** el link de `[Unreleased]` se actualiza a `compare/v0.4.0...HEAD`

---

## Reglas MUST (obligatorias)

1. `VERSION` **MUST** ser `"0.4.0"`.
2. `CHANGELOG.md` **MUST** tener nueva sección `## [0.4.0] — 2026-08-04` con sub-sección `### Added`.
3. La sección `[0.4.0]` **MUST** documentar los 6 puntos del scope (snippet, inyección, test, opt-in init, doctor, docs).
4. `README.md` **MUST** contener un párrafo (o sub-sección) describiendo la feature opt-in.
5. `install-global.sh` **MUST NOT** ser modificado.
6. `install-global.ps1` **MUST NOT** ser modificado.
7. La nueva sección del CHANGELOG **MUST** estar arriba de `[0.3.0]` (orden cronológico inverso).
8. Los links de comparación al final del CHANGELOG **MUST** incluir `[0.4.0]` y actualizar `[Unreleased]`.

## Reglas SHOULD (recomendadas)

1. El párrafo del README **SHOULD** estar cerca de la sección que explica `/skalling-init` (para que el lector lo encuentre contextualmente).
2. La sección `[0.4.0]` del CHANGELOG **SHOULD** mantener el formato de bullets con `**bold**` para los nombres de features (consistente con releases previos).
3. Si hubo algún fix o cambio menor además de Added, **SHOULD** agregar sub-secciones `### Changed` o `### Fixed` (no obligatorio si no aplica).

## Reglas MAY (opcionales)

1. El CHANGELOG **MAY** agregar una sub-sección `### Security` aunque diga "ningún cambio" (consistente con `[0.3.0]`).
2. El README **MAY** incluir un mini-diagrama ASCII del flujo de opt-in.
3. El release **MAY** tener un blog post o nota de release externa (fuera del scope de Skalling, pero podría linkearse desde el CHANGELOG).

---

## Criterios de Aceptación (resumen)

- [ ] `VERSION` contiene `"0.4.0"`
- [ ] `CHANGELOG.md` tiene sección `## [0.4.0] — 2026-08-04` con `### Added`
- [ ] La sección documenta los 6 puntos del scope
- [ ] La sección está arriba de `[0.3.0]`
- [ ] Links de comparación actualizados (`[0.4.0]` y `[Unreleased]`)
- [ ] `README.md` tiene párrafo explicativo del opt-in
- [ ] `install-global.sh` intacto (diff = 0 líneas)
- [ ] `install-global.ps1` intacto (diff = 0 líneas)
- [ ] No hay referencias a versiones incorrectas en otros archivos (regression check)
- [ ] El formato sigue Keep a Changelog + SemVer

---

## Out of Spec (explícitamente NO incluido)

- Publicación del release en GitHub (eso lo hace el usuario fuera del repo).
- Tag de git `v0.4.0` (lo crea el usuario).
- Notas de release externas (blog, Twitter, etc.).
- Bump de versiones de dependencias internas (Skalling no tiene deps en runtime).
- Cambios al `install-global.sh` para mencionar codebase-memory-mcp (decisión explícita: zero deps).
- Documentación en otros idiomas (solo español).
- Migración de proyectos existentes (no hay schema changes, no se necesita migración).
