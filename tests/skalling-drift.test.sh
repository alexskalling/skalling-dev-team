#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/skalling-drift.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

PASS=0
FAIL=0
FAILED=()

c_verde='\033[32m'
c_rojo='\033[31m'
c_azul='\033[36m'
c_neutro='\033[0m'

pass() { PASS=$((PASS+1)); printf "  ${c_verde}✓${c_neutro} %s\n" "$*"; }
fail() { FAIL=$((FAIL+1)); FAILED+=("$*"); printf "  ${c_rojo}✗${c_neutro} %s\n" "$*" >&2; }
log()  { if [[ "$VERBOSE" == true ]]; then printf "    %s\n" "$*"; fi; }

VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift ;;
        *) echo "Arg desconocido: $1"; exit 1 ;;
    esac
done

afirmar_archivo_existe() {
    if [[ -f "$1" ]]; then
        pass "$2"
    else
        fail "$2 — archivo no existe: $1"
    fi
}

afirmar_sintaxis_ok() {
    set +e
    bash -n "$1" >/dev/null 2>&1
    local estado=$?
    set -e
    if [[ "$estado" -eq 0 ]]; then
        pass "$2"
    else
        fail "$2 — bash -n reporta error de sintaxis en $1"
    fi
}

afirmar_exit_code() {
    set +e
    OUTPUT="$(bash "$SCRIPT" "$1" 2>&1)"
    local estado=$?
    set -e
    if [[ "$estado" -eq "$2" ]]; then
        pass "exit $2: $3"
    else
        fail "exit esperado $2, obtuvo $estado: $3"
        log "Output: $OUTPUT"
    fi
}

afirmar_exit_code_fixture() {
    local plan_slug="$1"
    local esperado="$2"
    local desc="$3"
    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/$plan_slug" 2>&1)"
    local estado=$?
    set -e
    if [[ "$estado" -eq "$esperado" ]]; then
        pass "exit $esperado: $desc"
    else
        fail "exit esperado $esperado, obtuvo $estado: $desc"
        log "Output: $OUTPUT"
    fi
}

afirmar_output_contiene() {
    if [[ "$OUTPUT" == *"$1"* ]]; then
        pass "$2"
    else
        fail "$2 — output no contiene '$1'"
        log "Output: $OUTPUT"
    fi
}

preparar_fixture() {
    local plan_slug="$1"
    local plan_dir="$FIXTURE/.opencode/changes/archive/2026-08/$plan_slug"
    rm -rf "$plan_dir"
    rm -rf "$FIXTURE/agents-base"
    mkdir -p "$plan_dir/specs"
    mkdir -p "$FIXTURE/agents-base"
    mkdir -p "$FIXTURE/scripts"
    cp "$SCRIPT" "$FIXTURE/scripts/skalling-drift.sh"
}

preparar_spec() {
    local plan_slug="$1"
    local spec_name="$2"
    local contenido="$3"
    local spec_dir="$FIXTURE/.opencode/changes/archive/2026-08/$plan_slug/specs"
    mkdir -p "$spec_dir"
    printf '%s\n' "$contenido" > "$spec_dir/$spec_name"
}

echo "═══════════════════════════════════════════════════"
echo "  Skalling Drift Detection Tests"
echo "═══════════════════════════════════════════════════"

test_estructura_script() {
    echo ""
    echo "── Test 1.1: Estructura del script ──"

    afirmar_archivo_existe "$SCRIPT" "scripts/skalling-drift.sh existe"
    afirmar_sintaxis_ok "$SCRIPT" "bash -n pasa en scripts/skalling-drift.sh"
}

test_argv_invalido() {
    echo ""
    echo "── Test 1.2: argv inválido retorna exit 1 ──"

    afirmar_exit_code "" "1" "sin argumentos → exit 1"
    afirmar_exit_code "arg1 arg2" "1" "dos argumentos → exit 1"
    afirmar_exit_code "/path/que/no/existe" "1" "path inexistente → exit 1"
}

test_estructura_script
test_argv_invalido

test_bloque_no_detectado_subheading() {
    echo ""
    echo "── Test 1.3a: '### Verificación' (subheading) NO abre bloque ──"

    preparar_fixture "subheading"
    preparar_spec "subheading" "01-foo.md" "$(cat <<'MD'
# Spec foo

### Verificación

- archivo: agents-base/Alex.md

## Otra sección

texto narrativo
MD
)"

    afirmar_exit_code_fixture "subheading" "1" "subheading no se detecta como bloque"
}

test_bloque_ausente() {
    echo ""
    echo "── Test 1.3b: spec sin '## Verificación' no genera claims ──"

    preparar_fixture "sin-bloque"
    preparar_spec "sin-bloque" "01-foo.md" "$(cat <<'MD'
# Spec foo

Esta spec no tiene bloque de verificación.

## Cambios

- se cambió X
MD
)"

    afirmar_exit_code_fixture "sin-bloque" "1" "spec sin bloque → exit 1"
}

test_bloque_no_detectado_subheading
test_bloque_ausente

