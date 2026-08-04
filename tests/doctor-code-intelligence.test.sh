#!/usr/bin/env bash
set -euo pipefail

DIRECTORIO_RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$DIRECTORIO_RAIZ/setup-team-doctor.sh"

INSTANCIA_PROYECTO="$(mktemp -d)"
INSTANCIA_GLOBAL="$(mktemp -d)"
DOCTOR_SIN_CI="$(mktemp)"
HOME_BACKUP="$HOME"

trap 'rm -rf "$INSTANCIA_PROYECTO" "$INSTANCIA_GLOBAL" "$DOCTOR_SIN_CI"; export HOME="$HOME_BACKUP"' EXIT

mkdir -p "$INSTANCIA_PROYECTO/.opencode" "$INSTANCIA_GLOBAL/agents" "$INSTANCIA_GLOBAL/skills" "$INSTANCIA_GLOBAL/command" "$INSTANCIA_GLOBAL/templates" "$INSTANCIA_GLOBAL/skalling-data"

printf '%s\n' '# Constitución de Skalling' '' '## 🏛️ Reglas Base' '' 'R13 design-system.md obligatorio' > "$INSTANCIA_GLOBAL/constitucion.md"
for agente in Alex Pol Jes Sol Teo Jhon Luz Pau; do
    if [[ "$agente" == "Alex" ]]; then
        printf '%s\n' '---' 'mode: primary' "name: $agente" '---' > "$INSTANCIA_GLOBAL/agents/${agente}.md"
    else
        printf '%s\n' '---' 'mode: subagent' "name: $agente" '---' > "$INSTANCIA_GLOBAL/agents/${agente}.md"
    fi
done

