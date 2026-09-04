#!/usr/bin/env bash
set -euo pipefail

DIRECTORIO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ_REPOSITORIO="$(cd "$DIRECTORIO_SCRIPT/.." && pwd)"

c_verde='\033[32m'
c_rojo='\033[31m'
c_azul='\033[36m'
c_neutro='\033[0m'
MODO_COLOR=0
LIMITE_LINEAS_BLOQUE=100

total_aprobados=0
total_fallidos=0
total_reconocidos=0

uso() {
    cat <<TEXTO
Uso: bash skalling-drift.sh <plan-archivado>

Argumentos:
  <plan-archivado>    Ruta al directorio raíz de un plan archivado
                     que contiene un subdirectorio specs/ con archivos .md.

Ejemplo:
  bash skalling-drift.sh .opencode/changes/archive/2026-08/memory-improvements/
TEXTO
    exit 0
}

activar_color() {
    if [[ -t 1 ]]; then
        MODO_COLOR=1
    else
        MODO_COLOR=0
    fi
}

imprimir_error_entrada() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "${c_rojo}error:${c_neutro} %s\n" "$*" >&2
    else
        printf "error: %s\n" "$*" >&2
    fi
}

imprimir_advertencia() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "${c_azul}advertencia:${c_neutro} %s\n" "$*" >&2
    else
        printf "advertencia: %s\n" "$*" >&2
    fi
}

imprimir_ok() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "  ${c_verde}✓${c_neutro} %s\n" "$*"
    else
        printf "  ✓ %s\n" "$*"
    fi
}

imprimir_fallo() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "  ${c_rojo}✗${c_neutro} %s\n" "$*" >&2
    else
        printf "  ✗ %s\n" "$*" >&2
    fi
}