test_happy_path_un_archivo() {
    echo ""
    echo "── Test 1.5: Happy path con 1 spec + 1 claim archivo ──"

    preparar_fixture "happy-path"
    printf '# Alex\n\nSINCRONIZADO CON: foo\n' > "$FIXTURE/agents-base/Alex.md"
    preparar_spec "happy-path" "spec-unica.md" "$(cat <<'MD'
# Spec única

## Verificación

- archivo: agents-base/Alex.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/happy-path" 2>&1)"
    local estado_existente=$?
    set -e

    if [[ "$estado_existente" -eq 0 ]]; then
        pass "exit 0 cuando el archivo referenciado existe"
    else
        fail "exit esperado 0 con archivo existente, obtuvo $estado_existente"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"PASS"* || "$OUTPUT" == *"✓"* ]]; then
        pass "output reporta PASS para el archivo verificado"
    else
        fail "output no contiene PASS ni marca de aprobado"
        log "Output: $OUTPUT"
    fi

    rm -f "$FIXTURE/agents-base/Alex.md"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/happy-path" 2>&1)"
    local estado_ausente=$?
    set -e

    if [[ "$estado_ausente" -eq 1 ]]; then
        pass "exit 1 cuando el archivo referenciado no existe"
    else
        fail "exit esperado 1 con archivo ausente, obtuvo $estado_ausente"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para el archivo ausente"
    else
        fail "output no contiene FAIL ni marca de fallo"
        log "Output: $OUTPUT"
    fi
}

test_happy_path_un_archivo

test_validar_path_relativo_rechaza_invalidos() {
    echo ""
    echo "── Test 2.1: validar_path_relativo rechaza paths inválidos ──"

    preparar_fixture "path-invalido"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "path-invalido" "01-traversal.md" "$(cat <<'MD'
# Spec traversal

## Verificación

- archivo: ../escape.md
MD
)"
    preparar_spec "path-invalido" "02-absoluto.md" "$(cat <<'MD'
# Spec absoluto

## Verificación

- archivo: /etc/passwd
MD
)"
    preparar_spec "path-invalido" "03-home.md" "$(cat <<'MD'
# Spec home

## Verificación

- archivo: ~/secreto.md
MD
)"
    preparar_spec "path-invalido" "04-espacios.md" "$(cat <<'MD'
# Spec espacios

## Verificación

- archivo: con espacios/foo.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/path-invalido" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando hay paths inválidos"
    else
        fail "exit esperado 1 con paths inválidos, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"path inválido"* || "$OUTPUT" == *"path relativo inválido"* || "$OUTPUT" == *"inválido"* ]]; then
        pass "stderr/output menciona path inválido"
    else
        fail "no se reporta mensaje de path inválido"
        log "Output: $OUTPUT"
    fi
}

test_validar_path_relativo_acepta_validos() {
    echo ""
    echo "── Test 2.1b: validar_path_relativo acepta paths válidos ──"

    preparar_fixture "path-valido"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    mkdir -p "$FIXTURE/scripts/sub"
    printf '# Sub\n' > "$FIXTURE/scripts/sub/foo.md"

    preparar_spec "path-valido" "01-valido.md" "$(cat <<'MD'
# Spec valido

## Verificación

- archivo: agents-base/Alex.md
- archivo: scripts/sub/foo.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/path-valido" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "exit 0 con paths válidos (segments anidados, puntos, guiones)"
    else
        fail "exit esperado 0 con paths válidos, obtuvo $estado"
        log "Output: $OUTPUT"
    fi
}

test_validar_path_relativo_rechaza_invalidos
test_validar_path_relativo_acepta_validos

test_archivo_existe_es_pass() {
    echo ""
    echo "── Test 2.2a: archivo: con archivo existente → PASS ──"

    preparar_fixture "archivo-pasa"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "archivo-pasa" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: agents-base/Alex.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/archivo-pasa" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "exit 0 con archivo existente"
    else
        fail "exit esperado 0 con archivo existente, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"PASS"* || "$OUTPUT" == *"✓"* ]]; then
        pass "output reporta PASS"
    else
        fail "output no contiene PASS"
        log "Output: $OUTPUT"
    fi
}

test_archivo_directorio_es_fail() {
    echo ""
    echo "── Test 2.2b: archivo: con directorio en lugar de archivo → FAIL ──"

    preparar_fixture "archivo-dir"
    mkdir -p "$FIXTURE/agents-base"

    preparar_spec "archivo-dir" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/archivo-dir" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando path apunta a directorio"
    else
        fail "exit esperado 1 con directorio, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para directorio"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi
}

test_archivo_ausente_es_fail() {
    echo ""
    echo "── Test 2.2c: archivo: con archivo inexistente → FAIL ──"

    preparar_fixture "archivo-ausente"

    preparar_spec "archivo-ausente" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: agents-base/missing.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/archivo-ausente" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando archivo no existe"
    else
        fail "exit esperado 1 con archivo ausente, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para archivo ausente"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi
}

test_archivo_existe_es_pass
test_archivo_directorio_es_fail
test_archivo_ausente_es_fail

test_contar_archivos_match() {
    echo ""
    echo "── Test 2.3/2.4a: count coincide con archivos reales → PASS ──"

    preparar_fixture "count-match"
    mkdir -p "$FIXTURE/agents-base"
    printf '# a\n' > "$FIXTURE/agents-base/Alex.md"
    printf '# b\n' > "$FIXTURE/agents-base/Bruno.md"
    printf '# c\n' > "$FIXTURE/agents-base/Caro.md"

    preparar_spec "count-match" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- count: 3 agentes en agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/count-match" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "exit 0 cuando count coincide"
    else
        fail "exit esperado 0 con count coincidente, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"PASS"* || "$OUTPUT" == *"✓"* ]]; then
        pass "output reporta PASS para count correcto"
    else
        fail "output no contiene PASS"
        log "Output: $OUTPUT"
    fi
}

