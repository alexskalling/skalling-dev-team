# Design: Integración opt-in de `codebase-memory-mcp`

> **Status**: Draft
> **Author**: Sol
> **Created**: 2026-08-04
> **Source**: `proposal.md` + `specs/01..06-*.md` (Pol)
> **Scope**: Skalling v0.4.0

---

## 0. Visión de conjunto

Este change integra `codebase-memory-mcp` como **feature opt-in** en Skalling. Resuelve un problema concreto: Sol y Teo gastan 10–30 archivos leídos por handoff para entender blast radius, lo que infla contexto y retrasa decisiones. La integración agrega un **snippet canónico** en los 8 agentes + un **sniff en el doctor** + un **opt-in en `/skalling-init`**, sin romper la promesa "zero deps" del instalador global.

**Principio rector**: si `codebase-memory-mcp` no está instalado, los 8 agentes funcionan **idéntico a antes** (siguen con `grep`/`read`). El snippet es **guía, no assert rígido**.

---

## 1. Decisiones técnicas por spec

### 1.1 — Spec 01: Snippet canónico `templates/agents/snippets/code-intelligence.md`

**Decisiones concretas:**

| Aspecto | Decisión | Razón |
|---|---|---|
| **Path** | `templates/agents/snippets/code-intelligence.md` | Mismo dir que `memory-protocol.md` (convenciones del repo). |
| **Heading raíz** | `# 🔍 Code Intelligence (snippet canónico)` | Mismo emoji + formato que `memory-protocol.md`. |
| **Idioma** | Español | Consistente con el resto de Skalling. |
| **Tamaño** | ~80 líneas (±20) | Guía concisa, no enciclopedia. Spec 01 SHOULDs. |
| **Estructura interna** | 5 sub-secciones `##` (una por tool) + bloque de notas (fallback + anti-abuso) + bloque de sync | Orden canónico: tools → notas → sync. |
| **Nota de single source** | Primera línea después del heading `#`: `> **Este snippet es single source. ...` | Idéntico al patrón de `memory-protocol.md` (test lo verifica). |
| **Bloque de sync** | Final del archivo, comment block HTML: `<!-- SINCRONIZADO CON: ... -->` | Mismo patrón que `memory-protocol.md` (los agentes también lo verifican). |
| **Tool names** | Strings literales: `mcp__codebase-memory-mcp__trace_path` (formato MCP esperado por opencode) | Evita ambigüedad; opencode invoca tools con prefijo `mcp__<server>__<tool>`. |
| **Heurística por tool** | Cada sub-sección tiene: **(a)** pregunta natural ejemplo, **(b)** cuándo NO usar, **(c)** heurística de 1–2 archivos | Spec 01 MUST #2 + SHOULD #1. |
| **Nota fallback** | Bloque aparte "Si `codebase-memory-mcp` NO está instalado" con texto literal: `si codebase-memory-mcp NO está instalado` | Spec 01 MUST #3; test verifica case-insensitive. |
| **Nota anti-abuso** | Bloque aparte "NO abuses" con texto literal: `NO abuses` + heurística "1–2 archivos → grep gana" | Spec 01 MUST #4; test verifica case-insensitive. |
| **Referencia al index** | Mención breve: `El grafo se construye con codebase-memory-mcp index` (responsabilidad del usuario) | Spec 01 SHOULD #2. |

**Orden de implementación:**

1. **Primero**: snippet canónico (todo lo demás depende de él). Spec 06 (release) NO lo necesita.
2. **Depende de**: nada.
3. **Bloquea**: Spec 02 (la inyección copia su contenido) + Spec 03 (el test lo verifica).

**Riesgos y mitigaciones:**

| Riesgo | Mitigación |
|---|---|
| Snippet demasiado largo → infla system prompt | Tope duro de ~80 líneas según spec 01 SHOULD #3. Si se va a más, abrir issue nuevo. |
| Tools mal documentados → agente los invoca mal | Cada sub-sección tiene ejemplo natural + heurística de cuándo NO usar. |
| Agentes en proyectos sin MCP rompen | Nota fallback explícita + test verifica presencia del string. |
| Snippet en inglés rompe consistencia | Spec 01 MUST #6. Idioma verificado en code review por Jhon. |

---

### 1.2 — Spec 02: Inyección del snippet en los 8 agentes

**Decisiones concretas:**

