#!/usr/bin/env bash
# tests/doctor-strict-environment.test.sh — Verifica que --strict NO promueve
# a error warnings de entorno (bash <4, opencode/node/git no en PATH).
#
# Los warnings de configuración del proyecto (agentes faltantes, R13 violada,
# bundle corrupto) SÍ se promueven a error en strict. Los del entorno del
# usuario, NO: son responsabilidad del entorno, no del proyecto.
#
# Regla de verificación:
#   bash setup-team-doctor.sh --project "$(pwd)" --strict
#     → exit 0 si SOLO hay warnings de entorno
#     → exit 1 si hay warnings de proyecto

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/setup-team-doctor.sh"

PASS=0
FAIL=0
FAILED=()

pass() { PASS=$((PASS+1)); printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { FAIL=$((FAIL+1)); FAILED+=("$*"); printf "  \033[31m✗\033[0m %s\n" "$*" >&2; }

echo "═══════════════════════════════════════════════════"
echo "  Doctor --strict: warnings de entorno excluidos"
echo "═══════════════════════════════════════════════════"

if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    echo ""
    echo "  SKIP: bash $BASH_VERSION (>=4) no produce warning de entorno."
    echo "        El test es estructural: valida la categorización del código."
fi

echo ""
echo "── Test 1: comportamiento bajo --strict con bash actual ──"

set +e
OUTPUT_STRICT="$(bash "$DOCTOR" --project "$(pwd)" --strict 2>&1)"
EXIT_STRICT=$?
set -e

clean() { sed -E $'s/\033\\[[0-9;]*m//g'; }

WARN_COUNT="$(printf '%s\n' "$OUTPUT_STRICT" | clean | awk '/^[[:space:]]*Warnings:[[:space:]]+[0-9]+/{print $2; exit}')"
ENV_COUNT="$(printf '%s\n' "$OUTPUT_STRICT" | clean | awk '/^[[:space:]]*Env:[[:space:]]+[0-9]+/{print $2; exit}')"
WARN_COUNT="${WARN_COUNT:-0}"
ENV_COUNT="${ENV_COUNT:-0}"

if [[ "$EXIT_STRICT" -eq 0 ]]; then
    pass "--strict exit 0 (WARN=$WARN_COUNT project, ENV=$ENV_COUNT entorno)"
else
    fail "--strict exit $EXIT_STRICT — bash <4 warning NO debe promoverse a error"
fi

if [[ "${BASH_VERSINFO[0]}" -lt 4 && "$ENV_COUNT" -lt 1 ]]; then
    fail "bash <4 detectado pero $ENV_COUNT env warnings reportados — se perdió el warn_env()"
elif [[ "${BASH_VERSINFO[0]}" -lt 4 && "$ENV_COUNT" -ge 1 ]]; then
    pass "bash <4 warning categorizado como entorno (no proyecto)"
fi

echo ""
echo "── Test 2: categorización estructural ──"
echo "  Verifica que check_ambiente usa un canal distinto a warn() canónico,"

if grep -qE '^[[:space:]]*warn_env[[:space:]]*\(\)[[:space:]]*\{' "$DOCTOR"; then
    pass "Existe función warn_env() distinta a warn() del proyecto"
else
    fail "Falta función warn_env() para warnings de entorno"
fi

if grep -qE '^[[:space:]]*WARN_ENV_COUNT[[:space:]]*=' "$DOCTOR"; then
    pass "Existe contador separado WARN_ENV_COUNT"
else
    fail "Falta contador separado WARN_ENV_COUNT"
fi

if grep -qE 'check_ambiente.*warn_env|warn_env[[:space:]]+"bash ' "$DOCTOR"; then
    pass "check_ambiente usa warn_env() para el warning de versión de bash"
else
    fail "check_ambiente no usa warn_env() para bash <4"
fi

if grep -qE 'STRICT.*WARN_COUNT.*exit 1|exit 1.*STRICT.*WARN_COUNT' "$DOCTOR" \
    || (grep -qE 'WARN_COUNT.*-gt 0.*STRICT' "$DOCTOR" && ! grep -qE 'WARN_ENV_COUNT.*-gt 0.*STRICT' "$DOCTOR"); then
    pass "--strict se basa en WARN_COUNT (proyecto), no en WARN_ENV_COUNT (entorno)"
else
    fail "--strict no diferencia correctamente los contadores"
fi

echo ""
echo "── Test 3: --strict SÍ falla con warnings de proyecto ──"

TMP_PROJECT="$(mktemp -d)"
TMP_GLOBAL="$(mktemp -d)"
trap 'rm -rf "$TMP_PROJECT" "$TMP_GLOBAL"' EXIT

mkdir -p "$TMP_GLOBAL/agents" "$TMP_GLOBAL/skills" "$TMP_GLOBAL/command" "$TMP_GLOBAL/templates" "$TMP_GLOBAL/skalling-data"
mkdir -p "$TMP_PROJECT/.opencode/context"

printf '%s\n' '---' 'mode: primary' 'name: Alex' '---' > "$TMP_GLOBAL/agents/Alex.md"
printf '%s\n' '---' 'mode: subagent' 'name: FakeAgent' '---' > "$TMP_GLOBAL/agents/FakeAgent.md"

set +e
OUTPUT_PROJ="$(SKALLING_OPENCODE_DIR="$TMP_GLOBAL" bash "$DOCTOR" --strict --project "$TMP_PROJECT" 2>&1)"
EXIT_PROJ=$?
set -e

if [[ "$EXIT_PROJ" -eq 1 ]]; then
    pass "--strict exit 1 con warnings de proyecto (esperados 8 agentes, encontré 2)"
else
    fail "--strict exit $EXIT_PROJ — debería ser 1 con warnings de proyecto"
fi

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
    for t in "${FAILED[@]}"; do
        printf "  \033[31m-\033[0m %s\n" "$t"
    done
    exit 1
fi

printf "\n\033[32mAll tests passed.\033[0m\n"
exit 0
