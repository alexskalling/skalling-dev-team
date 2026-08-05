#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/spec-memory-link.sh"
PAU_AGENTE="$ROOT/agents-base/Pau.md"
DOCTOR="$ROOT/setup-team-doctor.sh"
DOC_DOCTOR="$ROOT/command/skalling-doctor.md"
README="$ROOT/README.md"
VERSION_FILE="$ROOT/VERSION"
CHANGELOG="$ROOT/CHANGELOG.md"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

PASS=0
FAIL=0
FAILED_TESTS=()

c_verde='\033[32m'
c_rojo='\033[31m'
c_azul='\033[36m'
c_neutro='\033[0m'

pass() { PASS=$((PASS + 1)); printf "  ${c_verde}✓${c_neutro} %s\n" "$*"; }
fail() { FAIL=$((FAIL + 1)); FAILED_TESTS+=("$*"); printf "  ${c_rojo}✗${c_neutro} %s\n" "$*" >&2; }
log() { if [[ "$VERBOSE" == true ]]; then printf "    %s\n" "$*"; fi; }

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

ejecutar_sin_fixture() {
    set +e
    OUTPUT="$(bash "$SCRIPT" "$@" 2>&1)"
    STATUS=$?
    set -e
}

ejecutar_sin_fixture_cero_args() {
    set +e
    OUTPUT="$(bash "$SCRIPT" 2>&1)"
    STATUS=$?
    set -e
}

preparar_fixture_plan() {
    local plan_slug="$1"
    rm -rf "$FIXTURE/.opencode/changes/$plan_slug"
    mkdir -p "$FIXTURE/.opencode/changes/$plan_slug/specs"
    mkdir -p "$FIXTURE/.opencode/context/concept"
    mkdir -p "$FIXTURE/scripts"
    cp "$SCRIPT" "$FIXTURE/scripts/spec-memory-link.sh"
}

preparar_concept_doc() {
    local slug="$1"
    local contenido="$2"
    mkdir -p "$FIXTURE/.opencode/context/concept"
    printf '%s\n' "$contenido" > "$FIXTURE/.opencode/context/concept/$slug.md"
}

preparar_plan_archivo() {
    local plan_slug="$1"
    local archivo_relativo="$2"
    local contenido="$3"
    local ruta_archivo="$FIXTURE/.opencode/changes/$plan_slug/$archivo_relativo"
    mkdir -p "$(dirname "$ruta_archivo")"
    printf '%s\n' "$contenido" > "$ruta_archivo"
}

preparar_destino_archive() {
    local yyyymm="$1"
    local plan_slug="$2"
    mkdir -p "$FIXTURE/.opencode/changes/archive/$yyyymm/$plan_slug"
}

ejecutar_script_plan() {
    local plan_slug="$1"
    local yyyymm="${2:-2026-08}"
    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/spec-memory-link.sh" ".opencode/changes/$plan_slug" ".opencode/changes/archive/$yyyymm/$plan_slug" 2>&1)"
    STATUS=$?
    set -e
}

ejecutar_script_con_destino() {
    local plan_slug="$1"
    local destino_relativo="$2"
    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/spec-memory-link.sh" ".opencode/changes/$plan_slug" "$destino_relativo" 2>&1)"
    STATUS=$?
    set -e
}

ejecutar_script_en_fixture_con_args() {
    set +e
    OUTPUT="$(cd "$FIXTURE" && bash "scripts/spec-memory-link.sh" "$@" 2>&1)"
    STATUS=$?
    set -e
}

echo "═══════════════════════════════════════════════════"
echo "  Spec ↔ Memory Link Tests"
echo "═══════════════════════════════════════════════════"

test_estructura_script() {
    echo ""
    echo "── Test 1.1: Estructura del script ──"

    afirmar_archivo_existe "$SCRIPT" "scripts/spec-memory-link.sh existe"
    afirmar_sintaxis_ok "$SCRIPT" "bash -n pasa en scripts/spec-memory-link.sh"

    local primera_linea
    primera_linea="$(head -1 "$SCRIPT")"
    if [[ "$primera_linea" == "#!/usr/bin/env bash" ]]; then
        pass "shebang correcto"
    else
        fail "shebang incorrecto: $primera_linea"
    fi

    if grep -q '^set -euo pipefail$' "$SCRIPT"; then
        pass "set -euo pipefail presente"
    else
        fail "falta set -euo pipefail"
    fi

    if grep -q '^validar_argv()' "$SCRIPT" \
       && grep -q '^detectar_concept_docs()' "$SCRIPT" \
       && grep -q '^extraer_matches()' "$SCRIPT" \
       && grep -q '^validar_path_concept()' "$SCRIPT" \
       && grep -q '^aplicar_footer_a_concept_doc()' "$SCRIPT" \
       && grep -q '^calcular_path_relativo()' "$SCRIPT" \
       && grep -q '^validar_footer_existente()' "$SCRIPT" \
       && grep -q '^validar_escribible()' "$SCRIPT" \
       && grep -q '^procesar_concept_doc()' "$SCRIPT" \
       && grep -q '^principal()' "$SCRIPT"; then
        pass "todas las funciones de spec declaradas"
    else
        fail "faltan funciones de spec"
    fi
}