test_contar_archivos_incluye_ocultos() {
    echo ""
    echo "── Test 2.3b: count incluye archivos ocultos (ADR-007) ──"

    preparar_fixture "count-ocultos"
    mkdir -p "$FIXTURE/agents-base"
    printf '# a\n' > "$FIXTURE/agents-base/Alex.md"
    printf '# b\n' > "$FIXTURE/agents-base/Bruno.md"
    printf 'cache\n' > "$FIXTURE/agents-base/.DS_Store"

    preparar_spec "count-ocultos" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- count: 3 archivos en agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/count-ocultos" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "exit 0: archivos ocultos cuentan (3 = 2 visibles + .DS_Store)"
    else
        fail "exit esperado 0 contando ocultos, obtuvo $estado"
        log "Output: $OUTPUT"
    fi
}

test_contar_archivos_directorio_vacio() {
    echo ""
    echo "── Test 2.3c: count = 0 con directorio vacío → PASS ──"

    preparar_fixture "count-cero"
    mkdir -p "$FIXTURE/agents-base"

    preparar_spec "count-cero" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- count: 0 archivos en agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/count-cero" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "exit 0 con directorio vacío y count 0"
    else
        fail "exit esperado 0 con count 0, obtuvo $estado"
        log "Output: $OUTPUT"
    fi
}

test_contar_archivos_directorio_inexistente() {
    echo ""
    echo "── Test 2.3d: count sobre directorio inexistente → FAIL ──"

    preparar_fixture "count-inexistente"

    preparar_spec "count-inexistente" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- count: 5 archivos en agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/count-inexistente" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando directorio no existe"
    else
        fail "exit esperado 1 con directorio inexistente, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para directorio inexistente"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi
}

test_contar_archivos_mismatch() {
    echo ""
    echo "── Test 2.4: count mismatch → FAIL con esperado y observado ──"

    preparar_fixture "count-mismatch"
    mkdir -p "$FIXTURE/agents-base"
    printf '# a\n' > "$FIXTURE/agents-base/Alex.md"
    printf '# b\n' > "$FIXTURE/agents-base/Bruno.md"

    preparar_spec "count-mismatch" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- count: 8 agentes en agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/count-mismatch" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando count no coincide"
    else
        fail "exit esperado 1 con count incorrecto, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"8"* && "$OUTPUT" == *"2"* ]]; then
        pass "output muestra esperado (8) y observado (2)"
    else
        fail "output no muestra esperado y observado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para count incorrecto"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi
}

test_contar_archivos_match
test_contar_archivos_incluye_ocultos
test_contar_archivos_directorio_vacio
test_contar_archivos_directorio_inexistente
test_contar_archivos_mismatch

test_contiene_presente_es_pass() {
    echo ""
    echo "── Test 2.5/2.6a: contiene: texto presente → PASS ──"

    preparar_fixture "contiene-pasa"
    printf '# Alex\n\nSINCRONIZADO CON: foo\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "contiene-pasa" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- contiene: "SINCRONIZADO CON:" en agents-base/Alex.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/contiene-pasa" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "exit 0 cuando texto está presente"
    else
        fail "exit esperado 0 con texto presente, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"PASS"* || "$OUTPUT" == *"✓"* ]]; then
        pass "output reporta PASS"
    else
        fail "output no contiene PASS"
        log "Output: $OUTPUT"
    fi
}

test_contiene_texto_ausente_es_fail() {
    echo ""
    echo "── Test 2.5/2.6b: contiene: texto ausente → FAIL ──"

    preparar_fixture "contiene-ausente"
    printf '# Alex\n\nSINCRONIZADO CON: foo\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "contiene-ausente" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- contiene: "ESTO NO EXISTE" en agents-base/Alex.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/contiene-ausente" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando texto está ausente"
    else
        fail "exit esperado 1 con texto ausente, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para texto ausente"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi
}

test_contiene_archivo_ausente_es_fail() {
    echo ""
    echo "── Test 2.5/2.6c: contiene: archivo ausente → FAIL ──"

    preparar_fixture "contiene-archivo-ausente"

    preparar_spec "contiene-archivo-ausente" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- contiene: "SINCRONIZADO CON:" en agents-base/Alex.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/contiene-archivo-ausente" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando archivo de contiene no existe"
    else
        fail "exit esperado 1 con archivo ausente, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para archivo ausente"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi
}

test_contiene_literal_con_caracteres_especiales() {
    echo ""
    echo "── Test 2.5/2.6d: contiene: trata '*' como literal, no regex ──"

    preparar_fixture "contiene-literal"
    printf 'literal: a*b\n' > "$FIXTURE/agents-base/foo.md"

    preparar_spec "contiene-literal" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- contiene: "a*b" en agents-base/foo.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/contiene-literal" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "exit 0: '*' se trata literal (no regex)"
    else
        fail "exit esperado 0 con '*' literal, obtuvo $estado"
        log "Output: $OUTPUT"
    fi
}

test_contiene_presente_es_pass
test_contiene_texto_ausente_es_fail
test_contiene_archivo_ausente_es_fail
test_contiene_literal_con_caracteres_especiales

