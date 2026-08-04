#!/usr/bin/env bash
set -euo pipefail

DIRECTORIO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ_REPOSITORIO="$(cd "$DIRECTORIO_SCRIPT/.." && pwd)"

c_verde='\033[32m'
c_rojo='\033[31m'
c_azul='\033[36m'
c_neutro='\033[0m'
MODO_COLOR=0

uso() {
    cat <<TEXTO
Uso: bash spec-memory-link.sh <origen> <destino>

Argumentos:
  <origen>     Directorio del plan a archivar (con proposal.md, design.md,
               tasks.md o specs/).
  <destino>    Path final post-archivado, formato
               .opencode/changes/archive/<YYYY-MM>/<slug>/.

Ejemplo:
  bash scripts/spec-memory-link.sh \\
      .opencode/changes/spec-memory-link \\
      .opencode/changes/archive/2026-08/spec-memory-link
TEXTO
    exit 0
}

activar_color() {
    if [[ -t 1 && -t 2 ]]; then
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

imprimir_aplicado() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "${c_verde}aplicado:${c_neutro} %s\n" "$*"
    else
        printf "aplicado: %s\n" "$*"
    fi
}

imprimir_preservado() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "${c_azul}preservado:${c_neutro} %s\n" "$*"
    else
        printf "preservado: %s\n" "$*"
    fi
}

imprimir_error() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "${c_rojo}error:${c_neutro} %s\n" "$*" >&2
    else
        printf "error: %s\n" "$*" >&2
    fi
}