test_argv_invalido() {
    echo ""
    echo "── Test 1.2: argv inválido retorna exit 2 con mensaje accionable ──"

    ejecutar_sin_fixture_cero_args
    if [[ "$STATUS" -eq 2 ]]; then
        pass "sin argumentos → exit 2"
    else
        fail "sin argumentos → exit esperado 2, obtuvo $STATUS"
    fi
    if [[ "$OUTPUT" == *"<origen>"* && "$OUTPUT" == *"<destino>"* ]]; then
        pass "mensaje sin args contiene <origen> y <destino>"
    else
        fail "mensaje sin args NO contiene <origen> y <destino>. Output: $OUTPUT"
    fi

    ejecutar_sin_fixture "solo-uno"
    if [[ "$STATUS" -eq 2 ]]; then
        pass "1 argumento → exit 2"
    else
        fail "1 argumento → exit esperado 2, obtuvo $STATUS"
    fi

    ejecutar_sin_fixture "a" "b" "c"
    if [[ "$STATUS" -eq 2 ]]; then
        pass "3 argumentos → exit 2"
    else
        fail "3 argumentos → exit esperado 2, obtuvo $STATUS"
    fi

    ejecutar_sin_fixture "/path/que/no/existe" ".opencode/changes/archive/2026-08/x"
    if [[ "$STATUS" -eq 2 ]]; then
        pass "origen inexistente → exit 2"
    else
        fail "origen inexistente → exit esperado 2, obtuvo $STATUS"
    fi
    if [[ "$OUTPUT" == *"<origen>"* ]]; then
        pass "mensaje origen inexistente menciona <origen>"
    else
        fail "mensaje origen inexistente NO menciona <origen>"
    fi

    preparar_fixture_plan "x"
    preparar_destino_archive "2026-08" "x"
    preparar_plan_archivo "x" "proposal.md" "# proposal"

    ejecutar_script_en_fixture_con_args ".opencode/changes/x" "/path/que/no/existe/destino"
    if [[ "$STATUS" -eq 2 ]]; then
        pass "destino inexistente → exit 2"
    else
        fail "destino inexistente → exit esperado 2, obtuvo $STATUS. Output: $OUTPUT"
    fi
    if [[ "$OUTPUT" == *"<destino>"* ]]; then
        pass "mensaje destino inexistente menciona <destino>"
    else
        fail "mensaje destino inexistente NO menciona <destino>. Output: $OUTPUT"
    fi

    rm -rf "$FIXTURE/.opencode/changes/vacio"
    mkdir -p "$FIXTURE/.opencode/changes/vacio"
    ejecutar_script_en_fixture_con_args ".opencode/changes/vacio" "$FIXTURE/vacio-dest"
    if [[ "$STATUS" -eq 2 ]]; then
        pass "directorio sin archivos escaneables → exit 2"
    else
        fail "directorio sin archivos → exit esperado 2, obtuvo $STATUS. Output: $OUTPUT"
    fi
}

test_detectar_archivos_escaneables_orden() {
    echo ""
    echo "── Test 1.3: detectar_archivos_escaneables orden, ignores, etc ──"

    preparar_fixture_plan "orden"
    preparar_plan_archivo "orden" "proposal.md" "# proposal"
    preparar_plan_archivo "orden" "design.md" "# design"
    preparar_plan_archivo "orden" "tasks.md" "# tasks"
    preparar_plan_archivo "orden" "receipts/foo.md" "# receipts"
    preparar_plan_archivo "orden" "index.md" "# index"
    preparar_plan_archivo "orden" "specs/01-foo.md" "# spec foo"
    preparar_plan_archivo "orden" "specs/02-bar.md" "# spec bar"

    preparar_destino_archive "2026-08" "orden"
    ejecutar_script_plan "orden" "2026-08"

    if [[ "$STATUS" -eq 0 ]]; then
        pass "directorio completo procesa OK"
    else
        fail "esperado exit 0, obtuvo $STATUS. Output: $OUTPUT"
    fi

    rm -rf "$FIXTURE/.opencode/changes/solo-proposal"
    preparar_fixture_plan "solo-proposal"
    preparar_plan_archivo "solo-proposal" "proposal.md" "# proposal"
    preparar_destino_archive "2026-08" "solo-proposal"
    ejecutar_script_plan "solo-proposal" "2026-08"
    if [[ "$STATUS" -eq 0 ]]; then
        pass "directorio con solo proposal.md procesa OK"
    else
        fail "esperado exit 0 con solo proposal, obtuvo $STATUS"
    fi

    rm -rf "$FIXTURE/.opencode/changes/specs-vacio"
    preparar_fixture_plan "specs-vacio"
    mkdir -p "$FIXTURE/.opencode/changes/specs-vacio/specs"
    preparar_plan_archivo "specs-vacio" "proposal.md" "# proposal"
    preparar_destino_archive "2026-08" "specs-vacio"
    ejecutar_script_plan "specs-vacio" "2026-08"
    if [[ "$STATUS" -eq 0 ]]; then
        pass "specs/ sin .md se ignora silenciosamente"
    else
        fail "specs/ vacío debía ignorarse, exit $STATUS. Output: $OUTPUT"
    fi
}