test_dispatch_archivo_sin_path_es_malformado() {
    echo ""
    echo "── Test 2.7a: archivo: sin path → malformado, FAIL, reconocido ──"

    preparar_fixture "malformado-archivo"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "malformado-archivo" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo:
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/malformado-archivo" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 con archivo: malformado"
    else
        fail "exit esperado 1 con malformado, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output reporta FAIL para malformado"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"malformado"* ]]; then
        pass "output identifica el malformado"
    else
        fail "output no menciona 'malformado'"
        log "Output: $OUTPUT"
    fi
}

test_dispatch_count_palabra_es_malformado() {
    echo ""
    echo "── Test 2.7b: count: con palabra en vez de número → malformado, FAIL ──"

    preparar_fixture "malformado-count"
    mkdir -p "$FIXTURE/agents-base"
    printf '# a\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "malformado-count" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- count: ocho en agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/malformado-count" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 con count: malformado"
    else
        fail "exit esperado 1 con malformado, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"malformado"* ]]; then
        pass "output identifica el malformado"
    else
        fail "output no menciona 'malformado'"
        log "Output: $OUTPUT"
    fi
}

test_dispatch_contiene_sin_archivo_es_malformado() {
    echo ""
    echo "── Test 2.7c: contiene: sin archivo → malformado, FAIL ──"

    preparar_fixture "malformado-contiene"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "malformado-contiene" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- contiene: "texto" en
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/malformado-contiene" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 con contiene: malformado"
    else
        fail "exit esperado 1 con malformado, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"malformado"* ]]; then
        pass "output identifica el malformado"
    else
        fail "output no menciona 'malformado'"
        log "Output: $OUTPUT"
    fi
}

test_dispatch_mezcla_reconocidos_y_malformados() {
    echo ""
    echo "── Test 2.7d: 1 malformado no enmascara 1 reconocido → ambos se reportan ──"

    preparar_fixture "mezcla-malformados"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "mezcla-malformados" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: agents-base/Alex.md
- archivo:
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/mezcla-malformados" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando hay malformado junto a reconocido"
    else
        fail "exit esperado 1, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"PASS"* || "$OUTPUT" == *"✓"* ]]; then
        pass "el reconocido se reporta como PASS"
    else
        fail "el reconocido no se reporta como PASS"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "el malformado se reporta como FAIL"
    else
        fail "el malformado no se reporta como FAIL"
        log "Output: $OUTPUT"
    fi
}

test_dispatch_archivo_sin_path_es_malformado
test_dispatch_count_palabra_es_malformado
test_dispatch_contiene_sin_archivo_es_malformado
test_dispatch_mezcla_reconocidos_y_malformados

test_drift_mixto() {
    echo ""
    echo "── Test 2.8: drift mixto (PASS + FAIL) en 4 specs ──"

    preparar_fixture "drift-mixto"
    mkdir -p "$FIXTURE/agents-base"
    printf '# a\n' > "$FIXTURE/agents-base/Alex.md"
    printf '# b\n' > "$FIXTURE/agents-base/Bruno.md"
    printf '# c\n' > "$FIXTURE/agents-base/Caro.md"

    preparar_spec "drift-mixto" "01-archivo-pasa.md" "$(cat <<'MD'
# Spec 1

## Verificación

- archivo: agents-base/Alex.md
MD
)"
    preparar_spec "drift-mixto" "02-archivo-falla.md" "$(cat <<'MD'
# Spec 2

## Verificación

- archivo: agents-base/Inexistente.md
MD
)"
    preparar_spec "drift-mixto" "03-count-pasa.md" "$(cat <<'MD'
# Spec 3

## Verificación

- count: 3 agentes en agents-base
MD
)"
    preparar_spec "drift-mixto" "04-count-falla.md" "$(cat <<'MD'
# Spec 4

## Verificación

- count: 99 agentes en agents-base
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/drift-mixto" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando hay drift mixto"
    else
        fail "exit esperado 1 con drift mixto, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    local cuenta_pass
    cuenta_pass=$(printf '%s\n' "$OUTPUT" | grep -cE '✓|PASS' || true)
    local cuenta_fail
    cuenta_fail=$(printf '%s\n' "$OUTPUT" | grep -cE '✗|FAIL' || true)

    if [[ "$cuenta_pass" -ge 2 ]]; then
        pass "se reportan múltiples PASS ($cuenta_pass)"
    else
        fail "se esperaban al menos 2 PASS, obtuvo $cuenta_pass"
        log "Output: $OUTPUT"
    fi

    if [[ "$cuenta_fail" -ge 2 ]]; then
        pass "se reportan múltiples FAIL ($cuenta_fail)"
    else
        fail "se esperaban al menos 2 FAIL, obtuvo $cuenta_fail"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"PASS"* || "$OUTPUT" == *"✓"* ]]; then
        pass "output contiene marca de PASS"
    else
        fail "output no contiene PASS"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"FAIL"* || "$OUTPUT" == *"✗"* ]]; then
        pass "output contiene marca de FAIL"
    else
        fail "output no contiene FAIL"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"01-archivo-pasa.md"* && "$OUTPUT" == *"04-count-falla.md"* ]]; then
        pass "se procesaron todas las specs (no paró en el primer FAIL)"
    else
        fail "no aparecen las 4 specs en el output"
        log "Output: $OUTPUT"
    fi
}

test_drift_mixto

test_mensaje_sin_args() {
    echo ""
    echo "── Test 3.1a: sin args → mensaje accionable exacto ──"

    set +e
    OUTPUT="$(bash "$SCRIPT" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 al invocar sin argumentos"
    else
        fail "exit esperado 1, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"Falta el argumento <plan>"* ]]; then
        pass "mensaje contiene 'Falta el argumento <plan>'"
    else
        fail "mensaje no contiene 'Falta el argumento <plan>'"
        log "Output: $OUTPUT"
    fi
}

