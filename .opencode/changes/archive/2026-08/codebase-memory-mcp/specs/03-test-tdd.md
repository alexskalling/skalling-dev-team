# Spec 03: Test bash TDD `tests/code-intelligence.test.sh`

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then (BDD)
> **Cubre**: Punto 3 del scope (test bash siguiendo patrón de `tests/memory-protocol.test.sh`).

---

## Escenario 1: El test existe y es ejecutable

**Given** que la integración del snippet + secciones está implementada
**When** se crea `tests/code-intelligence.test.sh`
**Then** el archivo existe en esa ruta exacta
**Y** tiene shebang `#!/usr/bin/env bash`
**Y** empieza con `set -euo pipefail` (consistente con otros tests)
**Y** es ejecutable (`chmod +x` o al menos corre con `bash tests/code-intelligence.test.sh`)

---

## Escenario 2: El test verifica que el snippet canónico tiene las 5 tools

**Given** que el snippet existe
**When** corre el test
**Then** el test verifica que el archivo `templates/agents/snippets/code-intelligence.md` existe
**Y** el test verifica que el snippet contiene (case-sensitive) los strings: `trace_path`, `get_architecture`, `search_graph`, `find_dead_code`, `detect_changes`
**Y** cada verificación cuenta como 1 PASS

---

## Escenario 3: El test verifica las notas obligatorias del snippet

**Given** que el snippet tiene notas de fallback y anti-abuso
**When** corre el test
**Then** el test verifica (case-insensitive) que el snippet contiene: `si codebase-memory-mcp NO está instalado`
**Y** el test verifica (case-insensitive) que el snippet contiene: `NO abuses`
**Y** el test verifica que el snippet contiene: `SINCRONIZADO CON:`
**Y** cada verificación cuenta como 1 PASS

---

## Escenario 4: El test verifica los 8 agentes con sección + comment block

**Given** que los 8 agentes están actualizados
**When** corre el test
**Then** el test itera sobre `Alex Pol Jes Sol Teo Jhon Luz Pau`
**Y** para cada agente verifica que `agents-base/<nombre>.md` contiene `^## 🔍 Code Intelligence` (regex anchored)
**Y** para cada agente verifica que contiene `SINCRONIZADO CON:.*code-intelligence` (regex)
**Y** cada una de las 16 verificaciones (8 sección + 8 comment block) cuenta como 1 PASS

---

## Escenario 5: Output con colores y exit codes correctos

**Given** que el test corre
**When** un assert pasa o falla
**Then** el PASS se imprime en verde con `✓` (código ANSI `\033[32m`)
**Y** el FAIL se imprime en rojo con `✗` (código ANSI `\033[31m`)
**Y** el resumen final muestra `Results: N passed, M failed`
**Y** si `M > 0` → exit code 1, lista de failed tests al final
**Y** si `M == 0` → exit code 0, imprime `All tests passed.` en verde
**Y** soporta flag `--verbose` (consistente con otros tests)

---

## Escenario 6: PASS total acumulado ≥ 12

**Given** los asserts definidos arriba
**When** todos pasan
**Then** el PASS total es:

| Bloque | Asserts |
|---|---|
| Snippet existe | 1 |
| Snippet tiene las 5 tools | 5 |
| Snippet tiene notas (fallback + anti-abuso + sync) | 3 |
| 8 agentes con sección | 8 |
| 8 agentes con comment block | 8 |
| **Total** | **≥ 25** |

**Y** PASS ≥ 12 es el mínimo aceptado (cualquier PASS menor indica que faltan asserts).

---

## Reglas MUST (obligatorias)

1. El archivo **MUST** existir en `tests/code-intelligence.test.sh`.
2. El archivo **MUST** tener `set -euo pipefail` como segunda línea (después del shebang y comentarios).
3. El archivo **MUST** usar helpers `pass()` / `fail()` / `log()` consistentes con `tests/memory-protocol.test.sh`.
4. El archivo **MUST** iterar sobre los 8 agentes: `Alex Pol Jes Sol Teo Jhon Luz Pau` — no se saltea ninguno.
5. El archivo **MUST** verificar las 5 tools principales en el snippet.
6. El archivo **MUST** verificar las notas fallback + anti-abuso + sincronización.
7. El archivo **MUST** terminar con exit code 1 si hay failures, 0 si todos pasan.
8. PASS total **MUST** ser ≥ 12.

## Reglas SHOULD (recomendadas)

1. El archivo **SHOULD** estar estructurado en bloques `test_<nombre>()` llamados desde un `main` o desde el final del script (como `memory-protocol.test.sh`).
2. El archivo **SHOULD** tener un banner inicial identificable: `"  Code Intelligence Tests (v0.4.0 — codebase-memory-mcp)"`.
3. Las verificaciones **SHOULD** usar regex anchored (`^## 🔍 Code Intelligence`) en lugar de substring matching, para evitar falsos positivos.
4. El archivo **SHOULD** tener ~150 líneas (±50).

## Reglas MAY (opcionales)

1. El archivo **MAY** agregar un test que verifica que Code Intelligence aparece **antes** de Memory Protocol en cada agente (grep + awk para número de línea).
2. El archivo **MAY** agregar un test de regresión que verifica que el snippet NO fue agregado al `.gitignore` ni movido de carpeta.

---

## Criterios de Aceptación (resumen)

- [ ] `tests/code-intelligence.test.sh` existe y es ejecutable
- [ ] `bash tests/code-intelligence.test.sh` corre sin errores de sintaxis
- [ ] Verifica que el snippet existe
- [ ] Verifica las 5 tools en el snippet
- [ ] Verifica las notas (fallback + anti-abuso + sync)
- [ ] Verifica sección `## 🔍 Code Intelligence` en los 8 agentes
- [ ] Verifica comment block `SINCRONIZADO CON:.*code-intelligence` en los 8 agentes
- [ ] PASS ≥ 12 con implementación correcta
- [ ] PASS = 0 con implementación faltante (cada assert falla si no se cumple)
- [ ] Exit code 0 si todos pasan, 1 si hay failures
- [ ] Output con colores verde/rojo
- [ ] El resto de tests del repo (`memory-protocol`, `setup`, etc.) sigue verde (no hay regresión)

---

## Out of Spec (explícitamente NO incluido)

- Tests E2E que ejecutan el binario codebase-memory-mcp (no es responsabilidad del test de Skalling).
- Tests de performance del snippet (tamaño, líneas, etc.) — solo presencia/contenido.
- Tests de los otros 10 tools del MCP — el snippet documenta solo los 5 principales.
- Tests del comando de instalación (`curl ... | bash`) — eso se prueba manualmente o en otro change.
- Mocking del MCP — Skalling no testea integración con terceros.