validar_argv() {
    if [[ $# -eq 0 ]]; then
        imprimir_error_entrada "Falta el argumento <plan>. Uso: bash skalling-drift.sh <plan-archivado>"
        exit 1
    fi
    if [[ $# -ne 1 ]]; then
        imprimir_error_entrada "Se esperaba exactamente 1 argumento posicional, se recibieron $#."
        exit 1
    fi
    if [[ ! -d "$1" ]]; then
        imprimir_error_entrada "$1 no existe o no es directorio"
        exit 1
    fi
}

listar_specs() {
    local directorio_plan="$1"
    local directorio_specs="$directorio_plan/specs"

    if [[ ! -d "$directorio_specs" ]]; then
        imprimir_error_entrada "$directorio_plan no contiene directorio specs/"
        exit 1
    fi

    local specs_vacios
    specs_vacios="$(find "$directorio_specs" -maxdepth 1 -type f -name '*.md' | sort)"
    if [[ -z "$specs_vacios" ]]; then
        imprimir_error_entrada "$directorio_specs no contiene archivos .md"
        exit 1
    fi

    printf '%s\n' "$specs_vacios"
}

extraer_bloque_verificacion() {
    local ruta_spec="$1"
    local en_bloque="false"
    local lineas_bloque=0

    while IFS= read -r linea || [[ -n "$linea" ]]; do
        if [[ "$en_bloque" == "false" ]]; then
            if [[ "$linea" == "## Verificación" ]]; then
                en_bloque="true"
            fi
        else
            if [[ "$linea" == "## "* ]]; then
                break
            fi
            lineas_bloque=$((lineas_bloque + 1))
            if [[ "$lineas_bloque" -eq $((LIMITE_LINEAS_BLOQUE + 1)) ]]; then
                imprimir_advertencia "bloque ## Verificación supera el límite de $LIMITE_LINEAS_BLOQUE líneas (spec: $(basename "$ruta_spec"))"
            fi
            printf '%s\n' "$linea"
        fi
    done < "$ruta_spec"
}

imprimir_linea_resultado() {
    local estado="$1"
    local spec="$2"
    local claim="$3"
    local mensaje="$claim (spec: $(basename "$spec"))"
    if [[ "$estado" == "ok" ]]; then
        imprimir_ok "$mensaje"
    else
        imprimir_fallo "$mensaje"
    fi
}

imprimir_resumen() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "\n${c_azul}── Resultado ──${c_neutro}\n"
    else
        printf "\n── Resultado ──\n"
    fi
    printf "  total_aprobados: %d\n" "$total_aprobados"
    printf "  total_fallidos: %d\n" "$total_fallidos"
    printf "  total_reconocidos: %d\n" "$total_reconocidos"
}

validar_path_relativo() {
    local ruta="$1"

    if [[ -z "$ruta" ]]; then
        imprimir_error_entrada "path relativo vacío"
        return 1
    fi

    if [[ "$ruta" == /* ]]; then
        imprimir_error_entrada "path absoluto no permitido: $ruta"
        return 1
    fi

    if [[ "$ruta" == ~* ]]; then
        imprimir_error_entrada "path con ~ no permitido: $ruta"
        return 1
    fi

    if [[ "$ruta" == *" "* ]]; then
        imprimir_error_entrada "path con espacios no permitido: $ruta"
        return 1
    fi

    local segmento
    local IFS='/'
    for segmento in $ruta; do
        if [[ -z "$segmento" ]]; then
            imprimir_error_entrada "path con segmentos vacíos: $ruta"
            return 1
        fi
        if [[ "$segmento" == ".." ]]; then
            imprimir_error_entrada "path con traversal '..': $ruta"
            return 1
        fi
    done

    return 0
}

verificar_archivo() {
    local ruta="$1"
    local spec="$2"

    if [[ -z "$ruta" ]]; then
        imprimir_linea_resultado "fail" "$spec" "archivo: (claim malformado: falta path)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    if ! validar_path_relativo "$ruta"; then
        imprimir_linea_resultado "fail" "$spec" "archivo: $ruta (claim malformado: path inválido)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    local destino="$RAIZ_REPOSITORIO/$ruta"

    if [[ ! -e "$destino" ]]; then
        imprimir_linea_resultado "fail" "$spec" "archivo: $ruta (no existe)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    if [[ ! -f "$destino" ]]; then
        imprimir_linea_resultado "fail" "$spec" "archivo: $ruta (existe pero no es archivo regular)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    imprimir_linea_resultado "ok" "$spec" "archivo: $ruta"
    total_aprobados=$((total_aprobados + 1))
    return 0
}

verificar_count() {
    local linea="$1"
    local spec="$2"
    local patron='^([0-9]+) (.+) en (.+)$'
    local sin_prefijo="${linea#- count: }"

    if [[ ! "$sin_prefijo" =~ $patron ]]; then
        imprimir_linea_resultado "fail" "$spec" "count: $sin_prefijo (claim malformado)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    local esperado="${BASH_REMATCH[1]}"
    local directorio="${BASH_REMATCH[3]}"

    if ! validar_path_relativo "$directorio"; then
        imprimir_linea_resultado "fail" "$spec" "count: $linea (path inválido)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    local observado
    observado="$(contar_archivos "$RAIZ_REPOSITORIO/$directorio")"

    if [[ "$esperado" == "$observado" ]]; then
        imprimir_linea_resultado "ok" "$spec" "count: $esperado en $directorio"
        total_aprobados=$((total_aprobados + 1))
        return 0
    fi

    imprimir_linea_resultado "fail" "$spec" "count: $esperado en $directorio (esperado $esperado, observado $observado)"
    total_fallidos=$((total_fallidos + 1))
    return 1
}

contar_archivos() {
    local directorio="$1"

    if [[ ! -d "$directorio" ]]; then
        imprimir_error_entrada "directorio no existe: $directorio"
        printf '0\n'
        return 0
    fi

    find "$directorio" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' '
    return 0
}

verificar_contiene() {
    local linea="$1"
    local spec="$2"
    local patron='^"([^"]+)" en (.+)$'
    local sin_prefijo="${linea#- contiene: }"

    if [[ ! "$sin_prefijo" =~ $patron ]]; then
        imprimir_linea_resultado "fail" "$spec" "contiene: $sin_prefijo (claim malformado)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    local texto="${BASH_REMATCH[1]}"
    local archivo="${BASH_REMATCH[2]}"

    if ! validar_path_relativo "$archivo"; then
        imprimir_linea_resultado "fail" "$spec" "contiene: $linea (path inválido)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    if ! archivo_contiene "$texto" "$RAIZ_REPOSITORIO/$archivo"; then
        imprimir_linea_resultado "fail" "$spec" "contiene: \"$texto\" en $archivo (no encontrado)"
        total_fallidos=$((total_fallidos + 1))
        return 1
    fi

    imprimir_linea_resultado "ok" "$spec" "contiene: \"$texto\" en $archivo"
    total_aprobados=$((total_aprobados + 1))
    return 0
}

archivo_contiene() {
    local texto="$1"
    local archivo="$2"

    if [[ ! -f "$archivo" ]]; then
        return 1
    fi

    grep -Fq -- "$texto" "$archivo" 2>/dev/null
    return $?
}

verificar_claim() {
    local linea="$1"
    local spec="$2"

    case "$linea" in
        "- archivo:"*)
            total_reconocidos=$((total_reconocidos + 1))
            local ruta="${linea#- archivo: }"
            verificar_archivo "$ruta" "$spec"
            ;;
        "- count:"*)
            total_reconocidos=$((total_reconocidos + 1))
            verificar_count "$linea" "$spec"
            ;;
        "- contiene:"*)
            total_reconocidos=$((total_reconocidos + 1))
            verificar_contiene "$linea" "$spec"
            ;;
        *)
            ;;
    esac
}

principal() {
    activar_color
    validar_argv "$@"

    local plan="$1"
    local plan_absoluto
    plan_absoluto="$(cd "$plan" && pwd)"

    total_aprobados=0
    total_fallidos=0
    total_reconocidos=0

    while IFS= read -r spec; do
        [[ -z "$spec" ]] && continue
        while IFS= read -r linea; do
            verificar_claim "$linea" "$spec" || true
        done < <(extraer_bloque_verificacion "$spec")
    done < <(listar_specs "$plan_absoluto")

    if [[ "$total_reconocidos" -eq 0 ]]; then
        imprimir_error_entrada "Ninguna spec contiene claims válidos bajo '## Verificación'"
        exit 1
    fi

    imprimir_resumen

    if [[ "$total_fallidos" -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    uso
fi

principal "$@"
