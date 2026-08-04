# Tasks: Integración opt-in de `codebase-memory-mcp`

> **Status**: Draft
> **Author**: Sol
> **Created**: 2026-08-04
> **Source**: `design.md` (Sol) + `proposal.md` + `specs/01..06-*.md` (Pol)
> **Scope**: Skalling v0.4.0
> **Estrategia**: Release atómico (todo de una vez, no gradual)

---

## 0. Resumen

| Fase | Tareas | Tiempo estimado | Dependencias |
|---|---|---|---|
| **Fase 1 — Snippet + inyección + test** | 1.1, 1.2, 1.3 | ~1h Teo | ninguna |
| **Fase 2 — Init opt-in + doctor** | 2.1, 2.2 | ~1h Teo | Fase 1 |
| **Fase 3 — Release** | 3.1, 3.2, 3.3, 3.4 | ~1h Teo + Jhon + Luz + Pau | Fase 1 + 2 |
| **Total** | **9 tareas** | **~3h** | — |

**Cada tarea es ejecutable por Teo en ≤ 30 minutos** y **verificable por Jhon de forma aislada** (un comando + un criterio de PASS).

---

## Fase 1 — Snippet + inyección + test

> **Objetivo**: que los 8 agentes tengan el snippet canónico + sección inyectada + test que lo valide.
> **Criterio de éxito de la fase**: `bash tests/code-intelligence.test.sh` corre con **PASS ≥ 25** (objetivo ≥ 12 según spec 03) y exit code 0.

---

### Tarea 1.1 — Crear snippet canónico `templates/agents/snippets/code-intelligence.md`

**Spec**: [01-snippet-canonico.md](specs/01-snippet-canonico.md)
**Quién**: Teo
**Quién valida**: Jhon
**Dependencias**: ninguna
**Tiempo estimado**: 20 min

**Archivos a crear:**

- `templates/agents/snippets/code-intelligence.md` (~80 líneas)

**Contenido obligatorio** (estructura, NO copy-paste literal):

```markdown
# 🔍 Code Intelligence (snippet canónico)

> **Este snippet es single source. Las copias en cada agente están
> sincronizadas por convención. Si editás este archivo, propagá a las 8
> copias** (`agents-base/{Alex,Pol,Jes,Sol,Teo,Jhon,Luz,Pau}.md`).

---

## Cuándo usar cada tool

[5 sub-secciones, una por tool, en este orden:]

### `mcp__codebase-memory-mcp__trace_path` — blast radius
- **Cuándo**: "quién llama a X", "qué afecta la función Y".
- **NO usar**: si la respuesta cabe en 1–2 archivos (`grep` es más rápido).
- **Ejemplo**: "qué afecta `parseUserInput` en el módulo auth" → `trace_path`.

### `mcp__codebase-memory-mcp__get_architecture` — overview
- **Cuándo**: "cómo funciona Y", "arquitectura general del proyecto".
- **NO usar**: si ya conocés el módulo, querés detalles → `trace_path`.
- **Ejemplo**: "explicame la arquitectura del servicio de pagos" → `get_architecture`.

### `mcp__codebase-memory-mcp__search_graph` — búsqueda por nombre
- **Cuándo**: "buscá función/clase por nombre exacto o parcial".
- **NO usar**: si sabés el archivo, usá `grep` directo.
- **Ejemplo**: "dónde está definida `RateLimiter`" → `search_graph`.

### `mcp__codebase-memory-mcp__find_dead_code` — código muerto
- **Cuándo**: "¿esta función se usa?", "¿qué podemos borrar?".
- **NO usar**: para verificar uso de una API específica → `grep` + llamada.
- **Ejemplo**: "funciones de utils/ que nadie llama" → `find_dead_code`.

### `mcp__codebase-memory-mcp__detect_changes` — análisis de PR
- **Cuándo**: "¿qué cambia este diff?", "¿rompemos algo?".
- **NO usar**: para diff textual de un archivo → `git diff`.
- **Ejemplo**: "este PR refactoriza auth, qué funciones quedan tocadas" → `detect_changes`.

---

## Si codebase-memory-mcp NO está instalado

Si `codebase-memory-mcp` NO está instalado (no aparece en `~/.config/opencode/opencode.jsonc`), seguí con `grep`/`read` como siempre. Este snippet NO debe romper proyectos sin el MCP — es guía, no assert rígido.

Activación: ver paso 4.7 de `/skalling-init` o instalar manualmente desde https://github.com/DeusData/codebase-memory-mcp.

---

## NO abuses

Para cambios triviales (1–2 archivos, función puntual) no vale la pena el query al MCP: `grep`/`read` es más rápido. El grafo del MCP se construye con `codebase-memory-mcp index` (responsabilidad del usuario, no de Skalling).

---

<!-- SINCRONIZADO CON: agents-base/{Alex,Pol,Jes,Sol,Teo,Jhon,Luz,Pau}.md (8 copias). Si editás este snippet, propagá a las 8 copias en el mismo PR. -->
```

