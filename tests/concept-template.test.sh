#!/usr/bin/env bash
# tests/concept-template.test.sh — Tests del template OKF concept (Fase 1, memory-improvements).
#
# Valida que templates/okf/concept.template.md tiene las 4 secciones obligatorias
# (What / Why / Where / Learned) en el orden correcto, en el body (no en
# comentarios), y que cada sección tiene una descripción (no está vacía).
#
# Patrón: tests/setup.test.sh (set -euo pipefail, helpers pass/fail/log,
# asserts assert_file_exists / assert_file_contains).
#
# Uso:
#   bash tests/concept-template.test.sh
#   bash tests/concept-template.test.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/templates/okf/concept.template.md"

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

assert_file_contains_exact() {
    local line="$2"
    local desc="$3"
    # Coincidencia exacta de la línea completa (regex anclada)
    if [[ -f "$1" ]] && grep -qxF "$line" "$1"; then
        pass "$desc"
    else
        fail "$desc — falta línea exacta '$line' en $1"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 1: Template existe y frontmatter intacto
# ──────────────────────────────────────────────────────────────────────────────

test_template_exists_and_frontmatter() {
    echo ""
    echo "── Test 1: Template + frontmatter ──"

    assert_file_exists "$TEMPLATE" "concept.template.md existe"

    # Frontmatter OKF v0.2 intacto (no se toca en esta fase)
    assert_file_contains "$TEMPLATE" "^type: Concept" "frontmatter type: Concept presente"
    assert_file_contains "$TEMPLATE" "^title:" "frontmatter title presente"
    assert_file_contains "$TEMPLATE" "^timestamp:" "frontmatter timestamp presente"
    assert_file_contains "$TEMPLATE" "^confidence:" "frontmatter confidence presente"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 2: 4 secciones obligatorias presentes, en orden, en el body
# ──────────────────────────────────────────────────────────────────────────────

test_sections_in_order() {
    echo ""
    echo "── Test 2: 4 secciones en orden What → Why → Where → Learned ──"

    local headers
    headers="$(grep -nE "^## (What|Why|Where|Learned)$" "$TEMPLATE" 2>/dev/null || true)"
    log "Headers encontrados:"; log "$headers"

    local expected=("What" "Why" "Where" "Learned")
    local order_ok=true

    # Cada header debe aparecer exactamente una vez
    for h in "${expected[@]}"; do
        local count; count="$(grep -cE "^## ${h}$" "$TEMPLATE" 2>/dev/null || true)"
        if [[ "$count" -eq 1 ]]; then
            pass "Sección '## ${h}' presente (1 vez)"
        else
            fail "Sección '## ${h}' esperada 1 vez, encontrada ${count:-0}"
            order_ok=false
        fi
    done

    # Verificar orden: el line number de What < Why < Where < Learned
    local ln_what ln_why ln_where ln_learned
    ln_what="$(grep -nE "^## What$" "$TEMPLATE" | head -1 | cut -d: -f1 || echo 0)"
    ln_why="$(grep -nE "^## Why$" "$TEMPLATE" | head -1 | cut -d: -f1 || echo 0)"
    ln_where="$(grep -nE "^## Where$" "$TEMPLATE" | head -1 | cut -d: -f1 || echo 0)"
    ln_learned="$(grep -nE "^## Learned$" "$TEMPLATE" | head -1 | cut -d: -f1 || echo 0)"

    if [[ "$ln_what" -lt "$ln_why" ]] \
        && [[ "$ln_why" -lt "$ln_where" ]] \
        && [[ "$ln_where" -lt "$ln_learned" ]]; then
        pass "Orden correcto: What (línea $ln_what) → Why (línea $ln_why) → Where (línea $ln_where) → Learned (línea $ln_learned)"
    else
        fail "Orden incorrecto: What=$ln_what, Why=$ln_why, Where=$ln_where, Learned=$ln_learned"
    fi

    # No debe haber secciones legacy del template viejo (Qué es / Cómo se usa / Donde vive / Versiones / Links)
    local legacy_count; legacy_count="$(grep -cE "^## (Qué es|Cómo se usa|Donde vive|Versiones|Links relacionados)$" "$TEMPLATE" 2>/dev/null || true)"
    if [[ "$legacy_count" -eq 0 ]]; then
        pass "Sin secciones legacy (Qué es / Cómo se usa / Donde vive / Versiones / Links)"
    else
        fail "Encontradas ${legacy_count:-0} secciones legacy que deberían haber sido removidas"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 3: Cada sección tiene una descripción (no está vacía)
# ──────────────────────────────────────────────────────────────────────────────

test_sections_have_descriptions() {
    echo ""
    echo "── Test 3: Cada sección tiene descripción (no vacía) ──"

    # Extraer contenido entre ## <header> y el próximo ## (o fin de archivo)
    local headers=("What" "Why" "Where" "Learned")
    for h in "${headers[@]}"; do
        local body
        body="$(awk -v hdr="## ${h}" '
            $0 ~ "^"hdr"$" {found=1; next}
            found && /^## / {exit}
            found {print}
        ' "$TEMPLATE")"

        # Trim whitespace
        local trimmed; trimmed="$(printf '%s' "$body" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d')"

        if [[ -n "$trimmed" ]]; then
            pass "Sección '## ${h}' tiene descripción (no vacía)"
            log "  └─ inicio: $(printf '%s' "$trimmed" | head -1)"
        else
            fail "Sección '## ${h}' está vacía (sin descripción)"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 4: Pau referencia las 4 secciones por nombre
# ──────────────────────────────────────────────────────────────────────────────

test_pau_references_sections() {
    echo ""
    echo "── Test 4: Pau.md referencia las 4 secciones ──"

    local pau="$REPO_ROOT/agents-base/Pau.md"

    # Pau rechaza concept docs incompletos
    if grep -qE "rechaza|incompleto" "$pau"; then
        pass "Pau.md menciona 'rechaza' o 'incompleto'"
    else
        fail "Pau.md NO menciona 'rechaza' ni 'incompleto'"
    fi

    # Pau referencia las 4 secciones por nombre (regex permisivo)
    if grep -qE "What.*Why.*Where.*Learned|What, Why, Where, Learned" "$pau"; then
        pass "Pau.md referencia las 4 secciones por nombre"
    else
        fail "Pau.md NO referencia las 4 secciones en orden"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# RUN
# ──────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════"
echo "  Concept Template Tests (Fase 1 — memory-improvements)"
echo "═══════════════════════════════════════════════════"

test_template_exists_and_frontmatter
test_sections_in_order
test_sections_have_descriptions
test_pau_references_sections

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