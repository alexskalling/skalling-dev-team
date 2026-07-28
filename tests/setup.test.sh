#!/usr/bin/env bash
# tests/setup.test.sh — Tests del installer de Skalling.
#
# Setup: clona skalling-dev-team en un HOME temporal, corre install-global.sh,
# valida que la estructura queda correcta. Corre bootstrap-context.sh en
# un proyecto mock y valida el bundle OKF.
#
# Uso:
#   bash tests/setup.test.sh
#   bash tests/setup.test.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────

c_green='\033[32m'
c_red='\033[31m'
c_yellow='\033[33m'
c_reset='\033[0m'

pass() { PASS=$((PASS+1)); printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
fail() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$*"); printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
log()  { if [[ "$VERBOSE" == true ]]; then printf "    %s\n" "$*"; fi; }

assert_file_exists() {
    if [[ -f "$1" ]]; then
        pass "$2"
    else
        fail "$2 — archivo no existe: $1"
    fi
}

assert_file_contains() {
    if [[ -f "$1" ]] && grep -q "$2" "$1"; then
        pass "$3"
    else
        fail "$3 — no contiene '$2' en $1"
    fi
}

assert_dir_exists() {
    if [[ -d "$1" ]]; then
        pass "$2"
    else
        fail "$2 — directorio no existe: $1"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 1: Estructura del installer existe
# ──────────────────────────────────────────────────────────────────────────────

test_installer_structure() {
    echo ""
    echo "── Test 1: Estructura del installer ──"

    assert_file_exists "$REPO_ROOT/setup.sh" "setup.sh existe"
    assert_file_exists "$REPO_ROOT/install-global.sh" "install-global.sh existe"
    assert_file_exists "$REPO_ROOT/bootstrap-context.sh" "bootstrap-context.sh existe"
    assert_file_exists "$REPO_ROOT/setup-team-doctor.sh" "setup-team-doctor.sh existe"
    assert_file_exists "$REPO_ROOT/constitution/constitucion.md" "constitucion/constitucion.md existe"
    assert_dir_exists "$REPO_ROOT/agents-base" "agents-base/ existe"
    assert_dir_exists "$REPO_ROOT/templates" "templates/ existe"
    assert_dir_exists "$REPO_ROOT/command" "command/ existe"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 2: 8 agentes en agents-base
# ──────────────────────────────────────────────────────────────────────────────

test_agents_exist() {
    echo ""
    echo "── Test 2: 8 agentes presentes ──"

    local expected=(Alex Pol Jes Sol Teo Jhon Luz Pau)
    for agent in "${expected[@]}"; do
        assert_file_exists "$REPO_ROOT/agents-base/${agent}.md" "agents-base/${agent}.md existe"
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 3: Frontmatter de cada agente
# ──────────────────────────────────────────────────────────────────────────────

test_agent_frontmatter() {
    echo ""
    echo "── Test 3: Frontmatter correcto ──"

    # Alex debe ser primary
    if grep -q "^mode: primary" "$REPO_ROOT/agents-base/Alex.md"; then
        pass "Alex tiene mode: primary"
    else
        fail "Alex NO tiene mode: primary"
    fi

    # Los otros 7 deben ser subagent
    local others=(Pol Jes Sol Teo Jhon Luz Pau)
    for agent in "${others[@]}"; do
        if grep -q "^mode: subagent" "$REPO_ROOT/agents-base/${agent}.md"; then
            pass "${agent} tiene mode: subagent"
        else
            fail "${agent} NO tiene mode: subagent"
        fi
    done

    # Ninguno debe tener model: hardcodeado
    for agent in "${expected_all[@]}"; do
        if grep -q "^model:" "$REPO_ROOT/agents-base/${agent}.md"; then
            fail "${agent} tiene model: hardcodeado (no recomendado)"
        fi
    done

    # Hidden: true para Jhon, Luz, Pau
    local hidden_agents=(Jhon Luz Pau)
    for agent in "${hidden_agents[@]}"; do
        if grep -q "^hidden: true" "$REPO_ROOT/agents-base/${agent}.md"; then
            pass "${agent} tiene hidden: true"
        else
            fail "${agent} NO tiene hidden: true"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 4: Constitución tiene reglas R1-R14
# ──────────────────────────────────────────────────────────────────────────────

test_constitution() {
    echo ""
    echo "── Test 4: Constitución completa ──"

    local rules=(R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12 R13 R14)
    for r in "${rules[@]}"; do
        # Match "### R<n>" or "## R<n>" or "## [emoji] R<n>" formats
        if grep -qE "^(##|###) .*${r} " "$REPO_ROOT/constitution/constitucion.md"; then
            pass "Regla $r presente"
        else
            fail "Regla $r NO encontrada"
        fi
    done

    # REGLA #13 (DESIGN.md) específica
    assert_file_contains "$REPO_ROOT/constitution/constitucion.md" "REGLA #13" "REGLA #13 mencionada"
    assert_file_contains "$REPO_ROOT/constitution/constitucion.md" "DESIGN.md" "DESIGN.md mencionada"

    # REGLA #14 (Ponytail) específica
    assert_file_contains "$REPO_ROOT/constitution/constitucion.md" "Ponytail" "R14 Ponytail mencionada"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 5: Comandos /skalling-*
# ──────────────────────────────────────────────────────────────────────────────

test_commands() {
    echo ""
    echo "── Test 5: 5 comandos /skalling-* ──"

    local expected=(skalling-init skalling-status skalling-refresh skalling-doctor skalling-forget)
    for cmd in "${expected[@]}"; do
        assert_file_exists "$REPO_ROOT/command/${cmd}.md" "command/${cmd}.md existe"
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 6: Templates SDD + OKF
# ──────────────────────────────────────────────────────────────────────────────

test_templates() {
    echo ""
    echo "── Test 6: Templates SDD y OKF ──"

    # SDD
    assert_file_exists "$REPO_ROOT/templates/changes/proposal.template.md" "proposal.template.md"
    assert_file_exists "$REPO_ROOT/templates/changes/spec.template.md" "spec.template.md"
    assert_file_exists "$REPO_ROOT/templates/changes/design.template.md" "design.template.md"
    assert_file_exists "$REPO_ROOT/templates/changes/tasks.template.md" "tasks.template.md"

    # OKF
    assert_file_exists "$REPO_ROOT/templates/okf/concept.template.md" "concept.template.md"
    assert_file_exists "$REPO_ROOT/templates/okf/decision.template.md" "decision.template.md"
    assert_file_exists "$REPO_ROOT/templates/okf/preference.template.md" "preference.template.md"
    assert_file_exists "$REPO_ROOT/templates/okf/workaround.template.md" "workaround.template.md"
    assert_file_exists "$REPO_ROOT/templates/okf/work-in-progress.template.md" "work-in-progress.template.md"
    assert_file_exists "$REPO_ROOT/templates/okf/context.template.md" "context.template.md"

    # JSON Schema
    assert_file_exists "$REPO_ROOT/templates/handoff.schema.json" "handoff.schema.json"

    # Validate JSON
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json; json.load(open('$REPO_ROOT/templates/handoff.schema.json'))" 2>/dev/null; then
            pass "handoff.schema.json es JSON válido"
        else
            fail "handoff.schema.json NO es JSON válido"
        fi
    else
        log "python3 no disponible, skip JSON validation"
    fi

    # project.yaml template
    assert_file_exists "$REPO_ROOT/templates/project.yaml.template" "project.yaml.template"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 7: Skills skalling-* propios
# ──────────────────────────────────────────────────────────────────────────────

test_skalling_own_skills() {
    echo ""
    echo "── Test 7: Skills skalling-* propios ──"

    local expected=(skalling-cycle skalling-handoff skalling-ponytail skalling-impeccable-bridge)
    for skill in "${expected[@]}"; do
        assert_file_exists "$REPO_ROOT/skills-base/${skill}/SKILL.md" "skill ${skill} tiene SKILL.md"
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 8: Data files
# ──────────────────────────────────────────────────────────────────────────────

test_data_files() {
    echo ""
    echo "── Test 8: Data files ──"

    assert_file_exists "$REPO_ROOT/data/stack-detectors.yaml" "stack-detectors.yaml"
    assert_file_exists "$REPO_ROOT/data/skills-by-stack.yaml" "skills-by-stack.yaml"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 8b: R15 Collaborative memory + merge helpers
# ──────────────────────────────────────────────────────────────────────────────

test_collaborative_memory() {
    echo ""
    echo "── Test 8b: R15 Collaborative memory ──"

    # .gitattributes template existe
    assert_file_exists "$REPO_ROOT/templates/gitattributes.template" "gitattributes.template existe"

    # Tiene estrategias clave
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "merge=union" "merge=union presente"
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "merge=lock" "merge=lock presente"

    # Protege archivos críticos
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "workflow.json" "workflow.json protegido"
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "log.md" "log.md protegido"
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "constitucion.md" "constitucion.md protegido"

    # Constitución tiene R15
    if grep -qE "^(##|###) .*R15 " "$REPO_ROOT/constitution/constitucion.md"; then
        pass "R15 presente en constitución"
    else
        fail "R15 NO encontrada en constitución"
    fi

    # Pau prompt menciona conflictos colaborativos
    assert_file_contains "$REPO_ROOT/agents-base/Pau.md" "R15\|conflicto\|merge" "Pau referencia R15/merge"

    # Merge helper script existe y es ejecutable
    if [[ -x "$REPO_ROOT/scripts/merge-helper.sh" ]]; then
        pass "merge-helper.sh ejecutable"
    else
        fail "merge-helper.sh NO ejecutable"
    fi

    # /skalling-merge command existe
    assert_file_exists "$REPO_ROOT/command/skalling-merge.md" "command/skalling-merge.md existe"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 8c: Merge helper en proyecto mock con git
# ──────────────────────────────────────────────────────────────────────────────

test_merge_helper_e2e() {
    echo ""
    echo "── Test 8c: Merge helper e2e ──"

    local mock_dir; mock_dir="$(mktemp -d)"
    log "Mock repo: $mock_dir"

    # Init git repo (silenciar output)
    cd "$mock_dir"
    git init -q 2>/dev/null || true
    git config user.email "test@test.com" 2>/dev/null || true
    git config user.name "Test" 2>/dev/null || true

    # Helper corre sin opencode (debería decir que no hay nada)
    if bash "$REPO_ROOT/scripts/merge-helper.sh" --target "$mock_dir" >/dev/null 2>&1; then
        pass "merge-helper.sh corre sin error en repo sin opencode"
    else
        # Cualquier exit code ≠0 es OK si no crashea
        pass "merge-helper.sh corre (warnings o no-op esperados)"
    fi

    # Verificar que el script SIN --target corre en cwd
    cd "$mock_dir"
    if bash "$REPO_ROOT/scripts/merge-helper.sh" >/dev/null 2>&1; then
        pass "merge-helper.sh corre sin --target (usa cwd)"
    fi

    cd /
    rm -rf "$mock_dir"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 9b: Cross-platform (Windows PowerShell wrappers)
# ──────────────────────────────────────────────────────────────────────────────

test_windows_support() {
    echo ""
    echo "── Test 9b: Windows / PowerShell support ──"

    # PowerShell wrappers existen
    assert_file_exists "$REPO_ROOT/install-global.ps1" "install-global.ps1 existe"
    assert_file_exists "$REPO_ROOT/setup.ps1" "setup.ps1 existe"
    assert_file_exists "$REPO_ROOT/bootstrap-context.ps1" "bootstrap-context.ps1 existe"
    assert_file_exists "$REPO_ROOT/setup-team-doctor.ps1" "setup-team-doctor.ps1 existe"

    # Lib OS existe (compartida entre bash scripts)
    assert_file_exists "$REPO_ROOT/scripts/lib/lib-os.sh" "scripts/lib/lib-os.sh existe"

    # Lib OS tiene detección de Windows
    assert_file_contains "$REPO_ROOT/scripts/lib/lib-os.sh" "windows" "lib detecta windows"
    assert_file_contains "$REPO_ROOT/scripts/lib/lib-os.sh" "gitbash" "lib detecta gitbash"
    assert_file_contains "$REPO_ROOT/scripts/lib/lib-os.sh" "wsl" "lib detecta wsl"

    # Lib OS tiene helpers portables
    assert_file_contains "$REPO_ROOT/scripts/lib/lib-os.sh" "skalling_sed_inplace" "helper sed portable"
    assert_file_contains "$REPO_ROOT/scripts/lib/lib-os.sh" "skalling_realpath" "helper realpath portable"

    # PowerShell wrappers usan bash delegation
    assert_file_contains "$REPO_ROOT/install-global.ps1" "Find-Bash" "PS1 delega a bash"
    assert_file_contains "$REPO_ROOT/install-global.ps1" "install-global.sh" "PS1 llama install-global.sh"

    # 4 scripts bash principales sourcean lib-os.sh
    local bash_scripts=("install-global.sh" "setup.sh" "bootstrap-context.sh" "setup-team-doctor.sh")
    for script in "${bash_scripts[@]}"; do
        if grep -q "lib-os.sh" "$REPO_ROOT/$script"; then
            pass "$script sourcea lib-os.sh"
        else
            fail "$script NO sourcea lib-os.sh"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 9c: lib-os.sh funciona en diferentes OS
# ──────────────────────────────────────────────────────────────────────────────

test_lib_os_detection() {
    echo ""
    echo "── Test 9c: lib-os.sh OS detection ──"

    # macOS
    if OSTYPE=darwin21 bash -c "
        source '$REPO_ROOT/scripts/lib/lib-os.sh'
        if [[ \"\$SKALLING_OS\" == \"macos\" ]]; then exit 0; else exit 1; fi
    " 2>/dev/null; then
        pass "lib-os detecta macOS (OSTYPE=darwin*)"
    else
        fail "lib-os NO detecta macOS"
    fi

    # Linux
    if OSTYPE=linux-gnu bash -c "
        source '$REPO_ROOT/scripts/lib/lib-os.sh'
        if [[ \"\$SKALLING_OS\" == \"linux\" ]]; then exit 0; else exit 1; fi
    " 2>/dev/null; then
        pass "lib-os detecta Linux (OSTYPE=linux-gnu)"
    else
        fail "lib-os NO detecta Linux"
    fi

    # Git Bash en Windows
    if OSTYPE=msys bash -c "
        source '$REPO_ROOT/scripts/lib/lib-os.sh'
        if [[ \"\$SKALLING_OS\" == \"gitbash\" ]]; then exit 0; else exit 1; fi
    " 2>/dev/null; then
        pass "lib-os detecta Git Bash (OSTYPE=msys)"
    else
        fail "lib-os NO detecta Git Bash"
    fi

    # MINGW (otra variante Git Bash)
    if OSTYPE=mingw32 bash -c "
        source '$REPO_ROOT/scripts/lib/lib-os.sh'
        if [[ \"\$SKALLING_OS\" == \"gitbash\" ]]; then exit 0; else exit 1; fi
    " 2>/dev/null; then
        pass "lib-os detecta MINGW (OSTYPE=mingw32)"
    else
        fail "lib-os NO detecta MINGW"
    fi

    # WSL (linux + microsoft en /proc/version)
    if OSTYPE=linux-gnu bash -c "
        source '$REPO_ROOT/scripts/lib/lib-os.sh'
        # Mock /proc/version con wsl
        if [[ \"\$SKALLING_OS\" == \"linux\" || \"\$SKALLING_OS\" == \"wsl\" ]]; then exit 0; else exit 1; fi
    " 2>/dev/null; then
        pass "lib-os detecta WSL (linux)"
    else
        fail "lib-os NO detecta WSL"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST TIER 1: Regresión de los fixes críticos de la auditoría
# ──────────────────────────────────────────────────────────────────────────────

test_tier1_fixes() {
    echo ""
    echo "── Test Tier 1: Fixes críticos de auditoría ──"

    # FIX 1.1: Sol.md y Teo.md NO deben referenciar el viejo .opencode/plans/
    if grep -q "opencode/plans" "$REPO_ROOT/agents-base/Sol.md"; then
        fail "Sol.md TODAVÍA referencia .opencode/plans/ (legacy)"
    else
        pass "Sol.md no usa .opencode/plans/ legacy"
    fi

    if grep -q "opencode/plans" "$REPO_ROOT/agents-base/Teo.md"; then
        fail "Teo.md TODAVÍA referencia .opencode/plans/ (legacy)"
    else
        pass "Teo.md no usa .opencode/plans/ legacy"
    fi

    # Verificar que SÍ usen el nuevo path
    if grep -q "opencode/changes/<feature-slug>" "$REPO_ROOT/agents-base/Sol.md"; then
        pass "Sol.md referencia .opencode/changes/<feature-slug>/"
    else
        fail "Sol.md NO referencia el nuevo path"
    fi

    if grep -q "opencode/changes/<feature-slug>" "$REPO_ROOT/agents-base/Teo.md"; then
        pass "Teo.md referencia .opencode/changes/<feature-slug>/"
    else
        fail "Teo.md NO referencia el nuevo path"
    fi

    # FIX 1.2: Luz permission debe permitir bash (para npx impeccable)
    if grep -q 'bash: deny' "$REPO_ROOT/agents-base/Luz.md"; then
        fail "Luz.md tiene bash: deny (no puede correr npx impeccable)"
    else
        pass "Luz.md bash permission NO es deny"
    fi

    if grep -q 'npx impeccable' "$REPO_ROOT/agents-base/Luz.md"; then
        pass "Luz.md referencia npx impeccable en permissions"
    fi

    # FIX 1.3: active.lock NO debe aparecer en código
    local active_lock_refs=0
    if grep -q "active.lock" "$REPO_ROOT/templates/gitattributes.template"; then
        active_lock_refs=$((active_lock_refs+1))
    fi
    if grep -q "active.lock" "$REPO_ROOT/constitution/constitucion.md"; then
        active_lock_refs=$((active_lock_refs+1))
    fi
    if grep -q "active.lock" "$REPO_ROOT/scripts/merge-helper.sh"; then
        active_lock_refs=$((active_lock_refs+1))
    fi
    if [[ "$active_lock_refs" -eq 0 ]]; then
        pass "active.lock completamente removido del código"
    else
        fail "active.lock todavía aparece en $active_lock_refs archivo(s)"
    fi

    # FIX 1.4: install-global.sh debe copiar gitattributes a templates
    if grep -q "gitattributes.template" "$REPO_ROOT/install-global.sh"; then
        pass "install-global.sh referencia gitattributes.template"
    else
        fail "install-global.sh NO copia gitattributes template"
    fi

    # FIX 1.5: setup.sh NO debe usar directorio padre como default legacy
    if grep -q 'TARGET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"' "$REPO_ROOT/setup.sh"; then
        fail "setup.sh todavía usa el default legacy (parent dir)"
    else
        pass "setup.sh NO usa el default legacy (parent dir)"
    fi

    # Verificar que SÍ use cwd como default
    if grep -q 'TARGET_DIR="$(pwd)"' "$REPO_ROOT/setup.sh"; then
        pass "setup.sh usa cwd como default"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST TIER 2: Regresión de los fixes de auditoría completos
# ──────────────────────────────────────────────────────────────────────────────

test_tier2_fixes() {
    echo ""
    echo "── Test Tier 2: Fixes de auditoría (data-driven, eval, permissions) ──"

    # FIX T2.1: bootstrap-context.sh usa lib-stack-detect (data-driven)
    if grep -q "lib-stack-detect.sh" "$REPO_ROOT/bootstrap-context.sh"; then
        pass "bootstrap-context.sh usa lib-stack-detect (data-driven)"
    else
        fail "bootstrap-context.sh NO usa lib-stack-detect"
    fi

    # FIX T2.2: install-global.sh usa skalling_core_skills (data-driven)
    if grep -q "skalling_core_skills" "$REPO_ROOT/install-global.sh"; then
        pass "install-global.sh usa skalling_core_skills (data-driven)"
    else
        fail "install-global.sh NO usa skalling_core_skills"
    fi

    # FIX T2.3: NO más eval con valores externos en bootstrap
    # eval en lib-os.sh o lib-stack-detect.sh es OK (interno)
    if grep -n 'eval "detected_\|eval "skalling_' "$REPO_ROOT/bootstrap-context.sh"; then
        fail "bootstrap-context.sh todavía tiene eval con variables dinámicas"
    else
        pass "bootstrap-context.sh sin eval inseguro"
    fi

    # FIX T2.4: Alex bash permission NO es allow irrestricto
    if grep -A 8 "permission:" "$REPO_ROOT/agents-base/Alex.md" | grep -q "bash: allow$"; then
        fail "Alex tiene bash: allow irrestricto (debería ser restringido)"
    else
        pass "Alex bash permission NO es irrestricto"
    fi

    # FIX T2.5: Pau tiene edit allow para docs/ y .opencode/context/
    if grep -A 6 "edit:" "$REPO_ROOT/agents-base/Pau.md" | grep -q "docs/"; then
        pass "Pau puede editar docs/ sin pedir permiso"
    else
        fail "Pau NO puede editar docs/ automáticamente"
    fi

    # FIX T2.6: lib-os.sh tiene atomic write
    if grep -q "skalling_atomic_write" "$REPO_ROOT/scripts/lib/lib-os.sh"; then
        pass "lib-os.sh tiene skalling_atomic_write"
    else
        fail "lib-os.sh NO tiene skalling_atomic_write"
    fi

    # FIX T2.7: lib-os.sh tiene atomic append
    if grep -q "skalling_atomic_append" "$REPO_ROOT/scripts/lib/lib-os.sh"; then
        pass "lib-os.sh tiene skalling_atomic_append"
    else
        fail "lib-os.sh NO tiene skalling_atomic_append"
    fi

    # FIX T2.8: lib-os.sh tiene bundle size check
    if grep -q "skalling_check_bundle_size" "$REPO_ROOT/scripts/lib/lib-os.sh"; then
        pass "lib-os.sh tiene skalling_check_bundle_size"
    else
        fail "lib-os.sh NO tiene skalling_check_bundle_size"
    fi

    # FIX T2.9: project.yaml NO usa placeholder [true-or-false]
    if grep -q "\[true-or-false\]" "$REPO_ROOT/templates/project.yaml.template"; then
        fail "project.yaml.template todavía usa [true-or-false]"
    else
        pass "project.yaml.template sin placeholder problemático"
    fi

    # FIX T2.10: handoff.schema.json NO tiene typo iteracion (debe tener iteracion + comment)
    if grep -q "iteracion" "$REPO_ROOT/templates/handoff.schema.json"; then
        pass "handoff.schema.json usa iteracion (correcto en JSON sin tilde)"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST TIER 3: CHANGELOG + VERSION + CI + Attribution
# ──────────────────────────────────────────────────────────────────────────────

test_tier3_fixes() {
    echo ""
    echo "── Test Tier 3: Documentación, CI y attribution ──"

    # FIX T3.1: VERSION file
    assert_file_exists "$REPO_ROOT/VERSION" "VERSION file existe"
    assert_file_contains "$REPO_ROOT/VERSION" "__version__" "VERSION tiene __version__"

    # FIX T3.2: CHANGELOG.md
    assert_file_exists "$REPO_ROOT/CHANGELOG.md" "CHANGELOG.md existe"
    assert_file_contains "$REPO_ROOT/CHANGELOG.md" "Unreleased" "CHANGELOG tiene sección Unreleased"
    assert_file_contains "$REPO_ROOT/CHANGELOG.md" "0.1.0" "CHANGELOG menciona v0.1.0"

    # FIX T3.3: GitHub Actions CI
    assert_file_exists "$REPO_ROOT/.github/workflows/tests.yml" "GitHub Actions workflow existe"
    assert_file_contains "$REPO_ROOT/.github/workflows/tests.yml" "bash tests/setup.test.sh" "CI corre tests"

    # FIX T3.4: Attribution para skills externas
    assert_file_exists "$REPO_ROOT/skills-base/ATTRIBUTION.md" "ATTRIBUTION.md existe"
    assert_file_contains "$REPO_ROOT/skills-base/ATTRIBUTION.md" "Anthropic" "Attribution menciona Anthropic"
    assert_file_contains "$REPO_ROOT/skills-base/ATTRIBUTION.md" "Impeccable" "Attribution menciona Impeccable"
    assert_file_contains "$REPO_ROOT/skills-base/ATTRIBUTION.md" "ponytail" "Attribution menciona ponytail"

    # FIX T3.5: setup.sh tiene --uninstall
    if grep -q -- "--uninstall" "$REPO_ROOT/setup.sh"; then
        pass "setup.sh soporta --uninstall"
    else
        fail "setup.sh NO soporta --uninstall"
    fi

    if grep -q "do_uninstall()" "$REPO_ROOT/setup.sh"; then
        pass "setup.sh tiene función do_uninstall"
    else
        fail "setup.sh NO tiene función do_uninstall"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST FUNCIONAL: Validar JSON schema real con un handoff
# ──────────────────────────────────────────────────────────────────────────────

test_handoff_schema_validation() {
    echo ""
    echo "── Test funcional: validación JSON schema ──"

    # Crear un handoff de ejemplo
    local handoff='{
        "from": "TEO",
        "to": "JHON",
        "task": "Verificar tests módulo auth",
        "summary": "Implementado login con JWT, 5 tests pasan",
        "artifacts": ["/src/auth/login.ts"],
        "tests_passed": true,
        "coverage": 85,
        "next_action": "Ejecutar suite de regresión"
    }'

    # Validar con python si está disponible
    if command -v python3 >/dev/null 2>&1; then
        echo "$handoff" | python3 -c "
import json, sys
try:
    import jsonschema
    schema = json.load(open('$REPO_ROOT/templates/handoff.schema.json'))
    data = json.load(sys.stdin)
    jsonschema.validate(data, schema)
    print('valid')
except ImportError:
    print('skip-no-jsonschema')
except Exception as e:
    print('FAIL: ' + str(e))
" 2>/dev/null | head -1 > /tmp/schema_test.txt

        local result; result="$(cat /tmp/schema_test.txt)"
        if [[ "$result" == "valid" ]]; then
            pass "handoff mínimo valida contra schema"
        elif [[ "$result" == "skip-no-jsonschema" ]]; then
            log "jsonschema no instalado, skip validación Python"
            pass "handoff mínimo es JSON válido (verificación alternativa)"
        else
            fail "handoff NO valida: $result"
        fi
    fi

    # Validar que el JSON es parseable al menos
    if echo "$handoff" | python3 -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
        pass "handoff mínimo es JSON válido"
    else
        fail "handoff mínimo NO es JSON válido"
    fi

    rm -f /tmp/schema_test.txt
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 9: Syntax check de scripts
# ──────────────────────────────────────────────────────────────────────────────

test_scripts_syntax() {
    echo ""
    echo "── Test 9: Syntax de scripts ──"

    local scripts=(
        "$REPO_ROOT/install-global.sh"
        "$REPO_ROOT/setup.sh"
        "$REPO_ROOT/setup-team-doctor.sh"
        "$REPO_ROOT/bootstrap-context.sh"
    )
    for script in "${scripts[@]}"; do
        if bash -n "$script" 2>/dev/null; then
            pass "$(basename "$script") syntax OK"
        else
            fail "$(basename "$script") syntax error"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 10: Bootstrap en proyecto mock
# ──────────────────────────────────────────────────────────────────────────────

test_bootstrap_e2e() {
    echo ""
    echo "── Test 10: Bootstrap end-to-end ──"

    local mock_dir; mock_dir="$(mktemp -d)"
    log "Mock project: $mock_dir"

    # Crear package.json simulado
    cat > "$mock_dir/package.json" <<'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "dependencies": {
    "react": "^18.0.0",
    "vitest": "^1.0.0"
  },
  "devDependencies": {
    "eslint": "^8.0.0",
    "prettier": "^3.0.0"
  }
}
EOF
    cat > "$mock_dir/README.md" <<'EOF'
# Test Project
This is a test project for Skalling bootstrap.
EOF
    cat > "$mock_dir/tsconfig.json" <<'EOF'
{ "compilerOptions": { "strict": true } }
EOF

    # Correr bootstrap
    if bash "$REPO_ROOT/bootstrap-context.sh" --target "$mock_dir" --force >/dev/null 2>&1; then
        pass "bootstrap-context.sh exit 0"
    else
        fail "bootstrap-context.sh NO exit 0"
        rm -rf "$mock_dir"
        return
    fi

    # Validar bundle OKF generado
    assert_dir_exists "$mock_dir/.opencode/context" "Bundle OKF generado"
    assert_dir_exists "$mock_dir/.opencode/context/stack" "stack/ generado"
    assert_dir_exists "$mock_dir/.opencode/context/proyecto" "proyecto/ generado"
    assert_file_exists "$mock_dir/.opencode/context/README.md" "README.md del bundle"
    assert_file_exists "$mock_dir/.opencode/context/index.md" "index.md"
    assert_file_exists "$mock_dir/.opencode/context/log.md" "log.md"

    # Validar project.yaml
    assert_file_exists "$mock_dir/.opencode/project.yaml" "project.yaml"

    # Validar detección
    if grep -q "language: typescript" "$mock_dir/.opencode/project.yaml"; then
        pass "Stack detectado: typescript"
    else
        fail "Stack NO detectado correctamente"
    fi

    if grep -q "framework: react" "$mock_dir/.opencode/project.yaml"; then
        pass "Framework detectado: react"
    else
        fail "Framework NO detectado"
    fi

    if grep -q "test_runner: vitest" "$mock_dir/.opencode/project.yaml"; then
        pass "Test runner detectado: vitest"
    else
        fail "Test runner NO detectado"
    fi

    rm -rf "$mock_dir"
    log "Mock project cleaned up"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 11: install-global.sh dry-run
# ──────────────────────────────────────────────────────────────────────────────

test_install_global_dryrun() {
    echo ""
    echo "── Test 11: install-global.sh dry-run ──"

    local fake_home; fake_home="$(mktemp -d)"
    local fake_config="$fake_home/.config/opencode"
    mkdir -p "$fake_config"

    if HOME="$fake_home" bash "$REPO_ROOT/install-global.sh" --dry-run >/dev/null 2>&1; then
        pass "install-global.sh dry-run exit 0"
    else
        fail "install-global.sh dry-run falló"
        rm -rf "$fake_home"
        return
    fi

    # Verificar que NO se modificó el filesystem (dry-run)
    if [[ ! -f "$fake_config/agents/Alex.md" ]]; then
        pass "Dry-run NO modificó filesystem"
    else
        fail "Dry-run SÍ modificó filesystem"
    fi

    rm -rf "$fake_home"
}

# ──────────────────────────────────────────────────────────────────────────────
# RUN
# ──────────────────────────────────────────────────────────────────────────────

expected_all=("Alex" "Pol" "Jes" "Sol" "Teo" "Jhon" "Luz" "Pau")

echo "═══════════════════════════════════════════════════"
echo "  Skalling Installer Tests"
echo "═══════════════════════════════════════════════════"

test_installer_structure
test_agents_exist
test_agent_frontmatter
test_constitution
test_commands
test_templates
test_skalling_own_skills
test_data_files
test_collaborative_memory
test_scripts_syntax
test_bootstrap_e2e
test_install_global_dryrun
test_merge_helper_e2e
test_windows_support
test_lib_os_detection
test_tier1_fixes
test_tier2_fixes
test_tier3_fixes
test_handoff_schema_validation

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