**Validación por Jhon (comando único)**:

```bash
test -f templates/agents/snippets/code-intelligence.md && \
  grep -q "single source" templates/agents/snippets/code-intelligence.md && \
  for tool in trace_path get_architecture search_graph find_dead_code detect_changes; do
    grep -q "$tool" templates/agents/snippets/code-intelligence.md || exit 1
  done && \
  grep -qi "si codebase-memory-mcp NO está instalado" templates/agents/snippets/code-intelligence.md && \
  grep -qi "NO abuses" templates/agents/snippets/code-intelligence.md && \
  grep -q "SINCRONIZADO CON:" templates/agents/snippets/code-intelligence.md && \
  echo "OK: snippet válido"
```

**Criterio de "hecha"**: El comando imprime `OK: snippet válido`.

---

### Tarea 1.2 — Inyectar sección `## 🔍 Code Intelligence` en los 8 agentes

**Spec**: [02-inyeccion-8-agentes.md](specs/02-inyeccion-8-agentes.md)
**Quién**: Teo
**Quién valida**: Jhon
**Dependencias**: 1.1 (snippet debe existir)
**Tiempo estimado**: 15 min (operación atómica, no 8 tareas separadas)

**Archivos a editar:**

- `agents-base/Alex.md`
- `agents-base/Pol.md`
- `agents-base/Jes.md`
- `agents-base/Sol.md`
- `agents-base/Teo.md`
- `agents-base/Jhon.md`
- `agents-base/Luz.md`
- `agents-base/Pau.md`

**Operación (idéntica en los 8 archivos):**

1. Localizar el bloque existente:
   ```
   <!-- SINCRONIZADO CON: templates/agents/snippets/memory-protocol.md. Si editás esto, sincronizá ambos lados. -->

   ## 🧠 Memory Protocol
   ```