test_mensaje_plan_inexistente() {
    echo ""
    echo "── Test 3.1b: plan inexistente → mensaje accionable exacto ──"

    set +e
    OUTPUT="$(bash "$SCRIPT" "/ruta/inexistente/xyz" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando el plan no existe"
    else
        fail "exit esperado 1, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"no existe o no es directorio"* ]]; then
        pass "mensaje contiene 'no existe o no es directorio'"
    else
        fail "mensaje no contiene 'no existe o no es directorio'"
        log "Output: $OUTPUT"
    fi
}

test_mensaje_plan_sin_specs() {
    echo ""
    echo "── Test 3.1c: plan sin directorio specs/ → mensaje accionable ──"

    local plan_dir="$FIXTURE/.opencode/changes/archive/2026-08/plan-sin-specs"
    mkdir -p "$plan_dir"
    mkdir -p "$FIXTURE/scripts"
    cp "$SCRIPT" "$FIXTURE/scripts/skalling-drift.sh"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/plan-sin-specs" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando plan no contiene specs/"
    else
        fail "exit esperado 1, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"no contiene directorio specs/"* ]]; then
        pass "mensaje contiene 'no contiene directorio specs/'"
    else
        fail "mensaje no contiene 'no contiene directorio specs/'"
        log "Output: $OUTPUT"
    fi
}

test_mensaje_specs_sin_md() {
    echo ""
    echo "── Test 3.1d: specs/ sin archivos .md → mensaje accionable ──"

    local plan_dir="$FIXTURE/.opencode/changes/archive/2026-08/specs-vacias"
    mkdir -p "$plan_dir/specs"
    mkdir -p "$FIXTURE/scripts"
    cp "$SCRIPT" "$FIXTURE/scripts/skalling-drift.sh"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/specs-vacias" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando specs/ no tiene archivos .md"
    else
        fail "exit esperado 1, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"no contiene archivos .md"* ]]; then
        pass "mensaje contiene 'no contiene archivos .md'"
    else
        fail "mensaje no contiene 'no contiene archivos .md'"
        log "Output: $OUTPUT"
    fi
}

test_mensaje_cero_claims() {
    echo ""
    echo "── Test 3.1e: cero claims reconocidos → mensaje accionable ──"

    preparar_fixture "cero-claims"
    preparar_spec "cero-claims" "01-vacia.md" "$(cat <<'MD'
# Spec sin claims válidos

## Verificación

Esta sección no tiene bullets reconocibles.
Solo texto narrativo sin prefijo soportado.
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/cero-claims" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando ninguna spec tiene claims válidos"
    else
        fail "exit esperado 1, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"Ninguna spec contiene claims válidos"* ]]; then
        pass "mensaje contiene 'Ninguna spec contiene claims válidos'"
    else
        fail "mensaje no contiene 'Ninguna spec contiene claims válidos'"
        log "Output: $OUTPUT"
    fi
}

test_mensaje_sin_args
test_mensaje_plan_inexistente
test_mensaje_plan_sin_specs
test_mensaje_specs_sin_md
test_mensaje_cero_claims

test_paths_invalidos_rechazados() {
    echo ""
    echo "── Test 3.2: validar_path_relativo rechaza 5 paths problemáticos ──"

    preparar_fixture "paths-invalidos"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "paths-invalidos" "01-absoluto.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: /etc/passwd
MD
)"
    preparar_spec "paths-invalidos" "02-home.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: ~/secreto.md
MD
)"
    preparar_spec "paths-invalidos" "03-traversal-inicio.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: ../escape.md
MD
)"
    preparar_spec "paths-invalidos" "04-traversal-segmento.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: scripts/../escape.md
MD
)"
    preparar_spec "paths-invalidos" "05-espacios.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: con espacios/foo.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/paths-invalidos" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando hay paths inválidos"
    else
        fail "exit esperado 1 con paths inválidos, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"path absoluto no permitido"* ]]; then
        pass "rechaza '/etc/passwd' como path absoluto"
    else
        fail "no se reporta rechazo de path absoluto"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"path con ~ no permitido"* ]]; then
        pass "rechaza '~/secreto.md' como home expansion"
    else
        fail "no se reporta rechazo de home expansion"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"path con traversal '..'"* ]]; then
        pass "rechaza '../escape.md' como traversal"
    else
        fail "no se reporta rechazo de traversal"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"path con espacios no permitido"* ]]; then
        pass "rechaza 'con espacios/foo.md' por espacios"
    else
        fail "no se reporta rechazo por espacios"
        log "Output: $OUTPUT"
    fi
}

test_paths_invalidos_rechazados

test_claims_malformados_cobertura_total() {
    echo ""
    echo "── Test 3.3: cobertura consolidada de claims malformados ──"

    preparar_fixture "claims-malformados"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"

    preparar_spec "claims-malformados" "01-archivo-vacio.md" "$(cat <<'MD'
# Spec 1

## Verificación

- archivo:
MD
)"
    preparar_spec "claims-malformados" "02-count-palabra.md" "$(cat <<'MD'
# Spec 2

## Verificación

- count: ocho agentes en agents-base
MD
)"
    preparar_spec "claims-malformados" "03-contiene-texto-vacio.md" "$(cat <<'MD'