validar_argv() {
    if [[ $# -lt 2 ]]; then
        imprimir_error_entrada "Faltan argumentos. Uso: bash spec-memory-link.sh <origen> <destino>"
        exit 2
    fi
    if [[ $# -gt 2 ]]; then
        imprimir_error_entrada "Se esperaban 2 argumentos (se recibieron $#): bash spec-memory-link.sh <origen> <destino>"
        exit 2
    fi
    if [[ ! -d "$1" ]]; then
        imprimir_error_entrada "$1 no existe o no es directorio (argumento <origen>)"
        exit 2
    fi
    if [[ ! -d "$2" ]]; then
        imprimir_error_entrada "$2 no existe o no es directorio (argumento <destino>)"
        exit 2
    fi
    local tiene_archivos="false"
    [[ -f "$1/proposal.md" || -f "$1/design.md" || -f "$1/tasks.md" || -d "$1/specs" ]] && tiene_archivos="true"
    if [[ "$tiene_archivos" == "false" ]]; then
        imprimir_error_entrada "$1 no contiene proposal.md, design.md, tasks.md ni specs/ (ningún archivo escaneable)"
        exit 2
    fi
}

detectar_archivos_escaneables() {
    local directorio="$1"
    local archivos=""

    if [[ -f "$directorio/proposal.md" ]]; then
        archivos+="$directorio/proposal.md"
        archivos+=$'\n'
    fi
    if [[ -f "$directorio/design.md" ]]; then
        archivos+="$directorio/design.md"
        archivos+=$'\n'
    fi
    if [[ -f "$directorio/tasks.md" ]]; then
        archivos+="$directorio/tasks.md"
        archivos+=$'\n'
    fi
    if [[ -d "$directorio/specs" ]]; then
        local specs
        specs="$(find "$directorio/specs" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort || true)"
        if [[ -n "$specs" ]]; then
            archivos+="$specs"
            archivos+=$'\n'
        fi
    fi

    printf '%s' "$archivos" | sed '/^$/d'
}

extraer_matches() {
    local archivo="$1"
    [[ ! -f "$archivo" ]] && return 0
    grep -Eo '\.opencode/context/concept/[A-Za-z0-9._-]+\.md' "$archivo" 2>/dev/null | sed 's|^/||' || true
}

filtrar_matches_invalidos() {
    grep -vF '..' | grep -v ' ' | grep -v '/\.md$' || true
}

validar_path_concept() {
    local match="$1"
    local archivo_origen="${2:-}"
    local regex='^\.opencode/context/concept/[A-Za-z0-9._-]+\.md$'

    if [[ ! "$match" =~ $regex ]]; then
        imprimir_advertencia "match descartado por regex: $match"
        return 1
    fi
    if [[ ! -f "$RAIZ_REPOSITORIO/$match" ]]; then
        if [[ -n "$archivo_origen" ]]; then
            imprimir_advertencia "referencia a concept doc inexistente: $match (en $archivo_origen)"
        else
            imprimir_advertencia "referencia a concept doc inexistente: $match"
        fi
        return 1
    fi
    return 0
}

detectar_concept_docs() {
    local directorio="$1"
    local archivos
    archivos="$(detectar_archivos_escaneables "$directorio")"

    local todos_matches=""
    local archivo
    while IFS= read -r archivo; do
        [[ -z "$archivo" ]] && continue
        local matches_archivo
        matches_archivo="$(extraer_matches "$archivo")"
        if [[ -n "$matches_archivo" ]]; then
            todos_matches+="$matches_archivo"$'\n'
        fi
    done <<< "$archivos"

    local filtrados=""
    if [[ -n "$todos_matches" ]]; then
        filtrados="$(printf '%s' "$todos_matches" | filtrar_matches_invalidos | sort -u || true)"
    fi

    [[ -z "$filtrados" ]] && return 0

    local validos=""
    local match
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        if validar_path_concept "$match" "$directorio"; then
            validos+="$match"$'\n'
        fi
    done <<< "$filtrados"

    if [[ -n "$validos" ]]; then
        printf '%s' "$validos" | sed '/^$/d'
    fi
}

calcular_path_relativo() {
    local destino="$1"
    local destino_normalizado="${destino%/}"

    local segmentos_destino
    IFS='/' read -ra segmentos_destino <<< "$destino_normalizado"
    local total=${#segmentos_destino[@]}
    local slug="${segmentos_destino[$((total - 1))]:-}"
    local yyyymm="${segmentos_destino[$((total - 2))]:-}"

    if [[ -z "$slug" || "$slug" = "." || "$slug" = ".." ]]; then
        slug="$(basename "$destino_normalizado")"
    fi
    if [[ -z "$yyyymm" || ! "$yyyymm" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
        yyyymm="$(basename "$(dirname "$destino_normalizado")")"
    fi

    printf '../../changes/archive/%s/%s/\n' "$yyyymm" "$slug"
}

validar_footer_existente() {
    local concept_doc="$1"
    [[ ! -f "$concept_doc" ]] && return 1
    grep -q -E '^## Spec original[[:space:]]*$' "$concept_doc"
}

validar_escribible() {
    local concept_doc="$1"
    if [[ ! -f "$concept_doc" ]]; then
        return 1
    fi
    if [[ ! -s "$concept_doc" ]]; then
        return 1
    fi
    if [[ ! -w "$concept_doc" ]]; then
        return 1
    fi
    return 0
}

aplicar_footer_a_concept_doc() {
    local concept_doc="$1"
    local path_relativo="$2"
    local tmp_bloque tmp_destino

    tmp_bloque="$(mktemp 2>/dev/null || true)"
    if [[ -z "$tmp_bloque" ]]; then
        return 1
    fi

    if ! printf '\n%s\n\n[%s](%s)\n' '## Spec original' "$path_relativo" "$path_relativo" > "$tmp_bloque"; then
        rm -f "$tmp_bloque"
        return 1
    fi

    tmp_destino="$(mktemp "${concept_doc}.tmp.XXXXXX" 2>/dev/null || true)"
    if [[ -z "$tmp_destino" ]]; then
        rm -f "$tmp_bloque"
        return 1
    fi

    if ! cat "$concept_doc" "$tmp_bloque" > "$tmp_destino"; then
        rm -f "$tmp_bloque" "$tmp_destino"
        return 1
    fi

    if ! mv "$tmp_destino" "$concept_doc"; then
        rm -f "$tmp_bloque" "$tmp_destino"
        return 1
    fi

    rm -f "$tmp_bloque"
    return 0
}

total_aplicados=0
total_preservados=0
total_errores=0

procesar_concept_doc() {
    local concept_doc="$1"
    local path_relativo="$2"

    if validar_footer_existente "$concept_doc"; then
        imprimir_preservado "$concept_doc (ya enlazado)"
        total_preservados=$((total_preservados + 1))
        return 0
    fi

    if [[ ! -s "$concept_doc" ]]; then
        imprimir_error "concept doc vacío: $concept_doc"
        total_errores=$((total_errores + 1))
        return 1
    fi
    if [[ ! -w "$concept_doc" ]]; then
        imprimir_error "no se puede escribir $concept_doc"
        total_errores=$((total_errores + 1))
        return 1
    fi

    if aplicar_footer_a_concept_doc "$concept_doc" "$path_relativo"; then
        imprimir_aplicado "$concept_doc"
        total_aplicados=$((total_aplicados + 1))
        return 0
    fi

    imprimir_error "falló la aplicación del footer en $concept_doc"
    total_errores=$((total_errores + 1))
    return 1
}

imprimir_resumen() {
    if [[ "$MODO_COLOR" -eq 1 ]]; then
        printf "\n${c_azul}── Resumen ──${c_neutro}\n"
    else
        printf "\n── Resumen ──\n"
    fi
    printf "  aplicados: %d\n" "$total_aplicados"
    printf "  preservados: %d\n" "$total_preservados"
    printf "  errores: %d\n" "$total_errores"
}

principal() {
    activar_color
    validar_argv "$@"

    local origen="$1"
    local destino="$2"

    set +e
    local lista
    lista="$(detectar_concept_docs "$origen")"
    set -e

    if [[ -z "$lista" ]]; then
        printf "spec-memory-link: 0 concept docs afectados por este plan\n"
        exit 0
    fi

    local path_relativo
    path_relativo="$(calcular_path_relativo "$destino")"

    total_aplicados=0
    total_preservados=0
    total_errores=0

    local match
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local concept_doc="$RAIZ_REPOSITORIO/$match"
        set +e
        procesar_concept_doc "$concept_doc" "$path_relativo"
        set -e
    done <<< "$lista"

    imprimir_resumen

    if [[ "$total_errores" -gt 0 && "$total_aplicados" -eq 0 && "$total_preservados" -eq 0 ]]; then
        exit 1
    fi

    exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    uso
fi

principal "$@"