| Aspecto | Decisión | Razón |
|---|---|---|
| **Agentes a tocar** | `Alex.md`, `Pol.md`, `Jes.md`, `Sol.md`, `Teo.md`, `Jhon.md`, `Luz.md`, `Pau.md` (8 total) | Spec 02 MUST #5. |
| **Heading de la sección** | `## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp` (sin numeral `cuándo` en otros agentes para evitar ruido) | Spec 02 Escenario 1. |
| **Posición** | **Antes** de `## 🧠 Memory Protocol` (orden: Code Intelligence → Memory Protocol) | Spec 02 Escenario 4. |
| **Separador** | `---` (horizontal rule) entre ambas secciones | Spec 02 SHOULD #2 (consistente con `memory-improvements`). |
| **Comment block** | `<!-- SINCRONIZADO CON: templates/agents/snippets/code-intelligence.md -->` **inmediatamente antes** del heading `## 🔍 Code Intelligence` | Spec 02 Escenario 3. |
| **Contenido** | **Copia literal** del snippet. Sub-heading `## 🔍 Code Intelligence` (h2) en agente vs `# 🔍 Code Intelligence` (h1) en snippet. Sub-sub-headings `###` en agente vs `##` en snippet (preservar jerarquía). | Spec 02 Escenario 2. |
| **Notas MAY por agente** | Permitidas solo al final si el rol lo amerita (ej: "Sol usá `get_architecture` cuando planifiques features nuevas"). Excepción documentada, no la norma. | Spec 02 MAY #1. |
| **Lo que NO se toca** | Frontmatter (líneas 1–13), reglas de oro, personalidad, ciclo, decisión tree. Inserción **aditiva**. | Spec 02 MUST #6. |
| **Frontmatter** | Sin cambios en `permission:` (los tools del MCP se invocan si el MCP está configurado globalmente; no requiere permisos nuevos). | Spec 02 Escenario 5. |

**Patrón de inserción en cada agente** (exacto, copy-paste):

