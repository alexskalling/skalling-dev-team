#!/usr/bin/env bash
# tests/conflict-detection.test.sh — Tests de detección de conflictos en Pol (Fase 3, memory-improvements).
#
# Valida que:
#   1. Pol.md contiene una FASE 5 — Chequeo de conflictos contra memoria existente
#      ubicada después de las fases existentes de spec writing y antes del cierre.
#   2. La fase cubre los 3 escenarios:
#      a) Sin conflictos (nota breve "Sin conflictos con memoria existente")
#      b) Con conflictos (sección `## ⚠️ Conflictos detectados`)
#      c) Bundle corrupto (nota breve "Bundle corrupto, saltando check")
#   3. La fase referencia las áreas del bundle OKF (concept/, trabajo-en-curso/).
#   4. La numeración de fases existentes se preservó (FASE 1-4 intactas + nueva
#      FASE 5 + FASE 6 renumerada para no romper la FASE 5 previa "saltarse análisis").
#
# Patrón: tests/setup.test.sh y tests/memory-protocol.test.sh
# (set -euo pipefail, helpers pass/fail/log, asserts tipados).
#
# Uso:
#   bash tests/conflict-detection.test.sh
#   bash tests/conflict-detection.test.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POL="$REPO_ROOT/agents-base/Pol.md"

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
# TEST 1: Pol.md existe
# ──────────────────────────────────────────────────────────────────────────────

test_pol_exists() {
    echo ""
    echo "── Test 1: Pol.md presente ──"

    assert_file_exists "$POL" "agents-base/Pol.md existe"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 2: Pol.md tiene la nueva FASE 5 con título correcto
# ──────────────────────────────────────────────────────────────────────────────

test_phase5_title() {
    echo ""
    echo "── Test 2: FASE 5 — Chequeo de conflictos presente ──"

    if [[ -f "$POL" ]] && grep -qE "^### FASE 5 — Chequeo de conflictos" "$POL"; then
        pass "Pol.md contiene '### FASE 5 — Chequeo de conflictos'"
    else
        fail "Pol.md NO contiene la nueva FASE 5 — Chequeo de conflictos"
    fi

    if [[ -f "$POL" ]] && grep -qE "^### FASE 5.*memoria existente" "$POL"; then
        pass "FASE 5 menciona 'memoria existente' en el título"
    else
        fail "FASE 5 NO menciona 'memoria existente'"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 3: Tres escenarios cubiertos
# ──────────────────────────────────────────────────────────────────────────────

test_three_scenarios() {
    echo ""
    echo "── Test 3: 3 escenarios cubiertos ──"

    # Escenario A: sin conflictos
    if [[ -f "$POL" ]] && grep -qE "Sin conflictos con memoria existente" "$POL"; then
        pass "Escenario 'sin conflictos' cubierto"
    else
        fail "Escenario 'sin conflictos' FALTA"
    fi

    # Escenario B: con conflictos (sección con warning)
    if [[ -f "$POL" ]] && grep -qE "Conflictos detectados|⚠️ Conflictos" "$POL"; then
        pass "Escenario 'con conflictos' cubierto (sección Conflictos detectados)"
    else
        fail "Escenario 'con conflictos' FALTA"
    fi

    # Escenario C: bundle corrupto
    if [[ -f "$POL" ]] && grep -qE "[Bb]undle corrupto|saltando check" "$POL"; then
        pass "Escenario 'bundle corrupto' cubierto (con 'saltando check')"
    else
        fail "Escenario 'bundle corrupto' FALTA"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 4: Dos formatos diferenciados (sección vs nota breve)
# ──────────────────────────────────────────────────────────────────────────────

test_two_formats() {
    echo ""
    echo "── Test 4: 2 formatos diferenciados ──"

    # Formato 1: sección completa de Conflictos detectados (con o sin indentación)
    if [[ -f "$POL" ]] && grep -qE "^[[:space:]]*## ⚠️ Conflictos detectados" "$POL"; then
        pass "Formato completo '## ⚠️ Conflictos detectados' presente"
    else
        fail "Formato completo '## ⚠️ Conflictos detectados' FALTA"
    fi

    # El formato completo incluye campos estructurados (Razón, Propuesta)
    if [[ -f "$POL" ]] && grep -qE "Razón de contradicción|Concept doc contradicho" "$POL"; then
        pass "Formato de conflictos tiene campos estructurados"
    else
        fail "Formato de conflictos NO tiene campos estructurados"
    fi

    # Formato 2: nota breve "Sin conflictos"
    if [[ -f "$POL" ]] && grep -qE "Sin conflictos con memoria existente" "$POL"; then
        pass "Formato nota breve 'Sin conflictos con memoria existente' presente"
    else
        fail "Formato nota breve 'Sin conflictos' FALTA"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 5: Áreas del bundle OKF referenciadas
# ──────────────────────────────────────────────────────────────────────────────

test_bundle_areas_referenced() {
    echo ""
    echo "── Test 5: Áreas del bundle referenciadas ──"

    # concept/ es obligatorio (per usuario)
    if [[ -f "$POL" ]] && grep -qE "\\.opencode/context/concept" "$POL"; then
        pass "Área .opencode/context/concept/ referenciada"
    else
        fail "Área .opencode/context/concept/ NO referenciada"
    fi

    # trabajo-en-curso/ es obligatorio (per usuario)
    if [[ -f "$POL" ]] && grep -qE "trabajo-en-curso" "$POL"; then
        pass "Área trabajo-en-curso/ referenciada"
    else
        fail "Área trabajo-en-curso/ NO referenciada"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 6: Numeración coherente — FASE 4 intacta, FASE 5 nueva, FASE 6 renumerada
# ──────────────────────────────────────────────────────────────────────────────

test_phase_numbering_preserved() {
    echo ""
    echo "── Test 6: Numeración de fases coherente ──"

    # FASE 1-4 originales intactas
    local phases=("FASE 1 — Recepción" "FASE 2 — Cuestionamiento" "FASE 3 — Propuesta" "FASE 4 — Pase a Sol")
    for p in "${phases[@]}"; do
        if [[ -f "$POL" ]] && grep -qF "### $p" "$POL"; then
            pass "Pol.md preserva '### $p'"
        else
            fail "Pol.md perdió '### $p'"
        fi
    done

    # FASE 5 nueva presente
    if [[ -f "$POL" ]] && grep -qF "### FASE 5 — Chequeo de conflictos" "$POL"; then
        pass "Nueva FASE 5 presente"
    else
        fail "Nueva FASE 5 FALTA"
    fi

    # La antigua FASE 5 fue renumerada a FASE 6 (saltar análisis)
    if [[ -f "$POL" ]] && grep -qF "### FASE 6 — Si el usuario quiere saltarse" "$POL"; then
        pass "Antigua FASE 5 renumerada a FASE 6"
    else
        fail "Antigua FASE 5 NO renumerada a FASE 6"
    fi

    # La sección 'saltarse el análisis' sigue presente (no se rompió semántica)
    if [[ -f "$POL" ]] && grep -qE "saltarse el análisis|suficiente.*procede" "$POL"; then
        pass "Comportamiento de 'saltarse análisis' preservado"
    else
        fail "Comportamiento de 'saltarse análisis' perdido"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# RUN
# ──────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════"
echo "  Conflict Detection Tests (Fase 3 — memory-improvements)"
echo "═══════════════════════════════════════════════════"

test_pol_exists
test_phase5_title
test_three_scenarios
test_two_formats
test_bundle_areas_referenced
test_phase_numbering_preserved

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