test_extraer_matches() {
    echo ""
    echo "── Test 1.4: extraer_matches con regex declarado ──"

    preparar_fixture_plan "extraer"
    preparar_destino_archive "2026-08" "extraer"
    preparar_concept_doc "a" "x"
    preparar_concept_doc "b" "x"
    preparar_concept_doc "backtick" "x"
    preparar_concept_doc "link" "x"
    preparar_concept_doc "code" "x"

    preparar_plan_archivo "extraer" "proposal.md" "antes
.opencode/context/concept/a.md
entre
.opencode/context/concept/b.md
despues
mención coloquial sin path
mas
repo/.opencode/context/concept/external-prefix.md
backticks: \`.opencode/context/concept/backtick.md\`
link: [.opencode/context/concept/link.md](...)
code: \`\`
.opencode/context/concept/code.md
\`\`\`
fin"

    ejecutar_script_plan "extraer" "2026-08"

    if [[ "$OUTPUT" == *"aplicado:"*"a.md"* ]]; then
        pass "extrae match básico .opencode/context/concept/a.md"
    else
        fail "NO extrae match básico. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"aplicado:"*"b.md"* ]]; then
        pass "extrae segundo match .opencode/context/concept/b.md"
    else
        fail "NO extrae segundo match. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"advertencia:"*"external-prefix"* ]]; then
        pass "path con prefijo repo/ reporta como advertencia (no existe en fixture)"
    else
        fail "NO detectó path con prefijo repo/. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"advertencia:"*"backtick"* ]]; then
        pass "match en backticks se procesa (advierte porque el path no existe en fixture)"
    else
        fail "match en backticks NO procesado. Output: $OUTPUT"
    fi
}

test_filtrar_matches_invalidos_via_cli() {
    echo ""
    echo "── Test 1.5: filtrar_matches_invalidos descarta '..', espacios, '/.md' vacío ──"

    preparar_fixture_plan "filtro"
    preparar_destino_archive "2026-08" "filtro"
    preparar_concept_doc "valido" "x"

    preparar_plan_archivo "filtro" "proposal.md" "valido: .opencode/context/concept/valido.md
traversal: .opencode/context/concept/foo..md
espacio: .opencode/context/concept/con espacio.md
vacio: .opencode/context/concept/.md"

    ejecutar_script_plan "filtro" "2026-08"

    if [[ "$OUTPUT" == *"aplicado:"*"valido.md"* ]]; then
        pass "match válido se aplica"
    else
        fail "match válido NO se aplicó. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" != *"aplicado:"*"foo..md"* ]]; then
        pass "match con '..' NO se aplica"
    else
        fail "match con '..' se aplicó (debió descartarse)"
    fi

    if [[ "$OUTPUT" != *"aplicado:"*"con espacio"* ]]; then
        pass "match con espacio NO se aplica"
    else
        fail "match con espacio se aplicó (debió descartarse)"
    fi

    if [[ "$OUTPUT" != *"aplicado:"*"aplicado: .opencode/context/concept/.md"* ]]; then
        pass "match con '/.md' vacío NO se aplica"
    else
        fail "match con '/.md' vacío se aplicó"
    fi
}

test_validar_path_concept_via_cli() {
    echo ""
    echo "── Test 1.6: validar_path_concept via CLI ──"

    preparar_fixture_plan "validar"
    preparar_destino_archive "2026-08" "validar"
    preparar_concept_doc "existe" "x"

    preparar_plan_archivo "validar" "proposal.md" "existe: .opencode/context/concept/existe.md
noexiste: .opencode/context/concept/inexistente.md"

    ejecutar_script_plan "validar" "2026-08"

    if [[ "$OUTPUT" == *"aplicado:"*"existe.md"* ]]; then
        pass "regex OK + existe → aplicado"
    else
        fail "regex OK + existe NO se aplicó. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"advertencia:"*"inexistente"* ]]; then
        pass "regex OK + no existe → advertencia"
    else
        fail "regex OK + no existe NO advirtió. Output: $OUTPUT"
    fi

    if [[ ! -f "$FIXTURE/.opencode/context/concept/inexistente.md" ]]; then
        pass "concept doc inexistente NO se crea"
    else
        fail "concept doc inexistente se creó"
    fi
}

test_detectar_concept_docs_dedup() {
    echo ""
    echo "── Test 1.7: detectar_concept_docs deduplica ──"

    preparar_fixture_plan "dedup"
    preparar_destino_archive "2026-08" "dedup"
    preparar_concept_doc "compartido" "x"

    preparar_plan_archivo "dedup" "proposal.md" ".opencode/context/concept/compartido.md"
    preparar_plan_archivo "dedup" "design.md" ".opencode/context/concept/compartido.md"
    preparar_plan_archivo "dedup" "tasks.md" ".opencode/context/concept/compartido.md"

    ejecutar_script_plan "dedup" "2026-08"

    local aplicaciones
    aplicaciones="$(printf '%s\n' "$OUTPUT" | grep -c '^aplicado:' || true)"

    if [[ "$aplicaciones" -eq 1 ]]; then
        pass "3 menciones del mismo concept doc → 1 aplicado"
    else
        fail "esperaba 1 aplicado, obtuvo $aplicaciones. Output: $OUTPUT"
    fi
}

test_calcular_path_relativo() {
    echo ""
    echo "── Test 2.1: calcular_path_relativo hardcodea '../../changes/archive/...' ──"

    preparar_fixture_plan "calc"
    preparar_destino_archive "2026-08" "calc"
    preparar_concept_doc "target" "x"
    preparar_plan_archivo "calc" "proposal.md" ".opencode/context/concept/target.md"

    ejecutar_script_con_destino "calc" ".opencode/changes/archive/2026-08/calc"

    local concept_doc="$FIXTURE/.opencode/context/concept/target.md"
    if grep -q '../../changes/archive/2026-08/calc/' "$concept_doc"; then
        pass "footer usa '../../changes/archive/2026-08/calc/'"
    else
        fail "footer NO contiene path correcto. File: $(cat "$concept_doc")"
    fi

    preparar_concept_doc "otro" "x"
    preparar_plan_archivo "calc" "proposal.md" ".opencode/context/concept/otro.md
.opencode/context/concept/target.md"
    rm -f "$concept_doc"
    preparar_concept_doc "target" "x"

    ejecutar_script_con_destino "calc" ".opencode/changes/archive/2026-08/calc/"

    if grep -q '../../changes/archive/2026-08/calc/' "$concept_doc"; then
        pass "footer con trailing slash en destino → mismo path"
    else
        fail "footer con trailing slash → resultado diferente. File: $(cat "$concept_doc")"
    fi
}

test_validar_footer_existente() {
    echo ""
    echo "── Test 2.2: validar_footer_existente via CLI (preservar) ──"

    preparar_fixture_plan "footer"
    preparar_destino_archive "2026-08" "footer"
    preparar_concept_doc "sin" "contenido
"
    preparar_concept_doc "exacto" "contenido

## Spec original

[../../changes/archive/2026-05/otro/](../../changes/archive/2026-05/otro/)
"
    preparar_concept_doc "subheading" "contenido

### Spec original

[](../../changes/archive/2026-05/otro/)
"
    preparar_concept_doc "extra" "contenido

## Spec original X

[](../../changes/archive/2026-05/otro/)
"

    preparar_plan_archivo "footer" "proposal.md" "a: .opencode/context/concept/sin.md
b: .opencode/context/concept/exacto.md
c: .opencode/context/concept/subheading.md
d: .opencode/context/concept/extra.md"

    ejecutar_script_plan "footer" "2026-08"

    if [[ "$OUTPUT" == *"aplicado:"*"sin.md"* ]]; then
        pass "sin footer → aplicado"
    else
        fail "sin footer NO se aplicó. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"preservado:"*"exacto.md"* ]]; then
        pass "## Spec original exacto → preservado"
    else
        fail "## Spec original exacto NO se preservó. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"aplicado:"*"subheading.md"* ]]; then
        pass "### Spec original (subheading) → aplicado (no matchea)"
    else
        fail "### Spec original NO se aplicó (debió). Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"aplicado:"*"extra.md"* ]]; then
        pass "## Spec original X (texto extra) → aplicado"
    else
        fail "## Spec original X NO se aplicó. Output: $OUTPUT"
    fi
}

test_validar_escribible_y_vacio() {
    echo ""
    echo "── Test 2.3: validar_escribible via CLI ──"

    preparar_fixture_plan "escribible"
    preparar_destino_archive "2026-08" "escribible"

    mkdir -p "$FIXTURE/.opencode/context/concept"
    printf '' > "$FIXTURE/.opencode/context/concept/vacio.md"

    preparar_concept_doc "ok" "contenido
"
    preparar_plan_archivo "escribible" "proposal.md" ".opencode/context/concept/vacio.md
.opencode/context/concept/ok.md"

    ejecutar_script_plan "escribible" "2026-08"

    if [[ "$OUTPUT" == *"error:"*"vacío"* ]] || [[ "$OUTPUT" == *"errores: 1"* ]]; then
        pass "concept doc vacío → error"
    else
        fail "concept doc vacío NO reportó error. Output: $OUTPUT"
    fi
    log "Output vacío test: $OUTPUT"

    if [[ "$OUTPUT" == *"aplicado:"*"ok.md"* ]]; then
        pass "concept doc válido → aplicado (batch continúa)"
    else
        fail "concept doc válido NO se aplicó en batch. Output: $OUTPUT"
    fi
}

test_aplicar_footer_a_concept_doc() {
    echo ""
    echo "── Test 2.4: aplicar_footer_a_concept_doc escritura atómica ──"

    preparar_fixture_plan "aplicar"
    preparar_destino_archive "2026-08" "aplicar"
    preparar_concept_doc "target" "## What
algo
## Why
porque
## Where
aca
## Learned
fin
"
    preparar_plan_archivo "aplicar" "proposal.md" ".opencode/context/concept/target.md"

    ejecutar_script_plan "aplicar" "2026-08"

    if [[ "$STATUS" -eq 0 ]]; then
        pass "aplicación exit 0"
    else
        fail "exit esperado 0, obtuvo $STATUS. Output: $OUTPUT"
    fi

    local concept_doc="$FIXTURE/.opencode/context/concept/target.md"

    if tail -5 "$concept_doc" | grep -q '^## Spec original$'; then
        pass "archivo termina con '## Spec original'"
    else
        fail "archivo NO termina con '## Spec original'. Tail: $(tail -5 "$concept_doc")"
    fi

    if tail -3 "$concept_doc" | grep -q '^.\?\[../../changes/archive/2026-08/aplicar/\].*$'; then
        pass "link relativo presente"
    else
        fail "link relativo NO presente. Tail: $(tail -3 "$concept_doc")"
    fi

    local primeras8
    primeras8="$(head -8 "$concept_doc")"
    if [[ "$primeras8" == *"## What"* && "$primeras8" == *"## Learned"* ]]; then
        pass "primeras 8 líneas (frontmatter/contenido) intactas"
    else
        fail "primeras 8 líneas fueron alteradas. Got: $primeras8"
    fi

    local bytes_finales
    bytes_finales="$(tail -c 1 "$concept_doc" | wc -l | tr -d ' ')"
    if [[ "$bytes_finales" -eq 1 ]]; then
        pass "archivo termina con newline"
    else
        fail "archivo NO termina con newline"
    fi

    local archivos_tmp
    archivos_tmp="$(find "$FIXTURE" -name '*.tmp.*' 2>/dev/null | grep -c '.' || true)"
    if [[ "$archivos_tmp" -eq 0 ]]; then
        pass "no quedan archivos .tmp.* del proceso"
    else
        fail "quedan $archivos_tmp archivos .tmp.*"
    fi
}

test_happy_path_multiples_concept_docs() {
    echo ""
    echo "── Test 2.6a: happy path end-to-end ──"

    preparar_fixture_plan "happy"
    preparar_destino_archive "2026-08" "happy"

    preparar_concept_doc "repo-pattern" "# Repo
## What
algo
"
    preparar_concept_doc "db-schema" "# DB
## What
algo
"
    preparar_plan_archivo "happy" "proposal.md" "ver .opencode/context/concept/repo-pattern.md y .opencode/context/concept/db-schema.md"
    preparar_plan_archivo "happy" "design.md" "también referencia rota: .opencode/context/concept/inexistente.md"

    ejecutar_script_plan "happy" "2026-08"

    if [[ "$STATUS" -eq 0 ]]; then
        pass "exit 0 con 2 válidos + 1 rota"
    else
        fail "exit esperado 0, obtuvo $STATUS. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"aplicado:"*"repo-pattern.md"* ]]; then
        pass "reporta aplicado: repo-pattern.md"
    else
        fail "NO reporta aplicado: repo-pattern.md. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"aplicado:"*"db-schema.md"* ]]; then
        pass "reporta aplicado: db-schema.md"
    else
        fail "NO reporta aplicado: db-schema.md"
    fi

    if [[ "$OUTPUT" == *"advertencia:"*"inexistente"* ]]; then
        pass "reporta advertencia de referencia rota"
    else
        fail "NO reporta advertencia de referencia rota. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"aplicados: 2"* ]]; then
        pass "resumen: aplicados: 2"
    else
        fail "resumen NO dice 'aplicados: 2'. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"preservados: 0"* && "$OUTPUT" == *"errores: 0"* ]]; then
        pass "resumen: preservados: 0, errores: 0"
    else
        fail "resumen incompleto. Output: $OUTPUT"
    fi

    if grep -q '^## Spec original$' "$FIXTURE/.opencode/context/concept/repo-pattern.md"; then
        pass "repo-pattern.md tiene footer"
    else
        fail "repo-pattern.md NO tiene footer"
    fi

    if grep -q '^## Spec original$' "$FIXTURE/.opencode/context/concept/db-schema.md"; then
        pass "db-schema.md tiene footer"
    else
        fail "db-schema.md NO tiene footer"
    fi
}

test_sin_concept_docs_afectados() {
    echo ""
    echo "── Test 2.6b: plan sin matches → exit 0 + mensaje informativo ──"

    preparar_fixture_plan "sin-matches"
    preparar_destino_archive "2026-08" "sin-matches"
    preparar_plan_archivo "sin-matches" "proposal.md" "# proposal sin menciones"
    preparar_plan_archivo "sin-matches" "design.md" "# design vacío"

    ejecutar_script_plan "sin-matches" "2026-08"

    if [[ "$STATUS" -eq 0 ]]; then
        pass "exit 0 sin concept docs afectados"
    else
        fail "exit esperado 0, obtuvo $STATUS. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"0 concept docs afectados por este plan"* ]]; then
        pass "mensaje '0 concept docs afectados' presente"
    else
        fail "mensaje '0 concept docs afectados' NO presente"
    fi
}

test_idempotencia_segundo_run() {
    echo ""
    echo "── Test 2.6c: idempotencia — segundo run preserva ──"

    preparar_fixture_plan "idem"
    preparar_destino_archive "2026-08" "idem"
    preparar_concept_doc "repo-pattern" "contenido inicial
"
    preparar_plan_archivo "idem" "proposal.md" "ver .opencode/context/concept/repo-pattern.md"

    ejecutar_script_plan "idem" "2026-08"
    if [[ "$STATUS" -ne 0 ]]; then
        fail "primer run falló con exit $STATUS"
    fi

    local hash_antes
    hash_antes="$(shasum "$FIXTURE/.opencode/context/concept/repo-pattern.md" | awk '{print $1}')"

    ejecutar_script_plan "idem" "2026-08"

    if [[ "$STATUS" -eq 0 ]]; then
        pass "segundo run exit 0"
    else
        fail "segundo run exit esperado 0, obtuvo $STATUS"
    fi

    local hash_despues
    hash_despues="$(shasum "$FIXTURE/.opencode/context/concept/repo-pattern.md" | awk '{print $1}')"

    if [[ "$hash_antes" == "$hash_despues" ]]; then
        pass "concept doc no modificado en segundo run (idempotencia)"
    else
        fail "concept doc fue modificado en segundo run (rompió idempotencia)"
    fi

    if [[ "$OUTPUT" == *"preservado:"*"repo-pattern.md"* ]]; then
        pass "segundo run reporta preservado:"
    else
        fail "segundo run NO reporta preservado:"
    fi
}

test_idempotencia_tres_runs() {
    echo ""
    echo "── Test 3.2a: idempotencia 3-run — tercero no modifica ──"

    preparar_fixture_plan "tres-runs"
    preparar_destino_archive "2026-08" "tres-runs"
    preparar_concept_doc "repo-pattern" "contenido
"
    preparar_plan_archivo "tres-runs" "proposal.md" "ver .opencode/context/concept/repo-pattern.md"

    ejecutar_script_plan "tres-runs" "2026-08"
    local hash1
    hash1="$(shasum "$FIXTURE/.opencode/context/concept/repo-pattern.md" | awk '{print $1}')"

    ejecutar_script_plan "tres-runs" "2026-08"
    local hash2
    hash2="$(shasum "$FIXTURE/.opencode/context/concept/repo-pattern.md" | awk '{print $1}')"

    ejecutar_script_plan "tres-runs" "2026-08"
    local hash3
    hash3="$(shasum "$FIXTURE/.opencode/context/concept/repo-pattern.md" | awk '{print $1}')"

    if [[ "$hash1" == "$hash2" && "$hash2" == "$hash3" ]]; then
        pass "3 runs consecutivos no modifican el concept doc"
    else
        fail "hashes difieren entre runs. h1=$hash1 h2=$hash2 h3=$hash3"
    fi
}

test_preservar_primero_con_link_externo() {
    echo ""
    echo "── Test 3.2b: preservar primero con link externo pre-existente ──"

    preparar_fixture_plan "preservar"
    preparar_destino_archive "2026-08" "preservar"

    preparar_concept_doc "repo-pattern" "contenido histórico

## Spec original

[../../changes/archive/2026-05/otro-plan/](../../changes/archive/2026-05/otro-plan/)
"
    preparar_plan_archivo "preservar" "proposal.md" "ver .opencode/context/concept/repo-pattern.md"

    ejecutar_script_plan "preservar" "2026-08"

    if [[ "$STATUS" -eq 0 ]]; then
        pass "exit 0 cuando footer ya existe"
    else
        fail "exit esperado 0, obtuvo $STATUS"
    fi

    if grep -q 'archive/2026-05/otro-plan/' "$FIXTURE/.opencode/context/concept/repo-pattern.md"; then
        pass "link a archive/2026-05/otro-plan/ preservado"
    else
        fail "link externo NO preservado"
    fi

    if ! grep -q 'archive/2026-08/preservar/' "$FIXTURE/.opencode/context/concept/repo-pattern.md"; then
        pass "NO se agregó link al plan nuevo (preservar primero)"
    else
        fail "se agregó link nuevo (debió preservar el primero)"
    fi

    if [[ "$OUTPUT" == *"preservado:"* ]]; then
        pass "output reporta preservado:"
    else
        fail "output NO reporta preservado:"
    fi
}

test_concept_doc_no_escribible() {
    echo ""
    echo "── Test 2.6d: concept doc no escribible → exit 1, batch continúa ──"

    if [[ "$(id -u)" -eq 0 ]]; then
        echo "  SKIP: corriendo como root, chmod a-w se ignora"
        return 0
    fi

    preparar_fixture_plan "no-escribible"
    preparar_destino_archive "2026-08" "no-escribible"

    preparar_concept_doc "repo-pattern" "contenido
"
    preparar_plan_archivo "no-escribible" "proposal.md" "ver .opencode/context/concept/repo-pattern.md"

    chmod a-w "$FIXTURE/.opencode/context/concept/repo-pattern.md"
    ejecutar_script_plan "no-escribible" "2026-08"
    chmod u+w "$FIXTURE/.opencode/context/concept/repo-pattern.md"

    if [[ "$STATUS" -eq 1 ]]; then
        pass "exit 1 cuando concept doc no escribible"
    else
        fail "exit esperado 1, obtuvo $STATUS. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"error:"*"no se puede escribir"* ]]; then
        pass "output contiene 'error: no se puede escribir'"
    else
        fail "output NO contiene mensaje de error. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"errores: 1"* ]]; then
        pass "resumen: errores: 1"
    else
        fail "resumen NO dice 'errores: 1'"
    fi
}

test_formato_exacto_footer() {
    echo ""
    echo "── Test 2.4 / Spec 02 scenario 10: formato exacto del footer ──"

    preparar_fixture_plan "formato"
    preparar_destino_archive "2026-08" "formato"
    preparar_concept_doc "target" "## What
algo
## Why
porque
## Where
aca
## Learned
fin"
    preparar_plan_archivo "formato" "proposal.md" "ver .opencode/context/concept/target.md"

    ejecutar_script_plan "formato" "2026-08"

    if [[ "$STATUS" -eq 0 ]]; then
        pass "exit 0 formato test"
    else
        fail "exit esperado 0, obtuvo $STATUS"
    fi

    local concept_doc="$FIXTURE/.opencode/context/concept/target.md"

    local linea_spec linea_antes linea_despues_1 linea_despues_2 linea_link
    linea_spec="$(grep -n '^## Spec original$' "$concept_doc" | head -1 | cut -d: -f1)"
    linea_antes=$((linea_spec - 1))
    linea_despues_1=$((linea_spec + 1))
    linea_despues_2=$((linea_spec + 2))
    linea_link=$((linea_spec + 3))

    local antes despues_1 despues_2 link_final
    antes="$(sed -n "${linea_antes}p" "$concept_doc")"
    despues_1="$(sed -n "${linea_despues_1}p" "$concept_doc")"
    despues_2="$(sed -n "${linea_despues_2}p" "$concept_doc")"
    link_final="$(sed -n "${linea_link}p" "$concept_doc")"

    if [[ -z "$antes" ]]; then
        pass "1 línea antes de '## Spec original': vacía (separación visual)"
    else
        fail "1 línea antes: '$antes' (debió ser vacía)"
    fi

    if [[ -z "$despues_1" ]]; then
        pass "1 línea después de '## Spec original': vacía"
    else
        fail "1 línea después: '$despues_1' (debió ser vacía)"
    fi

    if [[ "$despues_2" == "[../../changes/archive/2026-08/formato/](../../changes/archive/2026-08/formato/)" ]]; then
        pass "link relativo exacto"
    else
        fail "link: '$despues_2'"
    fi

    if [[ -z "$link_final" ]]; then
        pass "última línea: vacía (trailing newline preservado)"
    else
        fail "última línea: '$link_final' (debió ser vacía)"
    fi
}

test_pau_referencia_spec_memory_link() {
    echo ""
    echo "── Test 3.2c: Pau.md referencia el script ──"

    if grep -q 'spec-memory-link' "$PAU_AGENTE"; then
        pass "Pau.md menciona 'spec-memory-link'"
    else
        fail "Pau.md NO menciona 'spec-memory-link'"
    fi

    if grep -q 'Spec original' "$PAU_AGENTE"; then
        pass "Pau.md menciona 'Spec original'"
    else
        fail "Pau.md NO menciona 'Spec original'"
    fi
}

test_pau_paso_5_intacto() {
    echo ""
    echo "── Test 3.2d: Pau.md PASO 5 sigue conteniendo archivado intacto ──"

    if grep -q 'git mv\|\bmv\b' "$PAU_AGENTE"; then
        pass "PASO 5 mantiene mención de mv/git mv"
    else
        fail "PASO 5 perdió mención de mv/git mv"
    fi

    if grep -q 'YYYY-MM\|<YYYY' "$PAU_AGENTE"; then
        pass "PASO 5 mantiene formato YYYY-MM"
    else
        fail "PASO 5 perdió formato YYYY-MM"
    fi
}

test_pau_reporte_concept_docs_enlazados() {
    echo ""
    echo "── Test 3.2e: Pau.md describe el reporte de concept docs enlazados ──"

    if grep -qi 'concept docs enlazados\|concept.*enlazado\|enlazado.*concept' "$PAU_AGENTE"; then
        pass "Pau.md describe reporte de concept docs enlazados"
    else
        fail "Pau.md NO describe reporte de concept docs enlazados"
    fi
}

test_doctor_info_spec_memory_link() {
    echo ""
    echo "── Test 4.6: doctor info sobre spec-memory-link (no bloqueante) ──"

    if grep -q 'Spec ↔ Memory link' "$DOCTOR"; then
        pass "doctor incluye 'Spec ↔ Memory link'"
    else
        fail "doctor NO incluye 'Spec ↔ Memory link'"
    fi

    if grep -q 'info.*Spec' "$DOCTOR"; then
        pass "doctor usa info() para Spec ↔ Memory link"
    else
        fail "doctor NO usa info() para Spec ↔ Memory link"
    fi

    local instancia_global="$FIXTURE/doctor-global"
    local instancia_proyecto="$FIXTURE/doctor-proyecto"
    mkdir -p "$instancia_global/agents" "$instancia_global/skills" "$instancia_global/command" "$instancia_global/templates" "$instancia_global/skalling-data" "$instancia_global/scripts" "$instancia_proyecto/.opencode"
    cp "$ROOT/scripts/spec-memory-link.sh" "$instancia_global/scripts/spec-memory-link.sh"

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
    OUTPUT="$(SKALLING_OPENCODE_DIR="$instancia_global" bash "$DOCTOR" --strict --project "$instancia_proyecto" 2>&1)"
    local rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
        pass "doctor --strict exit 0 con script instalado"
    else
        fail "doctor --strict exit $rc. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" == *"ℹ"* && "$OUTPUT" == *"Spec ↔ Memory link"* ]]; then
        pass "doctor muestra ℹ con 'Spec ↔ Memory link'"
    else
        fail "doctor NO muestra ℹ con 'Spec ↔ Memory link'. Output: $OUTPUT"
    fi

    if [[ "$OUTPUT" != *"⚠ Spec"* && "$OUTPUT" != *"✗ Spec"* ]]; then
        pass "doctor NO muestra ⚠ ni ✗ para Spec ↔ Memory link"
    else
        fail "doctor mostró finding bloqueante para Spec ↔ Memory link"
    fi

    set +e
    OUTPUT_NORMAL="$(SKALLING_OPENCODE_DIR="$instancia_global" bash "$DOCTOR" --project "$instancia_proyecto" 2>&1)"
    local rc_normal=$?
    set -e
    if [[ "$rc_normal" -eq 0 ]]; then
        pass "doctor modo normal exit 0"
    else
        fail "doctor modo normal exit $rc_normal"
    fi
}

test_portabilidad_bash_3_2() {
    echo ""
    echo "── Test 3.2 / Spec 03 scenario 11: portabilidad Bash 3.2 ──"

    afirmar_sintaxis_ok "$SCRIPT" "script principal bash -n pasa"
    afirmar_sintaxis_ok "$ROOT/tests/spec-memory-link.test.sh" "suite bash -n pasa"

    local api_asociativa='declare -A'
    local api_mapa='mapfile'
    local api_lectura='readarray'

    local usos
    usos="$(grep -E "($api_asociativa|(^|[^[:alnum:]_])$api_mapa([^[:alnum:]_]|$)|(^|[^[:alnum:]_])$api_lectura([^[:alnum:]_]|$))" "$SCRIPT" 2>/dev/null || true)"

    if [[ -z "$usos" ]]; then
        pass "script no usa APIs exclusivas de Bash 4+"
    else
        fail "se encontraron APIs no portables. Coincidencias: $usos"
    fi

    preparar_fixture_plan "bash-portable"
    preparar_destino_archive "2026-08" "bash-portable"
    preparar_concept_doc "target" "contenido
"
    preparar_plan_archivo "bash-portable" "proposal.md" "ver .opencode/context/concept/target.md"
    chmod -x "$FIXTURE/scripts/spec-memory-link.sh"

    ejecutar_script_plan "bash-portable" "2026-08"
    if [[ "$STATUS" -eq 0 ]]; then
        pass "script funciona vía bash sin bit ejecutable"
    else
        fail "script requiere bit ejecutable (status $STATUS)"
    fi
}

test_identificadores_en_espanol() {
    echo ""
    echo "── Test 3.2 / R1: identificadores en español ──"

    local identificadores_ingles
    identificadores_ingles="$(grep -En '(^|[[:space:]])(main|plan_dir|spec_path)(=|\(\))' "$SCRIPT" 2>/dev/null || true)"
    if [[ -z "$identificadores_ingles" ]]; then
        pass "script no usa identificadores propios en inglés (main, plan_dir, etc.)"
    else
        fail "script usa identificadores en inglés. Coincidencias: $identificadores_ingles"
    fi

    if grep -q '^validar_argv()' "$SCRIPT" \
       && grep -q '^detectar_concept_docs()' "$SCRIPT" \
       && grep -q '^extraer_matches()' "$SCRIPT" \
       && grep -q '^validar_path_concept()' "$SCRIPT" \
       && grep -q '^aplicar_footer_a_concept_doc()' "$SCRIPT"; then
        pass "helpers clave con identificadores en español"
    else
        fail "faltan helpers con identificadores en español"
    fi
}

test_version_bump_y_changelog() {
    echo ""
    echo "── Test 4.4 / 4.5: bump 0.7.3 y entrada CHANGELOG ──"

    local version_actual
    version_actual="$(grep -E '^__version__' "$VERSION_FILE" | sed -E 's/.*"([^"]+)".*/\1/')"
    if [[ "$version_actual" == "0.7.3" ]]; then
        pass "VERSION = 0.7.3"
    else
        fail "VERSION != 0.7.3 (obtenido: $version_actual)"
    fi

    if grep -q 'SKALLING_VERSION="\$(grep' "$DOCTOR"; then
        pass "doctor lee SKALLING_VERSION dinámico de VERSION"
    else
        fail "doctor SKALLING_VERSION no lee de VERSION dinámicamente"
    fi

    if grep -q 'SKALLING_VERSION="\$(grep' "$ROOT/install-global.sh"; then
        pass "install-global.sh lee SKALLING_VERSION dinámico de VERSION"
    else
        fail "install-global.sh SKALLING_VERSION no lee de VERSION dinámicamente"
    fi

    if grep -q '^## \[0.6.0\]' "$CHANGELOG"; then
        pass "CHANGELOG tiene sección [0.6.0]"
    else
        fail "CHANGELOG sin sección [0.6.0]"
    fi

    if grep -q 'spec-memory-link' "$CHANGELOG"; then
        pass "CHANGELOG menciona spec-memory-link"
    else
        fail "CHANGELOG NO menciona spec-memory-link"
    fi

    if grep -q 'agents-base/Pau.md' "$CHANGELOG"; then
        pass "CHANGELOG menciona cambio en Pau.md"
    else
        fail "CHANGELOG NO menciona cambio en Pau.md"
    fi
}

test_documentacion_readme_y_comando() {
    echo ""
    echo "── Test 4.2 / 4.3: documentación README + command ──"

    if grep -qi 'spec-memory-link' "$DOC_DOCTOR"; then
        pass "command/skalling-doctor.md menciona spec-memory-link"
    else
        fail "command/skalling-doctor.md NO menciona spec-memory-link"
    fi

    if grep -q 'ejecución manual' "$DOC_DOCTOR"; then
        pass "command/skalling-doctor.md menciona ejecución manual"
    else
        fail "command/skalling-doctor.md NO menciona ejecución manual"
    fi

    if grep -qi 'spec-memory-link' "$README"; then
        pass "README menciona spec-memory-link"
    else
        fail "README NO menciona spec-memory-link"
    fi

    if grep -q 'scripts/spec-memory-link.sh' "$README"; then
        pass "README menciona el script"
    else
        fail "README NO menciona scripts/spec-memory-link.sh"
    fi
}

test_estructura_script
test_argv_invalido
test_detectar_archivos_escaneables_orden
test_extraer_matches
test_filtrar_matches_invalidos_via_cli
test_validar_path_concept_via_cli
test_detectar_concept_docs_dedup
test_calcular_path_relativo
test_validar_footer_existente
test_validar_escribible_y_vacio
test_aplicar_footer_a_concept_doc
test_happy_path_multiples_concept_docs
test_sin_concept_docs_afectados
test_idempotencia_segundo_run
test_idempotencia_tres_runs
test_preservar_primero_con_link_externo
test_concept_doc_no_escribible
test_formato_exacto_footer
test_pau_referencia_spec_memory_link
test_pau_paso_5_intacto
test_pau_reporte_concept_docs_enlazados
test_doctor_info_spec_memory_link
test_portabilidad_bash_3_2
test_identificadores_en_espanol
test_version_bump_y_changelog
test_documentacion_readme_y_comando

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Resultados: ${c_verde}%d pasaron${c_neutro}, ${c_rojo}%d fallaron${c_neutro}\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Tests fallidos:"
    for t in "${FAILED_TESTS[@]}"; do
        printf "  ${c_rojo}-${c_neutro} %s\n" "$t"
    done
    exit 1
fi

exit 0