```markdown
---

<!-- SINCRONIZADO CON: templates/agents/snippets/code-intelligence.md. Si editás esto, sincronizá ambos lados. -->

## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp

> **Single source**: `templates/agents/snippets/code-intelligence.md`. Si modificás este bloque, propagá el cambio al snippet canónico y a las otras copias en `agents-base/*.md`.

---

[CONTENIDO DEL SNIPPET, con sub-sub-headings `###` en lugar de `##`]

---

(seguir con el bloque existente de `## 🧠 Memory Protocol`)
```

**Orden de implementación:**

1. **Depende de**: Spec 01 (snippet canónico debe existir).
2. **Bloquea**: Spec 03 (test verifica ambas cosas: snippet + 8 agentes).
3. **Operación atómica**: las 8 inserciones van en **una sola tarea** de Teo (no se commitea un agente a la vez). Razón: el test verifica los 8 + el snippet en un solo assert; si van por separado, los asserts intermedios fallarían.

**Riesgos y mitigaciones:**

| Riesgo | Mitigación |
|---|---|
| Drift entre snippet y 8 copias | Comment block `SINCRONIZADO CON` + nota de single source en cada copia. Test verifica presencia del comment. |
| Romper frontmatter al insertar | Inserción **antes** del `<!-- SINCRONIZADO CON: ...memory-protocol` existente, no antes de frontmatter. Jhon valida frontmatter intacto por diff. |
| Modificar personalidad / ciclo del agente | Diff de cada agente **solo** debe mostrar líneas nuevas (Code Intelligence section), no modificaciones a líneas existentes. |
| Reordenar memoria correctamente | Inserción **antes** de `## 🧠 Memory Protocol`, NO **después** (test verifica orden con grep por número de línea en Spec 03 MAY #1). |

---

### 1.3 — Spec 03: Test bash TDD `tests/code-intelligence.test.sh`

**Decisiones concretas:**

| Aspecto | Decisión | Razón |
|---|---|---|
| **Path** | `tests/code-intelligence.test.sh` | Consistente con `memory-protocol.test.sh`. |
| **Shebang + strict mode** | `#!/usr/bin/env bash` + `set -euo pipefail` (línea 2 tras comentarios) | Spec 03 MUST #2; patrón de `memory-protocol.test.sh`. |
| **Helpers** | `pass()`, `fail()`, `log()`, `assert_file_exists()`, `assert_file_contains()` (copiados de `memory-protocol.test.sh`) | Spec 03 MUST #3. |
| **Paleta** | `c_green='\033[32m'`, `c_red='\033[31m'`, `c_reset='\033[0m'` | Idéntico a `memory-protocol.test.sh`. |
| **Exit code** | 0 si todo PASS, 1 si hay FAIL | Spec 03 MUST #7. |
| **Flag** | `--verbose` (consistente con otros tests) | Spec 03 SHOULD #1. |
| **Banner** | `  Code Intelligence Tests (v0.4.0 — codebase-memory-mcp)` | Spec 03 SHOULD #2. |
| **Estructura** | Funciones `test_<nombre>()` llamadas desde el final del script (como `memory-protocol.test.sh`) | Spec 03 SHOULD #1. |
| **Tamaño** | ~150 líneas (±50) | Spec 03 SHOULD #4. |
| **Asserts definidos** | 25+ asserts (5 snippet + 2 notas + 1 sync + 8 secciones + 8 comment blocks + 1 orden) | Spec 03 Escenario 6. |

**Asserts concretos (regex / strings exactos):**

```bash
# ──────── TEST 1: Snippet existe ────────
assert_file_exists "$SNIPPET" "templates/agents/snippets/code-intelligence.md existe"

# ──────── TEST 2: 5 tools en snippet (case-sensitive) ────────
for tool in trace_path get_architecture search_graph find_dead_code detect_changes; do
    assert_file_contains "$SNIPPET" "$tool" "Snippet contiene tool $tool"
done

# ──────── TEST 3: Notas obligatorias (case-insensitive) ────────
# Fallback:         grep -qi "si codebase-memory-mcp NO está instalado" snippet
# Anti-abuso:       grep -qi "NO abuses" snippet
# Sincronización:   grep -q  "SINCRONIZADO CON:" snippet

# ──────── TEST 4: 8 agentes con sección (anchored regex) ────────
for agent in Alex Pol Jes Sol Teo Jhon Luz Pau; do
    grep -qE "^## 🔍 Code Intelligence" "$AGENTS_DIR/${agent}.md"
done

# ──────── TEST 5: 8 agentes con comment block ────────
for agent in Alex Pol Jes Sol Teo Jhon Luz Pau; do
    grep -qE "SINCRONIZADO CON:.*code-intelligence" "$AGENTS_DIR/${agent}.md"
done

# ──────── TEST 6 (opcional MAY): Code Intelligence < Memory Protocol (orden) ────────
# Para cada agente: awk '/^## 🔍 Code Intelligence/{n_ci=NR} /^## 🧠 Memory Protocol/{n_mp=NR} END{exit !(n_ci<n_mp)}'
```

**Mapeo a asserts contables:**

| Bloque | Asserts |
|---|---|
| Snippet existe | 1 |
| Snippet contiene 5 tools | 5 |
| Snippet nota fallback | 1 |
| Snippet nota anti-abuso | 1 |
| Snippet nota sync | 1 |
| 8 agentes con `## 🔍 Code Intelligence` | 8 |
| 8 agentes con comment block `code-intelligence` | 8 |
| **Subtotal** | **25** |
| (Opcional) 8 agentes con orden correcto CI < MP | 8 |
| **Total con MAY** | **33** |

PASS objetivo: **≥ 25** (cubre el mínimo de **12** del spec 03 MUST #8 con margen).

**Orden de implementación:**

1. **Depende de**: Spec 01 (snippet) + Spec 02 (8 agentes).
2. **Bloquea**: Spec 06 (regresión completa).
3. **TDD puro**: el test se escribe **antes** del snippet? **No.** En este caso, el test se escribe **después** del snippet + agentes porque su único propósito es validar la implementación, no guiar el diseño. El "TDD" aquí es regresión, no red-green-refactor. Doc TDD: implementar feature → escribir test → correr test → PASS.

**Riesgos y mitigaciones:**

| Riesgo | Mitigación |
|---|---|
| Regex anchored falsos positivos (ej: agentes sin Code Intelligence pero con "Code Intelligence" en otra sección) | Regex anchored `^## 🔍 Code Intelligence`previene matches en medio de párrafos. |
| `set -e` + `grep -q` que retorna 1 cuando no hay match | Helper `assert_file_contains` envuelve con `if ... fi` para evitar `-e` early exit. |
| Test pasa con snippet-pero-sin-agentes o viceversa | Ambos asserts (snippet + 8 agentes) son independientes; test reporta PASS/FAIL por separado. |
| Drift de test → pierde valor | Test verifica SOLO presencia textual (no semántica del snippet). Si el snippet cambia, el test sigue pasando siempre que mantenga los 5 nombres de tools + 2 notas + comment block. |

---

### 1.4 — Spec 04: Paso 5 opt-in en `/skalling-init`

**Decisiones concretas:**

| Aspecto | Decisión | Razón |
|---|---|---|
| **Posición** | Después de **paso 4.6** (Doctor) y **antes** del **paso 5 actual** (resumen final). Numerar como **paso 4.7** (intercalar), o renumerar 5→6. **Default propuesto**: insertar como **paso 4.7** y renumerar el resumen actual a **paso 5**. | Spec 04 Escenario 1. |
| **Texto de la pregunta** | `¿Querés instalar codebase-memory-mcp? (inteligencia estructural de código via MCP, opt-in)` | Spec 04 Escenario 1 + brief explicativo. |
| **Formato A/B/C** | `A) Sí, instalar y configurar`, `B) No, saltar` | Spec 04 SHOULD #1. |
| **Comando a ejecutar** | `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh \| bash` | Spec 04 MUST #4 (literal). |
| **Confirmación previa** | Mostrar el comando al usuario con `¿Ejecuto este comando? (Sí/No)` antes de correrlo | Spec 04 Escenario 2. |
| **Verificación post-install** | `grep -q codebase-memory-mcp ~/.config/opencode/opencode.jsonc` | Spec 04 Escenario 3. |
| **Mensaje OK** | `codebase-memory-mcp registrado como MCP server` | Spec 04 Escenario 3. |
| **Mensaje FAIL** | `El binario se instaló pero no aparece en opencode.jsonc — revisá manualmente` (warning, no error) | Spec 04 Escenario 3. |
| **Línea recordatoria en resumen** | Solo si verificó OK: `✓ Code Intelligence snippet activo en los 8 agentes (ya estaba habilitado por la integración v0.4.0)` | Spec 04 Escenario 4. |
| **Comportamiento si No** | Init sigue normal; resumen final NO menciona Code Intelligence | Spec 04 Escenario 5. |
| **Tiempo total del paso** | ≤ 30 segundos si el usuario dice No | Spec 04 Escenario 6. |
| **Edge case: binario ya instalado** | `which codebase-memory-mcp` retorna 0 → saltar la pregunta y reportar "Ya tenés codebase-memory-mcp instalado, paso al resumen." | Spec 04 MAY #1 (default propuesto). |
| **Edge case: error de red** | Si `curl` falla → warning "No pude instalar codebase-memory-mcp. Reintentá manualmente desde https://github.com/DeusData/codebase-memory-mcp". | Spec 04 Out of Spec: "Manejo de errores de red durante `curl`" (decisión a confirmar: warning vs error). |

**Snippet de markdown para el init (template exacto):**

```markdown
### 4.7 — Code Intelligence (opt-in)

`codebase-memory-mcp` ([DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)) es un servidor MCP que indexa codebases en un grafo de funciones y expone tools como `trace_path`, `get_architecture`, `search_graph`. Permite que Sol y Teo entiendan blast radius con 1 query en vez de leer 20 archivos.

**Importante**: es **opt-in, no dependencia**. Si no lo instalás, los agentes funcionan idéntico a antes (siguen con `grep`/`read`).

Primero verifico si ya está instalado:

```bash
command -v codebase-memory-mcp
```

**Si ya está**: reporto `Ya tenés codebase-memory-mcp instalado en <path>. La integración con Skalling ya está activa.` y salto al resumen.

**Si NO está**:

```
¿Querés instalar codebase-memory-mcp? (opcional, podés hacerlo después)

A) Sí, instalalo
B) No, saltar este paso
```

**Si A)**: muestro el comando y pido segunda confirmación:

```
Voy a ejecutar:
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash

¿Lo ejecuto? (Sí/No)
```

Solo si confirma, ejecuto. Después verifico:

```bash
grep -q codebase-memory-mcp ~/.config/opencode/opencode.jsonc && echo "OK: registrado" || echo "WARN: no aparece en opencode.jsonc"
```

Si OK → agrego al resumen final: `✓ Code Intelligence snippet activo en los 8 agentes (ya estaba habilitado por la integración v0.4.0)`.

**Si B)**: el init sigue normal. El resumen final **NO** menciona Code Intelligence.
```

**Orden de implementación:**

1. **Depende de**: nada (el init es independiente del snippet en agents).
2. **Bloquea**: nada (no es crítico para el release, se puede hacer en paralelo).
3. **Testabilidad**: el init es conversacional, no hay test automático. **Jhon lo verifica manualmente** corriendo `/skalling-init` en un proyecto de prueba y validando las 3 ramas (Sí/No/ya-instalado).

**Riesgos y mitigaciones:**

| Riesgo | Mitigación |
|---|---|
| Cambio de numeración rompe referencias en otros docs | Renumerar 5→6 de manera consistente (verificar que no haya otra referencia a "paso 5"). |
| `curl \| bash` puede fallar por red | Warning explícito + URL del repo para retry manual. |
| Usuario diste con `Sí` por error | Doble confirmación (Sí/No opt-in + Sí/No ejecución). |
| Binario instalado pero config no | Mensaje claro con instrucción: "revisá manualmente o reintentá el install". |
| El snippet en los agentes está activo pero el usuario eligió No → confusión | Nota explícita en el init: "El snippet... ya está en los 8 agentes (es parte de Skalling) pero el opt-in activa el binario". |

---

### 1.5 — Spec 05: Check informativo en `setup-team-doctor.sh`

**Decisiones concretas:**

| Aspecto | Decisión | Razón |
|---|---|---|
| **Función** | `check_code_intelligence()` | Spec 05 Escenario 1. |
| **Posición en `main()`** | Después de `check_project_install` (justo antes del `━━━ Resumen ━━━`) | Spec 05 Escenario 1. |
| **Sección** | `section "Code Intelligence (opt-in)"` (prefijo identificable) | Spec 05 MUST #7. |
| **Helper usado** | **Siempre** `info()` (azul, ℹ). **Nunca** `warn()` ni `err()`. | Spec 05 MUST #3. |
| **No incrementa contadores** | `WARN_COUNT` y `ERROR_COUNT` intactos | Spec 05 MUST #6. |
| **Comando 1: binario en PATH** | `command -v codebase-memory-mcp` | Spec 05 MUST #4 (preferido sobre `which` por portabilidad POSIX). |
| **Comando 2: MCP en config** | `grep -q codebase-memory-mcp ~/.config/opencode/opencode.jsonc` | Spec 05 MUST #5. **Con guard**: `[[ -f ~/.config/opencode/opencode.jsonc ]]` antes del grep (sino crashea con `set -e`). |
| **Combinaciones (4 estados)** | Ver tabla Spec 05 Escenario 5. | Spec 05 MUST. |
| **Exit code** | `--strict` no rompe por Code Intelligence (porque no incrementa `WARN_COUNT`) | Spec 05 Escenario 6. |

**Snippet de bash (template exacto):**

```bash
check_code_intelligence() {
    section "Code Intelligence (opt-in)"

    # Importante: este check es SOLO informativo. No usamos warn() ni err()
    # porque codebase-memory-mcp es opt-in (no es dependencia dura).
    # El snippet en los agentes ya está activo independientemente.

    local bin_path=""
    if bin_path="$(command -v codebase-memory-mcp 2>/dev/null)"; then
        info "Binario codebase-memory-mcp instalado en PATH: $bin_path"
    else
        info "codebase-memory-mcp no instalado (opt-in, no requerido)"
    fi

    local config="$HOME/.config/opencode/opencode.jsonc"
    if [[ -f "$config" ]] && grep -q codebase-memory-mcp "$config" 2>/dev/null; then
        info "Registrado como MCP server en opencode.jsonc"
    else
        info "No registrado en opencode.jsonc"
    fi

    # Combinación: si binario instalado pero no en config, sugerencia
    if [[ -n "$bin_path" ]] && { [[ ! -f "$config" ]] || ! grep -q codebase-memory-mcp "$config" 2>/dev/null; }; then
        info "Sugerencia: binario presente pero falta registrarlo. Reintentá /skalling-init o editá opencode.jsonc manualmente."
    fi
}
```

Y agregar en `main()`, **después de** `check_project_install`:

```bash
check_code_intelligence
```

**Orden de implementación:**

1. **Depende de**: nada (el doctor es independiente).
2. **Bloquea**: nada.
3. **Testabilidad**: el doctor es bash script. **Jhon lo verifica manualmente** corriendo:
   - `bash setup-team-doctor.sh` → ver que la sección aparece con `ℹ` azul.
   - `bash setup-team-doctor.sh --strict` → exit code 0 si no hay otros errores.
   - Borrar el binario (`mv codebase-memory-mcp /tmp/`) → ver mensaje "no instalado".
   - Borrar la línea de opencode.jsonc → ver mensaje "no registrado".

**Riesgos y mitigaciones:**

| Riesgo | Mitigación |
|---|---|
| `set -e` crashea si `~/.config/opencode/opencode.jsonc` no existe | Guard `[[ -f "$config" ]]` antes del grep. |
| `command -v` tiene side effects raros | Capturar output en variable local + `2>/dev/null`. |
| Sección rompe output ordenado del doctor | Posicionarla **después** de `check_project_install` (que ya imprime secciones). |
| Output demasiado verbose (2 líneas siempre) | Solo 2-3 líneas (info por check + sugerencia condicional). |

---

### 1.6 — Spec 06: Release v0.4.0

**Decisiones concretas:**

| Aspecto | Decisión | Razón |
|---|---|---|
| **`VERSION`** | `__version__ = "0.4.0"` (literal Python-style, mantener formato) | Spec 06 Escenario 1. |
| **`CHANGELOG.md`** | Nueva sección `## [0.4.0] — 2026-08-04` arriba de `[0.3.0]`, con `### Added` listando los 6 puntos | Spec 06 Escenario 2. |
| **Sub-secciones CHANGELOG** | `### Added` y (opcional) `### Changed` y `### Security` (siguiendo el patrón de [0.3.0]) | Spec 06 MAY #1. |
| **Links de comparación** | Agregar `[0.4.0]: https://github.com/tu-usuario/skalling-dev-team/compare/v0.3.0...v0.4.0` y actualizar `[Unreleased]` a `compare/v0.4.0...HEAD` | Spec 06 Escenario 5. |
| **`README.md`** | Nuevo párrafo o sub-sección describiendo el opt-in. **Default propuesto**: insertar después de la sección "Instalación" y antes de "Primeros pasos" (contexto de "/skalling-init" cerca). | Spec 06 Escenario 3. |
| **Contenido del párrafo README** | 4 puntos obligatorios: (a) qué es, (b) opt-in, (c) cómo activarlo, (d) qué pasa si no | Spec 06 Escenario 3. |
| **`install-global.sh` / `.ps1`** | **NO se tocan** | Spec 06 MUST #5/#6 (promesa "zero deps"). |
| **Tag de git** | NO se crea (lo crea el usuario fuera del repo) | Spec 06 Out of Spec. |
| **`SKALLING_VERSION` en `setup-team-doctor.sh`** | Default propuesto: bumpear de `"0.1.0"` (línea 29) a `"0.4.0"`. **Decisión a confirmar**. | Spec 06 Out of Spec no lo menciona, pero por consistencia. |

**Snippet de CHANGELOG (template exacto):**

```markdown
## [0.4.0] — 2026-08-04

### Added
- **Code Intelligence (opt-in)**: integración con [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp) como feature opt-in (no dependencia dura). Los 8 agentes ganan una sección `## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp` con snippet canónico en `templates/agents/snippets/code-intelligence.md` + comment block `SINCRONIZADO CON` para mantenimiento.
- **Snippet canonico de 5 tools MCP**: `trace_path` (blast radius), `get_architecture` (overview), `search_graph` (búsqueda por nombre), `find_dead_code` (código muerto), `detect_changes` (análisis de PR). Incluye nota fallback "si NO está instalado, seguí con grep/read" y nota anti-abuso "NO abuses para cambios triviales".
- **Test bash `tests/code-intelligence.test.sh`**: 25+ asserts que validan snippet + 8 agentes (PASS objetivo ≥ 12). Patrón consistente con `tests/memory-protocol.test.sh`.
- **Paso 4.7 opt-in en `/skalling-init`**: nueva pregunta Sí/No al final del init. Si Sí, ejecuta `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash` con doble confirmación y verifica registro en `~/.config/opencode/opencode.jsonc`.
- **Sección informativa en `setup-team-doctor.sh`**: nueva función `check_code_intelligence()` reporta estado del binario + config MCP. Siempre `info()` (azul, ℹ), nunca warning/error. No afecta `--strict`.

### Changed
- `agents-base/*.md` (8 archivos): cada uno gana sección Code Intelligence antes de `## 🧠 Memory Protocol`. Frontmatter y reglas base intactos.
- `setup-team-doctor.sh`: nueva sección en output (no afecta `OK_COUNT`/`WARN_COUNT`/`ERROR_COUNT`).

### Security
- Ningún cambio de superficie de seguridad. `codebase-memory-mcp` se instala via `curl | bash` solo con opt-in explícito del usuario.
```

**Snippet de README (template exacto, ~150 palabras):**

```markdown
### Code Intelligence (opt-in, v0.4.0+)

Desde v0.4.0, Skalling se integra de forma **opt-in** con [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp), un servidor MCP que indexa codebases en un grafo de funciones. Esto permite que Sol y Teo entiendan blast radius y arquitectura con **1 query** en vez de leer 20 archivos.

**No es una dependencia**: si no lo activás, los agentes funcionan idéntico a antes (siguen con `grep`/`read`).

**Cómo activarlo**:
1. Corré `/skalling-init` en tu proyecto.
2. Al final del flujo, respondé **Sí** cuando te pregunte si querés instalar `codebase-memory-mcp`.
3. El init confirma el comando, lo ejecuta, y verifica que quedó registrado en `~/.config/opencode/opencode.jsonc`.

**Si NO lo activás**: el snippet `## 🔍 Code Intelligence` sigue en los 8 agentes pero los tools del MCP no están disponibles. Los agentes siguen funcionando con `grep`/`read` como siempre.

**Cómo verificar**: `bash setup-team-doctor.sh` reporta el estado del MCP en la sección "Code Intelligence (opt-in)".
```

**Posición en README**: insertar entre `## Instalación` (línea 39) y `## Primeros pasos` (línea 59). Concretamente, después de la línea 56 (`Requiere Windows 10+ y Git Bash o WSL2.`) y antes de `## Primeros pasos`.

**Orden de implementación:**

1. **Depende de**: TODOS los demás specs (el release documenta todo lo agregado).
2. **Bloquea**: regresión + auditoría + archivo.
3. **Operación atómica**: VERSION + CHANGELOG + README van en **una sola tarea** de Teo (todos son ediciones de release, no se commitea hasta que el resto esté verde).

**Riesgos y mitigaciones:**

| Riesgo | Mitigación |
|---|---|
| `SKALLING_VERSION` hardcodeado en `setup-team-doctor.sh` (línea 29) queda en `"0.1.0"` | Bumpear a `"0.4.0"` en la misma tarea. **Decisión a confirmar** (no es MUST del spec). |
| Links de comparación apuntan a repo incorrecto | Default propuesto: `https://github.com/alexskalling/skalling-dev-team` (mismo path usado en la sección Instalación del README). **Decisión a confirmar**. |
| Date del CHANGELOG incorrecta | Usar `2026-08-04` (hoy, consistente con [0.3.0]). |
| Regresión en tests por cambios en setup-team-doctor.sh | Regresión completa en Fase 3 (correr `bash setup-team-doctor.sh --strict`). |
| `install-global.sh` queda con versión vieja | Spec 06 MUST #5: NO se toca. Confirmar con `git diff install-global.sh` debe ser vacío. |

---

## 2. Orden de implementación consolidado

```
FASE 1 — Snippet + inyección + test (orden estricto)
  1.1  Crear snippet canónico (Spec 01)              — sin deps
  1.2  Inyectar sección en 8 agentes (Spec 02)       — depende de 1.1
  1.3  Crear test bash (Spec 03)                     — depende de 1.1 y 1.2
  1.4  Correr test → debe pasar (PASS ≥ 25)          — gate de Fase 1

FASE 2 — Init opt-in + doctor (orden flexible, paralelo)
  2.1  Editar paso 4.7 en skalling-init (Spec 04)    — sin deps
  2.2  Agregar check_code_intelligence() (Spec 05)   — sin deps
  2.3  Verificar manualmente ambos                   — gate de Fase 2

FASE 3 — Release (orden estricto)
  3.1  Bump VERSION + CHANGELOG + README (Spec 06)   — depende de 1.x y 2.x
  3.2  Regresión completa (todos los tests)          — gate de Fase 3
  3.3  Luz audita el plan completo                   — gate final
  3.4  Pau archiva el change                         — done
```

**Razón de la secuenciación**:

- **Fase 1 antes que Fase 2**: el snippet + agentes es la feature. Init + doctor la rodean. Si Fase 1 falla, no tiene sentido tocar Fase 2.
- **Fase 2 en paralelo interno**: init y doctor son independientes (uno toca `command/`, otro toca `setup-team-doctor.sh`). Teo puede hacerlos en cualquier orden.
- **Fase 3 al final**: el release documenta todo. Se hace **último** para no tener que reversionar el CHANGELOG si Fase 1 o Fase 2 cambia.

---

## 3. Riesgos transversales y mitigaciones

| Riesgo | Mitigación |
|---|---|
| **Drift entre snippet y 8 copias** | Comment block `SINCRONIZADO CON` + nota de single source en cada copia. Test verifica presencia del comment block. Si el snippet cambia, las 8 copias deben actualizarse en el mismo PR (es explícito en la nota). |
| **Test pasa con implementación parcial** | Test tiene 25 asserts (no 12). Quien implementa a medias, ve 13 FAIL rojos. |
| **Cambio de numeración en init rompe referencias** | Buscar `paso 5` en todo el repo (incluyendo el propio init) antes de renumerar. Si hay alguna referencia, ajustarla. |
| **`curl \| bash` ejecuta sin ser realmente opt-in** | Doble confirmación (opt-in Sí/No + ejecución Sí/No). Comando se imprime explícito antes de correr. |
| **Doctor rompe `--strict` por Code Intelligence** | Helpers correctos (`info()` no incrementa `WARN_COUNT`). |
| **Release bumpea `SKALLING_VERSION` en setup-team-doctor.sh, no en `VERSION`** | Bumpear **ambos** en la misma tarea. |
| **Regresión en tests existentes** | Regresión completa en Fase 3 (`bash tests/setup.test.sh`, `bash tests/memory-protocol.test.sh`, `bash tests/code-intelligence.test.sh`). |
| **CHANGELOG con links rotos** | Default propuesto: `alexskalling/skalling-dev-team` (path del README). Verificar antes de merge. |
| **README en español pero title del snippet en inglés** | Aceptable: el heading es `# 🔍 Code Intelligence (snippet canónico)` — está en español, solo "Code Intelligence" es nombre del feature. |
| **`SKALLING_VERSION` vs `VERSION`** | Dos archivos. `VERSION` (raíz) para tools de release. `SKALLING_VERSION` (en setup-team-doctor.sh) para el banner del doctor. Bumpear ambos. |

---

## 4. Estrategia de adopción

**Decisión: "Todo de una vez, en un solo release"**.

**Por qué no gradual**:

- El snippet es **puramente aditivo** (no cambia comportamiento de agentes sin el MCP).
- El test es **puramente aditivo** (no interfiere con otros tests).
- El init y el doctor son **opt-in / info-only** (no rompen flujos existentes).
- Las 6 specs son **interdependientes**: el snippet se inyecta en los 8 agentes ATOMICAMENTE (no se commitea un agente a la vez). El release documenta los 6 juntos.

**Por qué no experimental / flag**:

- No hay flag necesario: el snippet es opt-in **por ausencia del binario** (si no está `codebase-memory-mcp`, los tools no existen y el snippet no se invoca).
- El opt-in en init ya es el "flag" de adopción.

**Adopción esperada**:

1. **Día 0 (release)**: devs que corren `/skalling-init` en proyectos nuevos ven el opt-in y eligen Sí/No.
2. **Día 1-N**: devs que ya tienen Skalling instalado reciben el update via `install-global.sh` + bump de versión. Los snippets se propagan a sus 8 agentes automáticamente.
3. **Ongoing**: devs que quieran activar el MCP en un proyecto existente corren `/skalling-init` (paso 4.7) o instalan manualmente.

**Métricas de éxito** (no se instrumentan en este release, son para validación manual):

- % de devs que eligen Sí en el opt-in (estimación: < 20% en release, creciendo orgánicamente).
- Reducción de tokens en handoffs Sol → Teo (medible por tamaño del JSON de handoff, si Sol hace 1 query al MCP en vez de leer 15 archivos).
- Tiempo de respuesta de Sol/Teo en proyectos con codebase-memory-mcp instalado (subjetivo, no automatizable).

---

## 5. Decisiones técnicas a confirmar

Las siguientes decisiones tienen **default propuesto** y NO bloquean el inicio de Fase 1. Se confirman durante la ejecución o en revisión de Jhon:

| # | Decisión | Default propuesto | Bloquea |
|---|---|---|---|
| D1 | Numeración del nuevo paso en init | Insertar como **paso 4.7** (después de 4.6 Doctor) y renumerar el resumen actual a **paso 5**. | Tarea 2.1 |
| D2 | Edge case: binario ya instalado en init | Si `command -v codebase-memory-mcp` retorna 0, saltar la pregunta y reportar "Ya instalado". | Tarea 2.1 |
| D3 | Edge case: error de red durante `curl` | Warning (no error) + URL del repo para retry manual. | Tarea 2.1 |
| D4 | Bumpear `SKALLING_VERSION` en `setup-team-doctor.sh` | Bumpear de `"0.1.0"` a `"0.4.0"` (consistencia con `VERSION`). | Tarea 3.1 |
| D5 | Path del repo en links de comparación del CHANGELOG | `https://github.com/alexskalling/skalling-dev-team`. | Tarea 3.1 |
| D6 | Posición del párrafo en README | Entre `## Instalación` y `## Primeros pasos` (después de la línea 56). | Tarea 3.1 |
| D7 | Bundling de sub-secciones CHANGELOG | `### Added` + `### Changed` + `### Security` (consistente con [0.3.0]). | Tarea 3.1 |
| D8 | Helper para la inserción en 8 agentes | `sed` (uno por agente) con anchor `<!-- SINCRONIZADO CON: ...memory-protocol` y reemplazo `Code Intelligence + comment block` antes. Más simple que `awk`. | Tarea 1.2 |

---

## 6. Resumen ejecutivo

- **6 specs → 1 release atómico** (v0.4.0).
- **~15 archivos tocados, 0 archivos eliminados**.
- **Tests: 25+ nuevos asserts (PASS objetivo ≥ 12)**.
- **Bajo riesgo**: todo aditivo, opt-in, info-only donde toca info-only.
- **Sin nuevas deps**: codebase-memory-mcp NO está en `install-global.sh`, solo en opt-in de init.
- **Tiempo estimado**: 3h–4h de Teo (1h F1, 1h F2, 1h F3 + regresión).