# Spec 3

## Verificación

- contiene: "" en agents-base/Alex.md
MD
)"
    preparar_spec "claims-malformados" "04-contiene-sin-archivo.md" "$(cat <<'MD'
# Spec 4

## Verificación

- contiene: "texto" en
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/claims-malformados" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 1 ]]; then
        pass "exit 1 cuando hay claims malformados"
    else
        fail "exit esperado 1 con malformados, obtuvo $estado"
        log "Output: $OUTPUT"
    fi

    local cuenta_malformados
    cuenta_malformados=$(printf '%s\n' "$OUTPUT" | grep -c "malformado" || true)
    if [[ "$cuenta_malformados" -ge 4 ]]; then
        pass "se identifican los 4 claims como malformados (encontrados: $cuenta_malformados)"
    else
        fail "se esperaban 4 menciones de 'malformado', obtuvo $cuenta_malformados"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"contiene: \"\" en agents-base/Alex.md (claim malformado)"* ]]; then
        pass "texto vacío en contiene: se marca como malformado"
    else
        fail "texto vacío en contiene: no se marca como malformado"
        log "Output: $OUTPUT"
    fi
}

test_claims_malformados_cobertura_total

expect_exit_1_con_stderr() {
    local regex="$1"
    local descripcion="$2"
    shift 2

    set +e
    OUTPUT="$(bash "$FIXTURE/scripts/skalling-drift.sh" "$@" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -ne 1 ]]; then
        fail "$descripcion — exit esperado 1, obtuvo $estado"
        log "Output: $OUTPUT"
        return 1
    fi

    if [[ "$OUTPUT" == *"$regex"* ]]; then
        pass "$descripcion"
    else
        fail "$descripcion — stderr no contiene '$regex'"
        log "Output: $OUTPUT"
        return 1
    fi
}

test_entradas_invalidas_bateria() {
    echo ""
    echo "── Test 3.4: Escenario 6 spec 01 — 8 errores de entrada ──"

    mkdir -p "$FIXTURE/scripts"
    cp "$SCRIPT" "$FIXTURE/scripts/skalling-drift.sh"

    expect_exit_1_con_stderr "Falta el argumento <plan>" "caso 1: sin argumentos"

    expect_exit_1_con_stderr "Se esperaba exactamente 1 argumento" "caso 2: dos argumentos" "arg1" "arg2"

    expect_exit_1_con_stderr "no existe o no es directorio" "caso 3: plan inexistente" "/ruta/inexistente/abc"

    local archivo_falso="$FIXTURE/archivo-en-lugar-de-dir.txt"
    printf 'no\n' > "$archivo_falso"
    expect_exit_1_con_stderr "no existe o no es directorio" "caso 4: path es archivo, no directorio" "$archivo_falso"

    local plan_sin_specs="$FIXTURE/.opencode/changes/archive/2026-08/aux-sin-specs"
    mkdir -p "$plan_sin_specs"
    expect_exit_1_con_stderr "no contiene directorio specs/" "caso 5: plan sin specs/" "$plan_sin_specs"

    local plan_specs_vacias="$FIXTURE/.opencode/changes/archive/2026-08/aux-specs-vacias"
    mkdir -p "$plan_specs_vacias/specs"
    expect_exit_1_con_stderr "no contiene archivos .md" "caso 6: specs/ sin .md" "$plan_specs_vacias"

    local plan_sin_claims="$FIXTURE/.opencode/changes/archive/2026-08/aux-sin-claims"
    mkdir -p "$plan_sin_claims/specs"
    cat > "$plan_sin_claims/specs/01.md" <<'MD'
# Spec sin claims

## Verificación

texto narrativo sin bullets válidos.
MD
    expect_exit_1_con_stderr "Ninguna spec contiene claims válidos" "caso 7: cero claims reconocidos" "$plan_sin_claims"

    local plan_path_absoluto="$FIXTURE/.opencode/changes/archive/2026-08/aux-path-absoluto"
    mkdir -p "$plan_path_absoluto/specs"
    mkdir -p "$FIXTURE/agents-base"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    cat > "$plan_path_absoluto/specs/01.md" <<'MD'
# Spec con path absoluto

## Verificación

- archivo: /etc/passwd
MD
    expect_exit_1_con_stderr "path absoluto no permitido" "caso 8: claim con path absoluto" "$plan_path_absoluto"
}

test_entradas_invalidas_bateria

test_colores_solo_en_tty() {
    echo ""
    echo "── Test 4.1: colores solo cuando stdout es TTY ──"

    preparar_fixture "sin-colores"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    preparar_spec "sin-colores" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: agents-base/Alex.md
MD
)"

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/sin-colores" < /dev/null 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "invocación no-TTY con stdin /dev/null mantiene exit 0"
    else
        fail "invocación no-TTY obtuvo exit $estado"
        log "Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" != *$'\033['* ]]; then
        pass "output no-TTY no contiene secuencias ANSI"
    else
        fail "output no-TTY contiene secuencias ANSI"
        log "Output: $OUTPUT"
    fi

    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/skalling-drift.sh" ".opencode/changes/archive/2026-08/sin-colores" 2>&1 | cat)"
    estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "pipeline no-TTY mantiene exit 0"
    else
        fail "pipeline no-TTY obtuvo exit $estado"
    fi

    if [[ "$OUTPUT" != *$'\033['* ]]; then
        pass "pipeline con cat no contiene secuencias ANSI"
    else
        fail "pipeline con cat contiene secuencias ANSI"
        log "Output: $OUTPUT"
    fi

    if grep -Fq '[[ -t 1 ]]' "$SCRIPT"; then
        pass "activar_color usa gating explícito [[ -t 1 ]]"
    else
        fail "activar_color no usa [[ -t 1 ]]"
    fi
}