awk '
    /^check_inteligencia_codigo\(\) \{/ { skip=1; brace=1; next }
    skip {
        for (i=1; i<=length($0); i++) {
            ch = substr($0, i, 1)
            if (ch == "{") brace++
            if (ch == "}") brace--
        }
        if (brace <= 0) skip=0
        next
    }
    /^[[:space:]]*check_inteligencia_codigo[[:space:]]*$/ { next }
    { print }
' "$DOCTOR" > "$DOCTOR_SIN_CI"

APROBADOS=0
FALLADOS=0
PRUEBAS_FALLIDAS=()

c_verde='\033[32m'
c_rojo='\033[31m'
c_reset='\033[0m'

aprobar() { APROBADOS=$((APROBADOS + 1)); printf "  ${c_verde}✓${c_reset} %s\n" "$1"; }
rechazar() { FALLADOS=$((FALLADOS + 1)); PRUEBAS_FALLIDAS+=("$1"); printf "  ${c_rojo}✗${c_reset} %s\n" "$1" >&2; }

afirmar_coincidencias() {
    local patron="$1"
    local archivo="$2"
    local esperado="$3"
    local descripcion="$4"
    local cuenta
    cuenta="$(grep -cE "$patron" "$archivo" 2>/dev/null | head -1 || true)"
    cuenta="${cuenta:-0}"
    if [[ "$cuenta" -eq "$esperado" ]]; then
        aprobar "$descripcion (cuenta=$cuenta)"
    else
        rechazar "$descripcion (esperado=$esperado, observado=$cuenta)"
    fi
}

limpiar_colores() { sed -E $'s/\033\\[[0-9;]*m//g'; }

echo "═══════════════════════════════════════════════════"
echo "  Tests del check_inteligencia_codigo() en el doctor"
echo "═══════════════════════════════════════════════════"

echo ""
echo "── Test: función existe y se invoca ──"

afirmar_coincidencias '^check_inteligencia_codigo\(\)[[:space:]]*\{' "$DOCTOR" 1 \
    "check_inteligencia_codigo() está definida"

afirmar_coincidencias '^[[:space:]]*check_inteligencia_codigo[[:space:]]*$' "$DOCTOR" 1 \
    "check_inteligencia_codigo está invocada en el flujo principal"

echo ""
echo "── Test: 3 ramas cubiertas ──"

afirmar_coincidencias 'command -v codebase-memory-mcp' "$DOCTOR" 1 \
    "Rama 1: detecta binario con 'command -v codebase-memory-mcp'"

afirmar_coincidencias 'codebase-memory-mcp.*opencode\.jsonc|opencode\.jsonc.*codebase-memory-mcp' "$DOCTOR" 1 \
    "Rama 2: chequea registro en opencode.jsonc"

if grep -qE 'codebase-memory-mcp.*(NO instalado|no instalado)' "$DOCTOR"; then
    aprobar "Rama 3: mensaje de no instalado presente"
else
    rechazar "Rama 3: mensaje de no instalado ausente"
fi

echo ""
echo "── Test: solo info() en la sección Code Intelligence ──"

BLOQUE_CI="$(mktemp)"
if awk '
    /^check_inteligencia_codigo\(\)[[:space:]]*\{/ { capturar=1; llave=1; next }
    capturar {
        print
        for (i=1; i<=length($0); i++) {
            ch = substr($0, i, 1)
            if (ch == "{") llave++
            if (ch == "}") llave--
        }
        if (llave <= 0) { capturar=0; exit }
    }
' "$DOCTOR" > "$BLOQUE_CI" && [[ -s "$BLOQUE_CI" ]]; then
    if grep -qE '\bwarn\(' "$BLOQUE_CI"; then
        rechazar "Code Intelligence usa warn() — debe ser SOLO info()"
    else
        aprobar "Code Intelligence NO usa warn()"
    fi
    if grep -qE '^[[:space:]]*[^#]*[[:space:]]err\(' "$BLOQUE_CI"; then
        rechazar "Code Intelligence usa err() — debe ser SOLO info()"
    else
        aprobar "Code Intelligence NO usa err()"
    fi
    if grep -qE '^[[:space:]]*[^#]*info[[:space:]]' "$BLOQUE_CI"; then
        aprobar "Code Intelligence usa info()"
    else
        rechazar "Code Intelligence NO usa info()"
    fi
else
    rechazar "No se pudo extraer el bloque check_inteligencia_codigo"
fi
rm -f "$BLOQUE_CI"

echo ""
echo "── Test: output del doctor con --global-only ──"

set +e
SALIDA_STRICT="$(SKALLING_OPENCODE_DIR="$INSTANCIA_GLOBAL" bash "$DOCTOR" --global-only 2>&1)"
ESTADO=$?
set -e

if [[ "$SALIDA_STRICT" == *"Code Intelligence (opt-in)"* ]]; then
    aprobar "Header 'Code Intelligence (opt-in)' aparece en el output del doctor"
else
    rechazar "Header 'Code Intelligence (opt-in)' NO aparece en el output del doctor"
fi

if [[ "$ESTADO" -eq 0 ]]; then
    aprobar "Doctor --global-only exit 0 (sin warnings de Code Intelligence)"
else
    rechazar "Doctor --global-only exit $ESTADO — Code Intelligence no debe incrementar WARN_COUNT"
fi

set +e
SALIDA_SIN_CI="$(SKALLING_OPENCODE_DIR="$INSTANCIA_GLOBAL" bash "$DOCTOR_SIN_CI" --global-only 2>&1)"
ADVERTENCIAS_SIN_CI="$(printf '%s\n' "$SALIDA_SIN_CI" | limpiar_colores | awk '/^[[:space:]]*Warnings:[[:space:]]+[0-9]+/{print $2; exit}')"
ADVERTENCIAS_CON_CI="$(printf '%s\n' "$SALIDA_STRICT" | limpiar_colores | awk '/^[[:space:]]*Warnings:[[:space:]]+[0-9]+/{print $2; exit}')"
set -e
ADVERTENCIAS_SIN_CI="${ADVERTENCIAS_SIN_CI:-0}"
ADVERTENCIAS_CON_CI="${ADVERTENCIAS_CON_CI:-0}"

if [[ "$ADVERTENCIAS_CON_CI" -eq "$ADVERTENCIAS_SIN_CI" ]]; then
    aprobar "Code Intelligence no incrementa WARN_COUNT (con=$ADVERTENCIAS_CON_CI, sin=$ADVERTENCIAS_SIN_CI)"
else
    rechazar "Code Intelligence incrementó WARN_COUNT (con=$ADVERTENCIAS_CON_CI, sin=$ADVERTENCIAS_SIN_CI)"
fi

echo ""
echo "── Test: posición en el output + sin warnings bajo --strict --project ──"

set +e
SALIDA_COMPLETA="$(SKALLING_OPENCODE_DIR="$INSTANCIA_GLOBAL" bash "$DOCTOR" --strict --project "$INSTANCIA_PROYECTO" 2>&1)"
ADVERTENCIAS_COMPLETA="$(printf '%s\n' "$SALIDA_COMPLETA" | limpiar_colores | awk '/^[[:space:]]*Warnings:[[:space:]]+[0-9]+/{print $2; exit}')"
SALIDA_COMPLETA_SIN_CI="$(SKALLING_OPENCODE_DIR="$INSTANCIA_GLOBAL" bash "$DOCTOR_SIN_CI" --strict --project "$INSTANCIA_PROYECTO" 2>&1)"
ADVERTENCIAS_COMPLETA_SIN_CI="$(printf '%s\n' "$SALIDA_COMPLETA_SIN_CI" | limpiar_colores | awk '/^[[:space:]]*Warnings:[[:space:]]+[0-9]+/{print $2; exit}')"
set -e
ADVERTENCIAS_COMPLETA="${ADVERTENCIAS_COMPLETA:-0}"
ADVERTENCIAS_COMPLETA_SIN_CI="${ADVERTENCIAS_COMPLETA_SIN_CI:-0}"

linea_per_project="$(printf '%s\n' "$SALIDA_COMPLETA" | awk '/━━━ Instalación Per-Project/{print NR; exit}')"
linea_ci="$(printf '%s\n' "$SALIDA_COMPLETA" | awk '/━━━ Code Intelligence \(opt-in\)/{print NR; exit}')"
linea_resumen="$(printf '%s\n' "$SALIDA_COMPLETA" | awk '/━━━ Resumen ━━━/{print NR; exit}')"

if [[ -n "$linea_per_project" && -n "$linea_ci" && -n "$linea_resumen" ]] \
    && (( linea_per_project < linea_ci && linea_ci < linea_resumen )); then
    aprobar "Code Intelligence aparece entre Per-Project y Resumen (orden correcto)"
else
    rechazar "Orden incorrecto: PerProject=$linea_per_project, CI=$linea_ci, Resumen=$linea_resumen"
fi

if [[ "$ADVERTENCIAS_COMPLETA" -eq "$ADVERTENCIAS_COMPLETA_SIN_CI" ]]; then
    aprobar "Code Intelligence no agrega warnings en --strict --project (con=$ADVERTENCIAS_COMPLETA, sin=$ADVERTENCIAS_COMPLETA_SIN_CI)"
else
    rechazar "Code Intelligence agregó warnings (con=$ADVERTENCIAS_COMPLETA, sin=$ADVERTENCIAS_COMPLETA_SIN_CI)"
fi

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Resultados: ${c_verde}%d aprobados${c_reset}, ${c_rojo}%d fallados${c_reset}\n" "$APROBADOS" "$FALLADOS"
echo "═══════════════════════════════════════════════════"

if [[ "$FALLADOS" -gt 0 ]]; then
    echo ""
    echo "Pruebas fallidas:"
    for t in "${PRUEBAS_FALLIDAS[@]}"; do
        printf "  ${c_rojo}-${c_reset} %s\n" "$t"
    done
    exit 1
fi

echo ""
printf "${c_verde}Todas las pruebas aprobadas.${c_reset}\n"
exit 0