2. Insertar **antes** del `<!-- SINCRONIZADO CON: ...memory-protocol` (es decir, **antes** de la sección Memory Protocol) este bloque:
   ```markdown
   ---

   <!-- SINCRONIZADO CON: templates/agents/snippets/code-intelligence.md. Si editás esto, sincronizá ambos lados. -->

   ## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp

   > **Single source**: `templates/agents/snippets/code-intelligence.md`. Si modificás este bloque, propagá el cambio al snippet canónico y a las otras copias en `agents-base/*.md`.

   ---

   [CONTENIDO DEL SNIPPET, con sub-headings `###` en lugar de `##` para preservar la jerarquía dentro del agente]
   ```
3. Asegurarse de que el bloque entre Code Intelligence y Memory Protocol sea **un solo `---`**.

**Mecánica sugerida** (Teo decide: `sed` o `cat`/`paste`):

- **Opción A — sed in-place** (8 invocaciones, una por agente):
  ```bash
  for agent in Alex Pol Jes Sol Teo Jhon Luz Pau; do
      # Backup de seguridad
      cp "agents-base/${agent}.md" "agents-base/${agent}.md.bak"
      # Inserción antes del comment block existente de memory-protocol
      # (usar el helper skalling_sed_inplace si existe en scripts/lib)
  done
  ```
- **Opción B — edición manual con edit tool** (8 invocaciones, una por agente, más controlable).

**Regla de oro**: si el agente ya tiene un bloque `## 🔍 Code Intelligence` (caso raro de re-ejecución), NO se duplica. Se aborta y se reporta.

**Validación por Jhon (comando único)**:

```bash
for agent in Alex Pol Jes Sol Teo Jhon Luz Pau; do
    grep -qE "^## 🔍 Code Intelligence" "agents-base/${agent}.md" || { echo "FAIL: ${agent} sin sección"; exit 1; }
    grep -qE "SINCRONIZADO CON:.*code-intelligence" "agents-base/${agent}.md" || { echo "FAIL: ${agent} sin comment block"; exit 1; }
    # Verificar que Code Intelligence aparece ANTES de Memory Protocol
    ci_line=$(grep -nE "^## 🔍 Code Intelligence" "agents-base/${agent}.md" | head -1 | cut -d: -f1)
    mp_line=$(grep -nE "^## 🧠 Memory Protocol" "agents-base/${agent}.md" | head -1 | cut -d: -f1)
    [[ $ci_line -lt $mp_line ]] || { echo "FAIL: ${agent} orden incorrecto (CI=$ci_line, MP=$mp_line)"; exit 1; }
done && \
# Verificar frontmatter intacto (línea 1 debe empezar con ---)
for agent in Alex Pol Jes Sol Teo Jhon Luz Pau; do
    head -1 "agents-base/${agent}.md" | grep -q "^---$" || { echo "FAIL: ${agent} frontmatter perdido"; exit 1; }
done && \
echo "OK: 8 agentes con sección Code Intelligence"
```

**Criterio de "hecha"**: El comando imprime `OK: 8 agentes con sección Code Intelligence`. Si algún agente falla, Jhon lo devuelve a Teo. Limpiar `.bak` files al terminar.

---

### Tarea 1.3 — Crear test bash `tests/code-intelligence.test.sh`

**Spec**: [03-test-tdd.md](specs/03-test-tdd.md)
**Quién**: Teo
**Quién valida**: Jhon
**Dependencias**: 1.1 y 1.2 (el test valida lo que ya está implementado)
**Tiempo estimado**: 25 min

**Archivos a crear:**

- `tests/code-intelligence.test.sh` (~150 líneas)

**Estructura obligatoria** (basada en `tests/memory-protocol.test.sh`):

```bash
#!/usr/bin/env bash
# tests/code-intelligence.test.sh — Tests de Code Intelligence (v0.4.0 — codebase-memory-mcp).
#
# Valida que:
#   1. templates/agents/snippets/code-intelligence.md existe con las 5 tools
#      principales + nota fallback + nota anti-abuso + comment block sync.
#   2. Cada uno de los 8 agentes (Alex, Pol, Jes, Sol, Teo, Jhon, Luz, Pau) tiene
#      la sección `## 🔍 Code Intelligence` con comment block SINCRONIZADO CON.
#   3. El orden es correcto: Code Intelligence aparece ANTES de Memory Protocol.
#
# Patrón: tests/memory-protocol.test.sh
# (set -euo pipefail, helpers pass/fail/log, asserts tipados).
#
# Uso:
#   bash tests/code-intelligence.test.sh
#   bash tests/code-intelligence.test.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNIPPET="$REPO_ROOT/templates/agents/snippets/code-intelligence.md"
AGENTS_DIR="$REPO_ROOT/agents-base"

VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift ;;
        *) echo "Arg desconocido: $1"; exit 1 ;;
    esac
done

PASS=0
FAIL=0
FAILED_TESTS=()

c_green='\033[32m'
c_red='\033[31m'
c_reset='\033[0m'

pass() { PASS=$((PASS+1)); printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
fail() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$*"); printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
log()  { if [[ "$VERBOSE" == true ]]; then printf "    %s\n" "$*"; fi; }

assert_file_exists() {
    if [[ -f "$1" ]]; then pass "$2"; else fail "$2 — archivo no existe: $1"; fi
}

assert_file_contains() {
    if [[ -f "$1" ]] && grep -q "$2" "$1"; then
        pass "$3"
    else
        fail "$3 — no contiene '$2' en $1"
    fi
}

assert_file_contains_ci() {
    if [[ -f "$1" ]] && grep -qi "$2" "$1"; then
        pass "$3"
    else
        fail "$3 — no contiene '$2' (case-insensitive) en $1"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 1: Snippet canónico existe
# ──────────────────────────────────────────────────────────────────────────────

test_snippet_exists() {
    echo ""
    echo "── Test 1: Snippet canónico ──"
    assert_file_exists "$SNIPPET" "templates/agents/snippets/code-intelligence.md existe"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 2: 5 tools principales en snippet
# ──────────────────────────────────────────────────────────────────────────────

test_snippet_5_tools() {
    echo ""
    echo "── Test 2: 5 tools principales en snippet ──"
    local tools=(trace_path get_architecture search_graph find_dead_code detect_changes)
    for tool in "${tools[@]}"; do
        assert_file_contains "$SNIPPET" "$tool" "Snippet contiene tool $tool"
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 3: Notas obligatorias (fallback + anti-abuso + sync)
# ──────────────────────────────────────────────────────────────────────────────

test_snippet_notes() {
    echo ""
    echo "── Test 3: Notas obligatorias en snippet ──"
    assert_file_contains_ci "$SNIPPET" "si codebase-memory-mcp NO está instalado" "Nota fallback presente"
    assert_file_contains_ci "$SNIPPET" "NO abuses" "Nota anti-abuso presente"
    assert_file_contains    "$SNIPPET" "SINCRONIZADO CON:" "Nota sync presente"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 4: 8 agentes con sección ## 🔍 Code Intelligence
# ──────────────────────────────────────────────────────────────────────────────

test_agents_have_section() {
    echo ""
    echo "── Test 4: 8 agentes con sección ## 🔍 Code Intelligence ──"

    local agents=(Alex Pol Jes Sol Teo Jhon Luz Pau)
    for agent in "${agents[@]}"; do
        local file="$AGENTS_DIR/${agent}.md"
        if [[ -f "$file" ]] && grep -qE "^## 🔍 Code Intelligence" "$file"; then
            pass "${agent}.md tiene sección '## 🔍 Code Intelligence'"
        else
            fail "${agent}.md NO tiene '## 🔍 Code Intelligence'"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 5: 8 agentes con comment block SINCRONIZADO CON
# ──────────────────────────────────────────────────────────────────────────────

test_agents_have_sync_comment() {
    echo ""
    echo "── Test 5: 8 agentes con comment block SINCRONIZADO CON:.*code-intelligence ──"

    local agents=(Alex Pol Jes Sol Teo Jhon Luz Pau)
    for agent in "${agents[@]}"; do
        local file="$AGENTS_DIR/${agent}.md"
        if [[ -f "$file" ]] && grep -qE "SINCRONIZADO CON:.*code-intelligence" "$file"; then
            pass "${agent}.md tiene comment block SINCRONIZADO CON:.*code-intelligence"
        else
            fail "${agent}.md NO tiene comment block SINCRONIZADO CON:.*code-intelligence"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 6 (opcional MAY): Code Intelligence aparece ANTES de Memory Protocol
# ──────────────────────────────────────────────────────────────────────────────

test_agents_order_ci_before_mp() {
    echo ""
    echo "── Test 6: Code Intelligence antes de Memory Protocol (orden) ──"

    local agents=(Alex Pol Jes Sol Teo Jhon Luz Pau)
    for agent in "${agents[@]}"; do
        local file="$AGENTS_DIR/${agent}.md"
        if [[ -f "$file" ]]; then
            local ci_line mp_line
            ci_line=$(grep -nE "^## 🔍 Code Intelligence" "$file" | head -1 | cut -d: -f1 || echo "0")
            mp_line=$(grep -nE "^## 🧠 Memory Protocol" "$file" | head -1 | cut -d: -f1 || echo "0")
            if [[ "$ci_line" -gt 0 && "$mp_line" -gt 0 && "$ci_line" -lt "$mp_line" ]]; then
                pass "${agent}.md: Code Intelligence (línea $ci_line) antes de Memory Protocol (línea $mp_line)"
            else
                fail "${agent}.md: orden incorrecto (CI=$ci_line, MP=$mp_line)"
            fi
        else
            fail "${agent}.md no existe"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# RUN
# ──────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════"
echo "  Code Intelligence Tests (v0.4.0 — codebase-memory-mcp)"
echo "═══════════════════════════════════════════════════"

test_snippet_exists
test_snippet_5_tools
test_snippet_notes
test_agents_have_section
test_agents_have_sync_comment
test_agents_order_ci_before_mp

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Results: ${c_green}%d passed${c_reset}, ${c_red}%d failed${c_reset}\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        printf "  ${c_red}-${c_reset} %s\n" "$t"
    done
    exit 1
fi

echo ""
printf "${c_green}All tests passed.${c_reset}\n"
exit 0
```

**Hacer ejecutable**:

```bash
chmod +x tests/code-intelligence.test.sh
```

**Validación por Jhon (comando único)**:

```bash
bash tests/code-intelligence.test.sh
```

**Criterio de "hecha"**:

- Exit code 0.
- PASS ≥ 25 (los 6 tests deben imprimir resultados verdes).
- Salida final: `All tests passed.`

**Test de regresión** (no debe romper):

```bash
bash tests/memory-protocol.test.sh
```

**Criterio de regresión**: `memory-protocol.test.sh` sigue pasando con los mismos PASS de antes (los 8 agentes no deben haber perdido su `## 🧠 Memory Protocol` ni su comment block).

---

## Fase 2 — Init opt-in + doctor

> **Objetivo**: permitir opt-in en `/skalling-init` y reportar el MCP en el doctor.
> **Criterio de éxito de la fase**: el opt-in responde correctamente a las 3 ramas (Sí/No/ya-instalado) y el doctor muestra `ℹ Code Intelligence` sin incrementar `WARN_COUNT`/`ERROR_COUNT`.

---

### Tarea 2.1 — Editar `command/skalling-init.md` con paso 4.7 opt-in

**Spec**: [04-opt-in-init.md](specs/04-opt-in-init.md)
**Quién**: Teo
**Quién valida**: Jhon (manualmente, el init es conversacional)
**Dependencias**: ninguna
**Tiempo estimado**: 25 min

**Archivos a editar:**

- `command/skalling-init.md` (insertar paso 4.7 antes del resumen final)

**Operación:**

1. Localizar la línea actual `## Paso 5 — Resumen final` (línea 203 del archivo actual).
2. Renumerar el heading existente `## Paso 5 — Resumen final` → `## Paso 5 — Resumen final` (sin cambios, sigue siendo paso 5).
3. **Insertar antes** de `## Paso 5 — Resumen final` el nuevo bloque `### 4.7 — Code Intelligence (opt-in)` con el contenido del spec 04 (ver abajo).
4. Verificar que no hay otra mención de "Paso 5" en el archivo.

**Bloque a insertar (markdown)**:

```markdown
### 4.7 — Code Intelligence (opt-in)

`codebase-memory-mcp` ([DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)) es un servidor MCP que indexa codebases en un grafo de funciones y expone tools como `trace_path`, `get_architecture`, `search_graph`. Permite que Sol y Teo entiendan blast radius con 1 query en vez de leer 20 archivos.

**Importante**: es **opt-in, no dependencia**. Si no lo instalás, los agentes funcionan idéntico a antes (siguen con `grep`/`read`).

Primero verifico si ya está instalado:

```bash
command -v codebase-memory-mcp
```

**Si ya está** (`command -v` retorna 0): reporto "Ya tenés codebase-memory-mcp instalado en `<path>`. La integración con Skalling ya está activa." y salto al resumen.

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

**Si el curl falla** (red o error): mostrar warning "No pude instalar codebase-memory-mcp. Reintentá manualmente desde https://github.com/DeusData/codebase-memory-mcp". El init sigue normal.

```

**Validación por Jhon (lectura + simulación manual)**:

1. Leer el archivo `command/skalling-init.md` y verificar:
   - Aparece la sección `### 4.7 — Code Intelligence (opt-in)`.
   - Está entre la sección 4.6 (Doctor) y el Paso 5 (Resumen).
   - El comando en el bloque es exactamente `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash`.
   - El formato A/B/C es Sí/No.
   - La doble confirmación (opt-in + ejecución) está presente.
   - El mensaje de verificación usa `grep -q codebase-memory-mcp ~/.config/opencode/opencode.jsonc`.

2. (Opcional) Simular en un proyecto de prueba:
   - Correr `/skalling-init` y elegir A) Sí → verificar que muestra el comando + pide confirmación.
   - Correr `/skalling-init` y elegir B) No → verificar que sigue normal.
   - Con `codebase-memory-mcp` ya en PATH → verificar que salta la pregunta.

**Criterio de "hecha"**:

- El archivo contiene la nueva sección `### 4.7 — Code Intelligence (opt-in)` antes del Paso 5.
- El comando es el literal del spec.
- Las 3 ramas (Sí/No/ya-instalado) están contempladas.
- Verificación visual por Jhon (lectura del markdown) confirma que el flujo no rompe los pasos previos.

**Tests automatizados**: NO hay (el init es conversacional, no bash testeable). Jhon valida por inspección.

---

### Tarea 2.2 — Agregar `check_code_intelligence()` a `setup-team-doctor.sh`

**Spec**: [05-doctor-check.md](specs/05-doctor-check.md)
**Quién**: Teo
**Quién valida**: Jhon
**Dependencias**: ninguna
**Tiempo estimado**: 20 min

**Archivos a editar:**

- `setup-team-doctor.sh` (agregar función + llamada en `main()`)

**Operación:**

1. **Agregar función** antes de la sección `MAIN` (después de `check_project_install`, antes de `main()`):

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

2. **Agregar llamada en `main()`** después de `check_project_install` (justo antes del bloque `echo ""` + `━━━ Resumen ━━━`):

```bash
    check_code_intelligence
```

Insertar **entre** la línea `fi` que cierra `check_project_install` y el `echo ""` que precede al Resumen.

**Validación por Jhon (comandos múltiples)**:

```bash
# Test 1: el script corre sin error
bash setup-team-doctor.sh --global-only
# Esperado: exit code 0, aparece la sección "Code Intelligence (opt-in)" con prefijos ℹ azules

# Test 2: --strict no rompe por Code Intelligence
bash setup-team-doctor.sh --strict
# Esperado: exit code 0 (Code Intelligence no incrementa WARN_COUNT)

# Test 3: los hallazgos usan info() (azul), no warn/err
bash setup-team-doctor.sh --global-only 2>&1 | grep -A2 "Code Intelligence"
# Esperado: solo líneas con ℹ azul, ninguna con ⚠ o ✗

# Test 4: la sección aparece DESPUÉS de Check Project Install
bash setup-team-doctor.sh --global-only 2>&1 | grep -E "(Project Install|Code Intelligence|Resumen)"
# Esperado: orden: Instalación Per-Project → Code Intelligence (opt-in) → Resumen
```

**Criterios de "hecha"**:

- Comando 1: exit code 0 + sección visible.
- Comando 2: exit code 0 incluso con `--strict`.
- Comando 3: solo `ℹ` (azul), ningún `⚠`/`✗` en la sección Code Intelligence.
- Comando 4: orden correcto (Code Intelligence entre Instalación Per-Project y Resumen).

---

## Fase 3 — Release

> **Objetivo**: documentar el release v0.4.0, correr regresión completa, auditoría de Luz, archivo del change.
> **Criterio de éxito de la fase**: `VERSION = 0.4.0`, CHANGELOG actualizado, README con párrafo opt-in, todos los tests en verde, Luz PASSED, change archivado.

---

### Tarea 3.1 — Bump VERSION + CHANGELOG + README

**Spec**: [06-release-0.4.0.md](specs/06-release-0.4.0.md)
**Quién**: Teo
**Quién valida**: Jhon
**Dependencias**: Fase 1 + Fase 2 completas
**Tiempo estimado**: 20 min

**Archivos a editar:**

- `VERSION` (línea 1)
- `CHANGELOG.md` (insertar sección arriba de [0.3.0])
- `README.md` (insertar párrafo "Code Intelligence opt-in" después de Instalación)
- `setup-team-doctor.sh` (línea 29: `SKALLING_VERSION="0.1.0"` → `"0.4.0"`) — **decisión D4 a confirmar**

**Operación:**

**3.1.1 — VERSION** (1 línea):

```diff
- __version__ = "0.3.0"
+ __version__ = "0.4.0"
```

**3.1.2 — CHANGELOG.md** (insertar después de `## [Unreleased]` y antes de `## [0.3.0] — 2026-08-04`):

```markdown
## [0.4.0] — 2026-08-04

### Added
- **Code Intelligence (opt-in)**: integración con [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp) como feature opt-in (no dependencia dura). Los 8 agentes ganan una sección `## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp` con snippet canónico en `templates/agents/snippets/code-intelligence.md` + comment block `SINCRONIZADO CON` para mantenimiento.
- **Snippet canónico de 5 tools MCP**: `trace_path` (blast radius), `get_architecture` (overview), `search_graph` (búsqueda por nombre), `find_dead_code` (código muerto), `detect_changes` (análisis de PR). Incluye nota fallback "si NO está instalado, seguí con grep/read" y nota anti-abuso "NO abuses para cambios triviales".
- **Test bash `tests/code-intelligence.test.sh`**: 25+ asserts que validan snippet + 8 agentes (PASS objetivo ≥ 12). Patrón consistente con `tests/memory-protocol.test.sh`.
- **Paso 4.7 opt-in en `/skalling-init`**: nueva pregunta Sí/No al final del init. Si Sí, ejecuta `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash` con doble confirmación y verifica registro en `~/.config/opencode/opencode.jsonc`.
- **Sección informativa en `setup-team-doctor.sh`**: nueva función `check_code_intelligence()` reporta estado del binario + config MCP. Siempre `info()` (azul, ℹ), nunca warning/error. No afecta `--strict`.

### Changed
- `agents-base/*.md` (8 archivos): cada uno gana sección Code Intelligence antes de `## 🧠 Memory Protocol`. Frontmatter y reglas base intactos.
- `setup-team-doctor.sh`: nueva sección en output (no afecta `OK_COUNT`/`WARN_COUNT`/`ERROR_COUNT`).

### Security
- Ningún cambio de superficie de seguridad. `codebase-memory-mcp` se instala via `curl | bash` solo con opt-in explícito del usuario.
```

**3.1.3 — README.md** (insertar después de la línea 56, antes de `## Primeros pasos`):

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

**3.1.4 — setup-team-doctor.sh** (línea 29, bumpear `SKALLING_VERSION`):

```diff
- SKALLING_VERSION="0.1.0"
+ SKALLING_VERSION="0.4.0"
```

Nota: **Decisión a confirmar D4**. Si no se bumpea, el banner del doctor sigue diciendo v0.1.0 (inconsistencia visual). Default propuesto: bumpear.

**3.1.5 — Links de comparación en CHANGELOG.md** (al final del archivo, después de la línea 132):

```markdown
[0.4.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.3.0...v0.4.0
```

Y actualizar:

```diff
- [Unreleased]: https://github.com/tu-usuario/skalling-dev-team/compare/v0.3.0...HEAD
+ [Unreleased]: https://github.com/alexskalling/skalling-dev-team/compare/v0.4.0...HEAD
```

Nota: **Decisión a confirmar D5**. Default propuesto: `alexskalling/skalling-dev-team` (consistente con el path del README).

**Validación por Jhon (comando único)**:

```bash
# VERSION
grep -q '^__version__ = "0.4.0"$' VERSION || { echo "FAIL: VERSION no es 0.4.0"; exit 1; }
# SKALLING_VERSION (si D4 confirmado)
grep -q '^SKALLING_VERSION="0.4.0"$' setup-team-doctor.sh || { echo "FAIL: SKALLING_VERSION no bumped"; exit 1; }
# CHANGELOG
grep -q '^## \[0.4.0\] — 2026-08-04$' CHANGELOG.md || { echo "FAIL: CHANGELOG sin [0.4.0]"; exit 1; }
head -8 CHANGELOG.md | grep -q '^## \[0.4.0\]' || { echo "FAIL: [0.4.0] no está arriba de [0.3.0]"; exit 1; }
# README
grep -q "Code Intelligence (opt-in, v0.4.0+)" README.md || { echo "FAIL: README sin párrafo opt-in"; exit 1; }
# install-global.sh INTACTO
git diff --stat install-global.sh install-global.ps1 | grep -q . && { echo "FAIL: install-global tocado"; exit 1; }
echo "OK: release v0.4.0 documentado"
```

**Criterio de "hecha"**: El comando imprime `OK: release v0.4.0 documentado`. Si D4 no se confirma, omitir la línea de `SKALLING_VERSION` del chequeo.

---

### Tarea 3.2 — Regresión completa

**Spec**: transversal (cubre todos los anteriores)
**Quién**: Teo (corre tests) + Jhon (verifica receipts)
**Dependencias**: 1.3, 2.1, 2.2, 3.1
**Tiempo estimado**: 15 min

**Operación:**

1. Correr el nuevo test:
   ```bash
   bash tests/code-intelligence.test.sh
   ```
   Esperado: PASS ≥ 25, exit 0.

2. Correr regresión de tests previos:
   ```bash
   bash tests/memory-protocol.test.sh
   ```
   Esperado: PASS de antes (no regresión), exit 0.

3. Correr el resto de tests del repo:
   ```bash
   for t in tests/*.test.sh; do
       echo "── $t ──"
       bash "$t" || { echo "FAIL: $t"; exit 1; }
   done
   ```
   Esperado: todos los tests en verde.

4. Correr el doctor:
   ```bash
   bash setup-team-doctor.sh --strict
   ```
   Esperado: exit 0, sección "Code Intelligence (opt-in)" presente.

5. Verificar diff de `install-global.sh`:
   ```bash
   git diff install-global.sh install-global.ps1 | wc -l
   ```
   Esperado: 0 líneas (spec 06 MUST #5/#6).

**Validación por Jhon**:

```bash
# Bloque completo de regresión
bash tests/code-intelligence.test.sh && \
  bash tests/memory-protocol.test.sh && \
  bash setup-team-doctor.sh --strict && \
  [ "$(git diff install-global.sh install-global.ps1 | wc -l)" -eq 0 ] && \
  echo "OK: regresión completa en verde"
```

**Criterio de "hecha"**: El comando imprime `OK: regresión completa en verde`. Si algún test falla, Jhon lo devuelve a Teo.

---

### Tarea 3.3 — Auditoría de Luz

**Spec**: transversal (revisión final del change)
**Quién**: Luz
**Quién valida**: Jhon (recibe el veredicto)
**Dependencias**: 3.2 (regresión en verde)
**Tiempo estimado**: 20 min

**Operación:**

Luz revisa el change completo con foco en:

1. **Calidad de los markdown**:
   - Snippet canónico: texto claro, español consistente, sin typos.
   - Sub-secciones balanceadas (ninguna desproporcionada).
   - Notas (fallback + anti-abuso) redactadas en español correcto.

2. **Consistencia de la inyección en los 8 agentes**:
   - Comment block exacto en los 8.
   - Separación `---` consistente.
   - Sin duplicación accidental.

3. **Cobertura del test**:
   - 25 asserts verifican lo que el spec exige.
   - No hay asserts débiles (ej: aceptar substring cuando spec exige anchored regex).

4. **Init opt-in**:
   - El flujo de las 3 ramas es coherente.
   - El comando es exacto (case, URLs).
   - La doble confirmación está clara.

5. **Doctor**:
   - Sección no rompe otras.
   - Helper `info()` usado consistentemente.
   - Combinaciones de estado (4) bien manejadas.

6. **Release**:
   - CHANGELOG sigue Keep a Changelog + SemVer.
   - README coherente con el resto.
   - No hay links rotos.

**Veredicto de Luz**:

- `PASSED`: el change está listo para Pau.
- `REJECTED`: el change vuelve a Teo con observaciones específicas.

**Criterio de "hecha"**: Luz emite `PASSED` con evidencia (qué revisó + qué encontró limpio).

---

### Tarea 3.4 — Pau archiva el change

**Spec**: transversal (cierre del ciclo)
**Quién**: Pau
**Quién valida**: Jhon (verifica el archivo)
**Dependencias**: 3.3 (Luz PASSED)
**Tiempo estimado**: 10 min

**Operación:**

1. Mover el change completo a `.opencode/changes/archive/2026-08/`:
   ```bash
   mkdir -p .opencode/changes/archive/2026-08
   mv .opencode/changes/codebase-memory-mcp .opencode/changes/archive/2026-08/
   ```

2. Confirmar que la propuesta archivada queda como referencia histórica.

**Validación por Jhon**:

```bash
test -d .opencode/changes/archive/2026-08/codebase-memory-mcp && \
  test -f .opencode/changes/archive/2026-08/codebase-memory-mcp/proposal.md && \
  test -f .opencode/changes/archive/2026-08/codebase-memory-mcp/design.md && \
  test -f .opencode/changes/archive/2026-08/codebase-memory-mcp/tasks.md && \
  ls .opencode/changes/archive/2026-08/codebase-memory-mcp/specs/ | wc -l && \
  echo "OK: change archivado"
```

**Criterio de "hecha"**:

- El directorio `.opencode/changes/codebase-memory-mcp` ya no existe en la raíz.
- El directorio `.opencode/changes/archive/2026-08/codebase-memory-mcp/` contiene: `proposal.md`, `design.md`, `tasks.md`, `specs/01..06-*.md`.

---

## 4. Resumen de tests por tarea

| Tarea | Test que la cubre | Archivo de test |
|---|---|---|
| 1.1 — Snippet canónico | Tests 1, 2, 3 (existencia + 5 tools + notas) | `tests/code-intelligence.test.sh` |
| 1.2 — Inyección 8 agentes | Tests 4, 5, 6 (sección + comment block + orden) | `tests/code-intelligence.test.sh` |
| 1.3 — Test bash | (validación por Jhon: `bash tests/code-intelligence.test.sh` con PASS ≥ 25) | — |
| 2.1 — Init opt-in | (manual: Jhon lee `command/skalling-init.md` + simula 3 ramas) | — |
| 2.2 — Doctor check | (manual: `bash setup-team-doctor.sh --strict` + verificar ℹ azul) | — |
| 3.1 — Release | (Jhon verifica VERSION, CHANGELOG, README, SKALLING_VERSION) | — |
| 3.2 — Regresión | `tests/code-intelligence.test.sh` + `tests/memory-protocol.test.sh` + otros + `--strict` | múltiples |
| 3.3 — Auditoría Luz | (lectura del change completo, no test automatizado) | — |
| 3.4 — Archivo | (verificación de movimiento de carpeta) | — |

**Tests automatizados totales**: 25+ asserts nuevos en `tests/code-intelligence.test.sh`.
**Tests manuales totales**: 6 (2.1, 2.2, 3.1, 3.2, 3.3, 3.4).

---

## 5. Checklist de archivos a tocar

| # | Path | Acción | Tarea |
|---|---|---|---|
| 1 | `templates/agents/snippets/code-intelligence.md` | **crear** | 1.1 |
| 2 | `agents-base/Alex.md` | editar (insertar sección) | 1.2 |
| 3 | `agents-base/Pol.md` | editar | 1.2 |
| 4 | `agents-base/Jes.md` | editar | 1.2 |
| 5 | `agents-base/Sol.md` | editar | 1.2 |
| 6 | `agents-base/Teo.md` | editar | 1.2 |
| 7 | `agents-base/Jhon.md` | editar | 1.2 |
| 8 | `agents-base/Luz.md` | editar | 1.2 |
| 9 | `agents-base/Pau.md` | editar | 1.2 |
| 10 | `tests/code-intelligence.test.sh` | **crear** + `chmod +x` | 1.3 |
| 11 | `command/skalling-init.md` | editar (insertar paso 4.7) | 2.1 |
| 12 | `setup-team-doctor.sh` | editar (función + llamada) | 2.2 |
| 13 | `setup-team-doctor.sh` | editar (bumpear `SKALLING_VERSION`) | 3.1 |
| 14 | `VERSION` | editar (`0.3.0` → `0.4.0`) | 3.1 |
| 15 | `CHANGELOG.md` | editar (nueva sección + links) | 3.1 |
| 16 | `README.md` | editar (párrafo opt-in) | 3.1 |

**Archivos NO tocados** (confirmación explícita):

- `install-global.sh` / `install-global.ps1` — zero deps.
- `templates/agents/snippets/memory-protocol.md` — el snippet de memoria sigue intacto.
- `templates/handoff.schema.json` — sin cambios en schema.
- `constitution/constitucion.md` — sin reglas nuevas.
- Frontmatter de los 8 agentes — sin cambios.

---

## 6. Reglas de oro (recordatorio para Teo)

1. **Cada tarea pasa por Teo → Jhon** antes de avanzar a la siguiente.
2. **Luz audita el plan completo** al final (tarea 3.3).
3. **Pau archiva** después de Luz PASSED (tarea 3.4).
4. **NO se hacen commits** — eso es de Alex (R16).
5. **NO se reescriben agentes** — solo AGREGA la sección Code Intelligence antes de Memory Protocol.
6. **NO se toca `install-global.sh`** — codebase-memory-mcp es opt-in per-project.
7. **NO se toca la constitución** — Code Intelligence no es regla de gobernanza.
8. **Test aislado por tarea** — Jhon valida con un comando y un criterio de PASS objetivo.

---

## 7. Decisiones técnicas a confirmar (revisión de Jhon)

Las siguientes decisiones tienen **default propuesto** y se confirman al inicio de la tarea correspondiente:

| # | Decisión | Default propuesto | Tarea |
|---|---|---|---|
| D1 | Numeración del nuevo paso en init | Insertar como **paso 4.7** (después de 4.6 Doctor) y renumerar el resumen actual a **paso 5**. | 2.1 |
| D2 | Edge case: binario ya instalado en init | Si `command -v codebase-memory-mcp` retorna 0, saltar la pregunta y reportar "Ya instalado". | 2.1 |
| D3 | Edge case: error de red durante `curl` | Warning (no error) + URL del repo para retry manual. | 2.1 |
| D4 | Bumpear `SKALLING_VERSION` en `setup-team-doctor.sh` | Bumpear de `"0.1.0"` a `"0.4.0"` (consistencia con `VERSION`). | 3.1 |
| D5 | Path del repo en links de comparación del CHANGELOG | `https://github.com/alexskalling/skalling-dev-team`. | 3.1 |
| D6 | Posición del párrafo en README | Entre `## Instalación` y `## Primeros pasos` (después de la línea 56). | 3.1 |
| D7 | Bundling de sub-secciones CHANGELOG | `### Added` + `### Changed` + `### Security` (consistente con [0.3.0]). | 3.1 |
| D8 | Helper para la inserción en 8 agentes | `sed` in-place con anchor en comment block existente de memory-protocol. | 1.2 |

**Defaults vigentes** si Jhon no objeta en revisión.