test_limites_bloque() {
    echo ""
    echo "── Test 4.2: límites canónicos del bloque ──"

    preparar_fixture "limites-bloque"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    preparar_spec "limites-bloque" "01.md" "$(cat <<'MD'
# Spec

- archivo: agents-base/FueraAntes.md

### Verificación

- archivo: agents-base/Subheading.md

## Verificación

Texto narrativo.
- otro: ignorado
- archivo: agents-base/Alex.md

## Otra sección

- archivo: agents-base/FueraDespues.md

## Verificaciones

- archivo: agents-base/Variante.md
MD
)"

    afirmar_exit_code_fixture "limites-bloque" "0" "solo el bloque canónico aporta claims"
    afirmar_output_contiene "total_reconocidos: 1" "solo se reconoce el claim dentro del bloque"

    if [[ "$OUTPUT" == *"Alex.md"* && "$OUTPUT" != *"FueraAntes.md"* && "$OUTPUT" != *"FueraDespues.md"* && "$OUTPUT" != *"Subheading.md"* && "$OUTPUT" != *"Variante.md"* ]]; then
        pass "claims fuera del bloque y headings variantes se ignoran"
    else
        fail "se procesaron claims fuera del bloque canónico"
        log "Output: $OUTPUT"
    fi
}

test_limite_lineas_bloque() {
    echo ""
    echo "── Test 4.2b: advertencia al superar límite de líneas ──"

    preparar_fixture "bloque-extenso"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    local ruta_spec="$FIXTURE/.opencode/changes/archive/2026-08/bloque-extenso/specs/01.md"
    printf '%s\n' '# Spec' '' '## Verificación' > "$ruta_spec"
    local numero
    for numero in $(seq 1 100); do
        printf 'línea narrativa %s\n' "$numero" >> "$ruta_spec"
    done
    printf '%s\n' '- archivo: agents-base/Alex.md' >> "$ruta_spec"

    afirmar_exit_code_fixture "bloque-extenso" "0" "un bloque extenso sigue verificándose"
    afirmar_output_contiene "supera el límite de 100 líneas" "bloque de 101 líneas emite advertencia"
    afirmar_output_contiene "total_reconocidos: 1" "la advertencia no descarta claims"
    afirmar_output_contiene "total_fallidos: 0" "la advertencia no es bloqueante"

    preparar_fixture "bloque-limite"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    ruta_spec="$FIXTURE/.opencode/changes/archive/2026-08/bloque-limite/specs/01.md"
    printf '%s\n' '# Spec' '' '## Verificación' > "$ruta_spec"
    for numero in $(seq 1 99); do
        printf 'línea narrativa %s\n' "$numero" >> "$ruta_spec"
    done
    printf '%s\n' '- archivo: agents-base/Alex.md' >> "$ruta_spec"

    afirmar_exit_code_fixture "bloque-limite" "0" "bloque de exactamente 100 líneas es válido"
    if [[ "$OUTPUT" != *"supera el límite"* ]]; then
        pass "bloque en el límite no emite advertencia"
    else
        fail "bloque en el límite emitió advertencia"
        log "Output: $OUTPUT"
    fi
}

test_resumen_final() {
    echo ""
    echo "── Test 4.2c: resumen con métricas agregadas ──"

    preparar_fixture "resumen"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    preparar_spec "resumen" "01.md" "$(cat <<'MD'
# Spec

## Verificación

- archivo: agents-base/Alex.md
- archivo: agents-base/Ausente.md
MD
)"

    afirmar_exit_code_fixture "resumen" "1" "resumen mixto conserva exit 1"
    afirmar_output_contiene "── Resultado ──" "imprime título del resumen"
    afirmar_output_contiene "total_aprobados: 1" "resumen informa aprobados"
    afirmar_output_contiene "total_fallidos: 1" "resumen informa fallidos"
    afirmar_output_contiene "total_reconocidos: 2" "resumen informa reconocidos"
}

test_portabilidad_bash_3_2() {
    echo ""
    echo "── Test 4.3: portabilidad Bash 3.2 ──"

    afirmar_sintaxis_ok "$SCRIPT" "script principal pasa bash -n con Bash 3.2"
    afirmar_sintaxis_ok "$ROOT/tests/skalling-drift.test.sh" "suite pasa bash -n con Bash 3.2"

    local usos_no_portables
    local api_asociativa="declare -""A"
    local api_mapa="map""file"
    local api_lectura="read""array"
    usos_no_portables="$(grep -E "$api_asociativa|(^|[^[:alnum:]_])$api_mapa([^[:alnum:]_]|$)|(^|[^[:alnum:]_])$api_lectura([^[:alnum:]_]|$)" "$SCRIPT" "$ROOT/tests/skalling-drift.test.sh" || true)"
    if [[ -z "$usos_no_portables" ]]; then
        pass "script y tests no usan APIs exclusivas de Bash 4+"
    else
        fail "se encontraron APIs no portables"
        log "Coincidencias: $usos_no_portables"
    fi

    preparar_fixture "bash-portable"
    printf '# Alex\n' > "$FIXTURE/agents-base/Alex.md"
    preparar_spec "bash-portable" "01.md" $'## Verificación\n\n- archivo: agents-base/Alex.md'
    chmod -x "$FIXTURE/scripts/skalling-drift.sh"
    afirmar_exit_code_fixture "bash-portable" "0" "el script funciona vía bash sin bit ejecutable"
}

