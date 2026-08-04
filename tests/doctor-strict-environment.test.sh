#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/setup-team-doctor.sh"

APROBADOS=0
FALLADOS=0
PRUEBAS_FALLIDAS=()

aprobar() { APROBADOS=$((APROBADOS+1)); printf "  \033[32m✓\033[0m %s\n" "$*"; }
rechazar() { FALLADOS=$((FALLADOS+1)); PRUEBAS_FALLIDAS+=("$*"); printf "  \033[31m✗\033[0m %s\n" "$*" >&2; }

FIXTURE="$(mktemp -d)"
GLOBAL_LIMPIO="$FIXTURE/global-limpio"
PROYECTO_LIMPIO="$FIXTURE/proyecto-limpio"
GLOBAL_TMP="$FIXTURE/global-con-warning"
PROYECTO_TMP="$FIXTURE/proyecto-con-warning"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$GLOBAL_LIMPIO/agents" "$GLOBAL_LIMPIO/skills/core" "$GLOBAL_LIMPIO/command" "$GLOBAL_LIMPIO/templates" "$GLOBAL_LIMPIO/skalling-data" "$PROYECTO_LIMPIO/.opencode"
printf '%s\n' '# Constitución' '' '## 🏛️ Reglas Base' '' 'R13 design-system.md' > "$GLOBAL_LIMPIO/constitucion.md"
printf '%s\n' '# Comando de fixture' > "$GLOBAL_LIMPIO/command/skalling-fixture.md"
for agente in Alex Pol Jes Sol Teo Jhon Luz Pau; do
    if [[ "$agente" == "Alex" ]]; then
        printf '%s\n' '---' 'mode: primary' "name: $agente" '---' > "$GLOBAL_LIMPIO/agents/${agente}.md"
    else
        printf '%s\n' '---' 'mode: subagent' "name: $agente" '---' > "$GLOBAL_LIMPIO/agents/${agente}.md"
    fi
done

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
SALIDA_ESTRICTA="$(SKALLING_OPENCODE_DIR="$GLOBAL_LIMPIO" bash "$DOCTOR" --project "$PROYECTO_LIMPIO" --strict 2>&1)"
CODIGO_SALIDA_ESTRICTO=$?
set -e

limpiar() { sed -E $'s/\033\\[[0-9;]*m//g'; }

WARN_COUNT_PROYECTO="$(printf '%s\n' "$SALIDA_ESTRICTA" | limpiar | awk '/^[[:space:]]*Warnings:[[:space:]]+[0-9]+/{print $2; exit}')"
WARN_ENV_COUNT="$(printf '%s\n' "$SALIDA_ESTRICTA" | limpiar | awk '/^[[:space:]]*Env:[[:space:]]+[0-9]+/{print $2; exit}')"
WARN_COUNT_PROYECTO="${WARN_COUNT_PROYECTO:-0}"
WARN_ENV_COUNT="${WARN_ENV_COUNT:-0}"

if [[ "$CODIGO_SALIDA_ESTRICTO" -eq 0 ]]; then
    aprobar "--strict exit 0 (WARN=$WARN_COUNT_PROYECTO project, ENV=$WARN_ENV_COUNT entorno)"
else
    rechazar "--strict exit $CODIGO_SALIDA_ESTRICTO — bash <4 warning NO debe promoverse a error"
fi

if [[ "${BASH_VERSINFO[0]}" -lt 4 && "$WARN_ENV_COUNT" -lt 1 ]]; then
    rechazar "bash <4 detectado pero $WARN_ENV_COUNT env warnings reportados — se perdió el warn_env()"
elif [[ "${BASH_VERSINFO[0]}" -lt 4 && "$WARN_ENV_COUNT" -ge 1 ]]; then
    aprobar "bash <4 warning categorizado como entorno (no proyecto)"
fi

echo ""
echo "── Test 2: categorización estructural ──"
echo "  Verifica que check_ambiente usa un canal distinto a warn() canónico,"

if grep -qE '^[[:space:]]*warn_env[[:space:]]*\(\)[[:space:]]*\{' "$DOCTOR"; then
    aprobar "Existe función warn_env() distinta a warn() del proyecto"
else
    rechazar "Falta función warn_env() para warnings de entorno"
fi

if grep -qE '^[[:space:]]*WARN_ENV_COUNT[[:space:]]*=' "$DOCTOR"; then
    aprobar "Existe contador separado WARN_ENV_COUNT"
else
    rechazar "Falta contador separado WARN_ENV_COUNT"
fi

if grep -qE 'check_ambiente.*warn_env|warn_env[[:space:]]+"bash ' "$DOCTOR"; then
    aprobar "check_ambiente usa warn_env() para el warning de versión de bash"
else
    rechazar "check_ambiente no usa warn_env() para bash <4"
fi

if grep -qE 'STRICT.*WARN_COUNT.*exit 1|exit 1.*STRICT.*WARN_COUNT' "$DOCTOR" \
    || (grep -qE 'WARN_COUNT.*-gt 0.*STRICT' "$DOCTOR" && ! grep -qE 'WARN_ENV_COUNT.*-gt 0.*STRICT' "$DOCTOR"); then
    aprobar "--strict se basa en WARN_COUNT (proyecto), no en WARN_ENV_COUNT (entorno)"
else
    rechazar "--strict no diferencia correctamente los contadores"
fi

echo ""
echo "── Test 3: --strict SÍ falla con warnings de proyecto ──"

mkdir -p "$GLOBAL_TMP/agents" "$GLOBAL_TMP/skills" "$GLOBAL_TMP/command" "$GLOBAL_TMP/templates" "$GLOBAL_TMP/skalling-data"
mkdir -p "$PROYECTO_TMP/.opencode/context"

printf '%s\n' '---' 'mode: primary' 'name: Alex' '---' > "$GLOBAL_TMP/agents/Alex.md"
printf '%s\n' '---' 'mode: subagent' 'name: FakeAgent' '---' > "$GLOBAL_TMP/agents/FakeAgent.md"

set +e
SALIDA_PROYECTO="$(SKALLING_OPENCODE_DIR="$GLOBAL_TMP" bash "$DOCTOR" --strict --project "$PROYECTO_TMP" 2>&1)"
CODIGO_SALIDA_PROYECTO=$?
set -e

if [[ "$CODIGO_SALIDA_PROYECTO" -eq 1 ]]; then
    aprobar "--strict exit 1 con warnings de proyecto (esperados 8 agentes, encontré 2)"
else
    rechazar "--strict exit $CODIGO_SALIDA_PROYECTO — debería ser 1 con warnings de proyecto"
fi

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$APROBADOS" "$FALLADOS"
echo "═══════════════════════════════════════════════════"

if [[ "$FALLADOS" -gt 0 ]]; then
    for t in "${PRUEBAS_FALLIDAS[@]}"; do
        printf "  \033[31m-\033[0m %s\n" "$t"
    done
    exit 1
fi

printf "\n\033[32mAll tests passed.\033[0m\n"
exit 0
