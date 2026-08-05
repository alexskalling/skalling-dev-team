#!/usr/bin/env bash
# tests/memory-protocol.test.sh — Tests del Memory Protocol (Fase 2, memory-improvements).
#
# Valida que:
#   1. templates/agents/snippets/memory-protocol.md existe y tiene las 4 secciones
#      obligatorias + la nota de sincronización (single source of truth).
#   2. Cada uno de los 8 agentes (Alex, Pol, Jes, Sol, Teo, Jhon, Luz, Pau) tiene
#      el marker `<!-- @include-snippet memory-protocol -->` (DC-2: el cuerpo vive
#      en templates/agents/snippets/memory-protocol.md y se expande en install).
#   3. Pau tiene el bloque "consolidación" extendido (rol específico de memoria).
#   4. El snippet canónico contiene los puntos clave (cuándo guardar, dónde,
#      cómo marcar contradicciones) — sanity check de que no quedó vacío.
#
# Patrón: tests/setup.test.sh y tests/concept-template.test.sh
# (set -euo pipefail, helpers pass/fail/log, asserts tipados).
#
# Uso:
#   bash tests/memory-protocol.test.sh
#   bash tests/memory-protocol.test.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNIPPET="$REPO_ROOT/templates/agents/snippets/memory-protocol.md"
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

# ──────────────────────────────────────────────────────────────────────────────
# TEST 1: Snippet canónico existe
# ──────────────────────────────────────────────────────────────────────────────

test_snippet_exists() {
    echo ""
    echo "── Test 1: Snippet canónico ──"

    assert_file_exists "$SNIPPET" "templates/agents/snippets/memory-protocol.md existe"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 2: 4 secciones obligatorias del snippet + nota de sincronización
# ──────────────────────────────────────────────────────────────────────────────

test_snippet_sections() {
    echo ""
    echo "── Test 2: 4 secciones + nota sync en snippet ──"

    local sections=(
        "Cuándo guardar"
        "Dónde guardar"
        "Cómo marcar contradicciones"
        "Qué NO guardar"
    )
    for s in "${sections[@]}"; do
        if [[ -f "$SNIPPET" ]] && grep -qE "^## ${s}" "$SNIPPET"; then
            pass "Sección '## ${s}' presente en snippet"
        else
            fail "Sección '## ${s}' FALTA en snippet"
        fi
    done

    # Nota de sincronización (single source)
    if [[ -f "$SNIPPET" ]] && grep -q "single source" "$SNIPPET"; then
        pass "Nota 'single source' presente en snippet"
    else
        fail "Nota 'single source' FALTA en snippet"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 3: 8 agentes tienen sección ## 🧠 Memory Protocol
# ──────────────────────────────────────────────────────────────────────────────

test_agents_have_section() {
    echo ""
    echo "── Test 3: 8 agentes con marker Memory Protocol ──"

    local agents=(Alex Pol Jes Sol Teo Jhon Luz Pau)
    for agent in "${agents[@]}"; do
        local file="$AGENTS_DIR/${agent}.md"
        if [[ -f "$file" ]] && grep -qE "<!-- @include-snippet memory-protocol -->" "$file"; then
            pass "${agent}.md tiene marker '## @include-snippet memory-protocol'"
        else
            fail "${agent}.md NO tiene marker 'memory-protocol'"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 4: Cada agente tiene el comment block SINCRONIZADO CON
# ──────────────────────────────────────────────────────────────────────────────

test_agents_have_sync_comment() {
    echo ""
    echo "── Test 4: 8 agentes con marker sincronizado (DC-2) ──"

    local agents=(Alex Pol Jes Sol Teo Jhon Luz Pau)
    for agent in "${agents[@]}"; do
        local file="$AGENTS_DIR/${agent}.md"
        if [[ -f "$file" ]] && grep -q "@include-snippet" "$file"; then
            pass "${agent}.md tiene markers de snippets (DC-2)"
        else
            fail "${agent}.md NO tiene markers de snippets"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 5: Pau tiene el bloque "consolidación" extendido
# ──────────────────────────────────────────────────────────────────────────────

test_pau_consolidation_block() {
    echo ""
    echo "── Test 5: Pau con bloque consolidación extendido ──"

    local pau="$AGENTS_DIR/Pau.md"

    # Menciona consolidación (case-insensitive para tolerar variantes)
    if [[ -f "$pau" ]] && grep -qiE "consolida[cr]ión" "$pau"; then
        pass "Pau.md menciona consolidación"
    else
        fail "Pau.md NO menciona consolidación"
    fi

    # El bloque describe el rol específico de Pau con palabras clave del spec
    if [[ -f "$pau" ]] && grep -qE "trabajo-en-curso.*decisiones|Luz.*Quality Gate" "$pau"; then
        pass "Pau.md describe el rol de consolidación con keywords del spec"
    else
        fail "Pau.md NO describe el rol de consolidación con keywords del spec"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 6: Sanity check — snippet tiene los 3 puntos clave
# ──────────────────────────────────────────────────────────────────────────────

test_snippet_key_points() {
    echo ""
    echo "── Test 6: Snippet tiene los 3 puntos clave (sanity check) ──"

    # Punto 1: cuándo guardar (momentos clave)
    if [[ -f "$SNIPPET" ]] && grep -qE "decisión|decisiones|arquitectóni" "$SNIPPET"; then
        pass "Snippet menciona decisiones arquitectónicas (cuándo guardar)"
    else
        fail "Snippet NO menciona momentos clave para guardar"
    fi

    # Punto 2: paths exactos
    if [[ -f "$SNIPPET" ]] && grep -qE "trabajo-en-curso|\.opencode/context/" "$SNIPPET"; then
        pass "Snippet referencia paths del bundle OKF (dónde guardar)"
    else
        fail "Snippet NO referencia paths del bundle OKF"
    fi

    # Punto 3: contradicciones
    if [[ -f "$SNIPPET" ]] && grep -qE "contradic" "$SNIPPET"; then
        pass "Snippet cubre cómo marcar contradicciones"
    else
        fail "Snippet NO cubre contradicciones"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# RUN
# ──────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════"
echo "  Memory Protocol Tests (Fase 2 — memory-improvements)"
echo "═══════════════════════════════════════════════════"

test_snippet_exists
test_snippet_sections
test_agents_have_section
test_agents_have_sync_comment
test_pau_consolidation_block
test_snippet_key_points

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