test_identificadores_en_espanol() {
    echo ""
    echo "── Test 4.4: auditoría R1 de identificadores ──"

    local identificadores_ingles
    identificadores_ingles="$(grep -En '(^|[[:space:]])(SCRIPT_DIR|REPO_ROOT|plan_dir|specs_dir|spec_path|main)(=|\(\))' "$SCRIPT" || true)"
    if [[ -z "$identificadores_ingles" ]]; then
        pass "grep R1 no encuentra identificadores propios en inglés"
    else
        fail "grep R1 encontró identificadores propios en inglés"
        log "Coincidencias: $identificadores_ingles"
    fi

    if grep -q '^activar_color()' "$SCRIPT" && grep -q '^imprimir_resumen()' "$SCRIPT" && grep -q '^extraer_bloque_verificacion()' "$SCRIPT"; then
        pass "helpers nuevos y existentes usan identificadores en español"
    else
        fail "faltan helpers esperados con identificadores en español"
    fi
}

test_release_y_doctor() {
    echo ""
    echo "── Test 5: versión, documentación e integración doctor ──"

    if grep -q '0.7.6' "$ROOT/VERSION"; then
        pass "VERSION declara 0.7.6"
    else
        fail "VERSION no declara 0.7.6"
    fi

    if grep -q 'SKALLING_VERSION="\$(grep' "$ROOT/setup-team-doctor.sh"; then
        pass "doctor lee SKALLING_VERSION dinámico de VERSION"
    else
        fail "doctor SKALLING_VERSION no lee de VERSION dinámicamente"
    fi

    if grep -q 'info "Drift detection disponible:' "$ROOT/setup-team-doctor.sh"; then
        pass "doctor usa info para drift detection"
    else
        fail "doctor no usa info para drift detection"
    fi

    if grep -q 'Drift detection' "$ROOT/command/skalling-doctor.md" && grep -q 'ejecución manual' "$ROOT/command/skalling-doctor.md"; then
        pass "comando doctor documenta drift detection manual"
    else
        fail "comando doctor no documenta drift detection manual"
    fi

    if grep -q '^## \[0.6.0\]' "$ROOT/CHANGELOG.md" && grep -q 'scripts/skalling-drift.sh' "$ROOT/CHANGELOG.md" && grep -q 'tests/skalling-drift.test.sh' "$ROOT/CHANGELOG.md"; then
        pass "CHANGELOG 0.6.0 cubre script y tests"
    else
        fail "CHANGELOG 0.6.0 incompleto"
    fi

    if grep -qi 'drift detection' "$ROOT/README.md" && grep -q 'scripts/skalling-drift.sh' "$ROOT/README.md"; then
        pass "README explica uso de drift detection"
    else
        fail "README no explica drift detection"
    fi

    local instancia_global="$FIXTURE/doctor-global"
    local instancia_proyecto="$FIXTURE/doctor-proyecto"
    mkdir -p "$instancia_global/agents" "$instancia_global/skills" "$instancia_global/command" "$instancia_global/templates" "$instancia_global/skalling-data" "$instancia_proyecto/.opencode"
    printf '%s\n' '# Constitución' '' '## 🏛️ Reglas Base' '' 'R13 design-system.md' > "$instancia_global/constitucion.md"
    local agente
    for agente in Alex Pol Jes Sol Teo Jhon Luz Pau; do
        if [[ "$agente" == "Alex" ]]; then
            printf '%s\n' '---' 'mode: primary' "name: $agente" '---' > "$instancia_global/agents/${agente}.md"
        else
            printf '%s\n' '---' 'mode: subagent' "name: $agente" '---' > "$instancia_global/agents/${agente}.md"
        fi
    done

    set +e
    OUTPUT="$(SKALLING_OPENCODE_DIR="$instancia_global" bash "$ROOT/setup-team-doctor.sh" --strict --project "$instancia_proyecto" 2>&1)"
    local estado=$?
    set -e

    if [[ "$estado" -eq 0 ]]; then
        pass "doctor --strict mantiene exit 0 con drift detection informativo"
    else
        fail "doctor --strict obtuvo exit $estado"
        log "Output: $OUTPUT"
    fi

    afirmar_output_contiene "ℹ" "doctor muestra severidad info"
    afirmar_output_contiene "Drift detection disponible" "doctor informa disponibilidad del script"

    if [[ "$OUTPUT" != *"⚠ Drift detection"* && "$OUTPUT" != *"✗ Drift detection"* ]]; then
        pass "drift detection no genera warning ni error"
    else
        fail "drift detection generó finding bloqueante"
        log "Output: $OUTPUT"
    fi
}

test_colores_solo_en_tty
test_limites_bloque
test_limite_lineas_bloque
test_resumen_final
test_portabilidad_bash_3_2
test_identificadores_en_espanol
test_release_y_doctor

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Resultados: ${c_verde}%d pasaron${c_neutro}, ${c_rojo}%d fallaron${c_neutro}\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Tests fallidos:"
    for t in "${FAILED[@]}"; do
        printf "  ${c_rojo}-${c_neutro} %s\n" "$t"
    done
    exit 1
fi

exit 0
