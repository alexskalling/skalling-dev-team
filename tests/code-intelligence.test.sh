#!/usr/bin/env bash
set -euo pipefail

DIRECTORIO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ_REPO="$(cd "$DIRECTORIO_SCRIPT/.." && pwd)"
FRAGMENTO="$RAIZ_REPO/templates/agents/snippets/code-intelligence.md"
DIRECTORIO_AGENTES="$RAIZ_REPO/agents-base"

VERBOSO=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSO=true; shift ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

APROBADOS=0
FALLADOS=0
PRUEBAS_FALLIDAS=()

c_verde='\033[32m'
c_rojo='\033[31m'
c_reset='\033[0m'

aprobar() { APROBADOS=$((APROBADOS+1)); printf "  ${c_verde}✓${c_reset} %s\n" "$*"; }
rechazar() { FALLADOS=$((FALLADOS+1)); PRUEBAS_FALLIDAS+=("$*"); printf "  ${c_rojo}✗${c_reset} %s\n" "$*" >&2; }
registrar() { if [[ "$VERBOSO" == true ]]; then printf "    %s\n" "$*"; fi; }

afirmar_existe_archivo() {
    if [[ -f "$1" ]]; then
        aprobar "$2"
    else
        rechazar "$2 — archivo no existe: $1"
    fi
}

afirmar_archivo_contiene() {
    if [[ -f "$1" ]] && grep -q -- "$2" "$1"; then
        aprobar "$3"
    else
        rechazar "$3 — no contiene '$2' en $1"
    fi
}

afirmar_archivo_contiene_sensible_caso() {
    if [[ -f "$1" ]] && grep -qi -- "$2" "$1"; then
        aprobar "$3"
    else
        rechazar "$3 — no contiene '$2' (case-insensitive) en $1"
    fi
}

afirmar_comment_frontmatter_fragmento() {
    local primera_linea=""
    if [[ -f "$FRAGMENTO" ]]; then
        IFS= read -r primera_linea < "$FRAGMENTO" || true
    fi

    if [[ "$primera_linea" == "<!--" ]] && grep -q "SINCRONIZADO CON: este archivo es single source" "$FRAGMENTO"; then
        aprobar "Fragmento tiene comment frontmatter de single source"
    else
        rechazar "Fragmento no tiene el comment frontmatter esperado"
    fi
}

afirmar_seccion_agente() {
    local agente="$1"
    local archivo="$DIRECTORIO_AGENTES/${agente}.md"
    if [[ -f "$archivo" ]] && grep -qE "^## 🔍 Code Intelligence — cuándo usar codebase-memory-mcp$" "$archivo"; then
        aprobar "${agente}.md tiene sección Code Intelligence"
    else
        rechazar "${agente}.md no tiene la sección Code Intelligence exacta"
    fi
}

afirmar_comment_sincronizacion_agente() {
    local agente="$1"
    local archivo="$DIRECTORIO_AGENTES/${agente}.md"
    if [[ -f "$archivo" ]] && grep -qE "SINCRONIZADO CON:.*code-intelligence" "$archivo"; then
        aprobar "${agente}.md tiene comment block de sincronización"
    else
        rechazar "${agente}.md no tiene comment block de sincronización"
    fi
}

afirmar_orden_agente() {
    local agente="$1"
    local archivo="$DIRECTORIO_AGENTES/${agente}.md"
    local linea_ci=""
    local linea_mp=""

    if [[ -f "$archivo" ]]; then
        linea_ci="$(awk '/^## 🔍 Code Intelligence/{print NR; exit}' "$archivo")"
        linea_mp="$(awk '/^## 🧠 Memory Protocol/{print NR; exit}' "$archivo")"
    fi

    if [[ "$linea_ci" =~ ^[0-9]+$ ]] && [[ "$linea_mp" =~ ^[0-9]+$ ]] && (( linea_ci < linea_mp )); then
        aprobar "${agente}.md ubica Code Intelligence antes de Memory Protocol"
        registrar "${agente}.md: CI=$linea_ci, MP=$linea_mp"
    else
        rechazar "${agente}.md tiene orden incorrecto (CI=${linea_ci:-ausente}, MP=${linea_mp:-ausente})"
    fi
}

afirmar_frontmatter_agente() {
    local agente="$1"
    local archivo="$DIRECTORIO_AGENTES/${agente}.md"
    local primera_linea=""
    if [[ -f "$archivo" ]]; then
        IFS= read -r primera_linea < "$archivo" || true
    fi

    if [[ "$primera_linea" == "---" ]]; then
        aprobar "${agente}.md conserva frontmatter en la primera línea"
    else
        rechazar "${agente}.md perdió el frontmatter inicial"
    fi
}

prueba_fragmento() {
    echo ""
    echo "── Prueba 1: Fragmento canónico ──"
    afirmar_existe_archivo "$FRAGMENTO" "templates/agents/snippets/code-intelligence.md existe"
    afirmar_comment_frontmatter_fragmento
    afirmar_archivo_contiene "$FRAGMENTO" "# 🔍 Code Intelligence" "Fragmento tiene heading canónico"
    afirmar_archivo_contiene "$FRAGMENTO" "single source" "Fragmento declara single source"
}

prueba_fragmento_herramientas() {
    echo ""
    echo "── Prueba 2: 5 herramientas principales ──"
    local herramientas=(trace_path get_architecture search_graph find_dead_code detect_changes)
    for herramienta in "${herramientas[@]}"; do
        afirmar_archivo_contiene "$FRAGMENTO" "mcp__codebase-memory-mcp__${herramienta}" "Fragmento contiene herramienta ${herramienta}"
    done
}

prueba_fragmento_notas() {
    echo ""
    echo "── Prueba 3: Fallback, anti-abuso y sincronización ──"
    afirmar_archivo_contiene_sensible_caso "$FRAGMENTO" "si codebase-memory-mcp NO está instalado" "Fragmento incluye fallback si el MCP no está instalado"
    afirmar_archivo_contiene_sensible_caso "$FRAGMENTO" "NO abuses" "Fragmento incluye nota anti-abuso"
    afirmar_archivo_contiene "$FRAGMENTO" "SINCRONIZADO CON:" "Fragmento incluye comment block de sincronización"
}

prueba_agentes() {
    echo ""
    echo "── Prueba 4: 8 agentes ──"
    local agentes=(Alex Pol Jes Sol Teo Jhon Luz Pau)
    local agente
    for agente in "${agentes[@]}"; do
        afirmar_seccion_agente "$agente"
        afirmar_comment_sincronizacion_agente "$agente"
        afirmar_orden_agente "$agente"
        afirmar_frontmatter_agente "$agente"
    done
}

echo "═══════════════════════════════════════════════════"
echo "  Pruebas de Code Intelligence (v0.4.0 — codebase-memory-mcp)"
echo "═══════════════════════════════════════════════════"

prueba_fragmento
prueba_fragmento_herramientas
prueba_fragmento_notas
prueba_agentes

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Resultados: ${c_verde}%d aprobados${c_reset}, ${c_rojo}%d fallados${c_reset}\n" "$APROBADOS" "$FALLADOS"
echo "═══════════════════════════════════════════════════"

if [[ "$FALLADOS" -gt 0 ]]; then
    echo ""
    echo "Pruebas fallidas:"
    for nombre in "${PRUEBAS_FALLIDAS[@]}"; do
        printf "  ${c_rojo}-${c_reset} %s\n" "$nombre"
    done
    exit 1
fi

echo ""
printf "${c_verde}Todas las pruebas aprobadas.${c_reset}\n"
exit 0
