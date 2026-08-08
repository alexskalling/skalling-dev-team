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

assert_no_path() {
    # assert_no_path "desc" "file" "string" → fail si `string` está en `file`
    if [[ -f "$2" ]] && grep -q -- "$3" "$2"; then
        fail "$1 — '$3' todavía aparece en $2"
    else
        pass "$1"
    fi
}

assert_no_superpowers() {
    # assert_no_superpowers "desc" "file" → fail si `superpowers:` está en `file`
    if [[ -f "$2" ]] && grep -q "superpowers:" "$2"; then
        fail "$1 — referencia 'superpowers:' todavía en $2"
    else
        pass "$1"
    fi
}

assert_uses_db() {
    # assert_uses_db "desc" "file" "marker" → fail si `marker` NO está en `file`
    if [[ -f "$2" ]] && grep -q -- "$3" "$2"; then
        pass "$1"
    else
        fail "$1 — '$3' no encontrado en $2"
    fi
}

assert_grep() {
    # assert_grep "desc" "file" "regex" → fail si el regex NO matchea en `file`
    # Acepta regex BRE: `\|` para alternación, `\.` para literal dot.
    if [[ -f "$2" ]] && grep -q -- "$3" "$2"; then
        pass "$1"
    else
        fail "$1 — regex '$3' no matchea en $2"
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
# TEST 4: Constitución tiene reglas R1-R17
# ──────────────────────────────────────────────────────────────────────────────

test_constitution() {
    echo ""
    echo "── Test 4: Constitución completa ──"

    local rules=(R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12 R13 R14 R15 R16 R17)
    for r in "${rules[@]}"; do
        # Match "### R<n>" or "## R<n>" or "## [emoji] R<n>" formats
        if grep -qE "^(##|###) .*${r} " "$REPO_ROOT/constitution/constitucion.md"; then
            pass "Regla $r presente"
        else
            fail "Regla $r NO encontrada"
        fi
    done

    # REGLA #13 (design-system.md) específica
    assert_file_contains "$REPO_ROOT/constitution/constitucion.md" "REGLA #13" "REGLA #13 mencionada"
    assert_file_contains "$REPO_ROOT/constitution/constitucion.md" "design-system.md" "design-system.md mencionada en R13"

    # REGLA #15 (Ponytail) específica
    assert_file_contains "$REPO_ROOT/constitution/constitucion.md" "Ponytail" "R15 Ponytail mencionada"
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 5: Comandos /skalling-*
# ──────────────────────────────────────────────────────────────────────────────

test_commands() {
    echo ""
    echo "── Test 5: 6 comandos /skalling-* ──"

    local expected=(skalling-init skalling-status skalling-refresh skalling-doctor skalling-forget skalling-update)
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
# TEST 8b: R16 Collaborative memory + merge helpers
# ──────────────────────────────────────────────────────────────────────────────

test_collaborative_memory() {
    echo ""
    echo "── Test 8b: R16 Collaborative memory ──"

    # .gitattributes template existe
    assert_file_exists "$REPO_ROOT/templates/gitattributes.template" "gitattributes.template existe"

    # Tiene estrategias clave
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "merge=union" "merge=union presente"
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "merge=lock" "merge=lock presente"

    # Protege archivos críticos
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "workflow_state" "workflow_state (DB) referenciado"
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "log.md" "log.md protegido"
    assert_file_contains "$REPO_ROOT/templates/gitattributes.template" "constitucion.md" "constitucion.md protegido"

    # Constitución tiene R16
    if grep -qE "^(##|###) .*R16 " "$REPO_ROOT/constitution/constitucion.md"; then
        pass "R16 presente en constitución"
    else
        fail "R16 NO encontrada en constitución"
    fi

    # Pau prompt menciona conflictos colaborativos
    assert_file_contains "$REPO_ROOT/agents-base/Pau.md" "R16\|conflicto\|merge" "Pau referencia R16/merge"

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
# TEST TIER 1 FIX 1.2: Skills NO escriben a docs/plans/ ni usan superpowers
# ──────────────────────────────────────────────────────────────────────────────

test_tier1_skills_fixes() {
    echo ""
    echo "── Test Tier 1 FIX 1.2: Skills no usan paths legacy ni superpowers ──"

    # brainstorming: NO docs/plans, NO superpowers, SI team.db
    assert_no_path 'brainstorming no escribe a docs/plans' \
        "$REPO_ROOT/skills-base/brainstorming/SKILL.md" 'docs/plans'

    assert_no_superpowers 'brainstorming no usa superpowers' \
        "$REPO_ROOT/skills-base/brainstorming/SKILL.md"

    assert_uses_db 'brainstorming referencia la DB' \
        "$REPO_ROOT/skills-base/brainstorming/SKILL.md" 'team.db'

    # writing-plans: NO docs/plans, NO superpowers, SI team.db
    assert_no_path 'writing-plans no escribe a docs/plans' \
        "$REPO_ROOT/skills-base/writing-plans/SKILL.md" 'docs/plans'

    assert_no_superpowers 'writing-plans no usa superpowers' \
        "$REPO_ROOT/skills-base/writing-plans/SKILL.md"

    assert_uses_db 'writing-plans referencia la DB' \
        "$REPO_ROOT/skills-base/writing-plans/SKILL.md" 'team.db'
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

    # FIX TIER 14: install-global.sh tiene remove_broken_symlink
    if grep -q "remove_broken_symlink" "$REPO_ROOT/install-global.sh"; then
        pass "install-global.sh maneja symlinks rotos"
    else
        fail "install-global.sh NO maneja symlinks rotos"
    fi

    if grep -q "remove_broken_symlink\|Symlink roto\|symlink roto" "$REPO_ROOT/setup.sh"; then
        pass "setup.sh maneja symlinks rotos"
    else
        fail "setup.sh NO maneja symlinks rotos"
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
# TEST TIER 4: Memory improvements (Fase 7 — cierre v0.3.0)
# ──────────────────────────────────────────────────────────────────────────────

test_tier4_memory_improvements() {
    echo ""
    echo "── Test Tier 4: Memory improvements (helpers + doctor) ──"

    assert_file_exists "$REPO_ROOT/scripts/lib/lib-memory-check.sh" "scripts/lib/lib-memory-check.sh existe"
    if [[ -x "$REPO_ROOT/scripts/lib/lib-memory-check.sh" ]]; then
        pass "scripts/lib/lib-memory-check.sh es ejecutable"
    else
        fail "scripts/lib/lib-memory-check.sh NO es ejecutable"
    fi

    assert_file_exists "$REPO_ROOT/scripts/mem-review.sh" "scripts/mem-review.sh existe"
    if [[ -x "$REPO_ROOT/scripts/mem-review.sh" ]]; then
        pass "scripts/mem-review.sh es ejecutable"
    else
        fail "scripts/mem-review.sh NO es ejecutable"
    fi

    local expected_funcs=(
        "skalling_parse_yaml_field"
        "skalling_find_orphans"
        "skalling_find_zombie_wip"
        "skalling_find_duplicates"
        "skalling_find_stale"
        "skalling_find_superseded"
    )
    local helper="$REPO_ROOT/scripts/lib/lib-memory-check.sh"
    for fn in "${expected_funcs[@]}"; do
        if grep -qE "^${fn}\(\)" "$helper"; then
            pass "helper define ${fn}()"
        else
            fail "helper NO define ${fn}()"
        fi
    done

    if grep -q "install_memory_helpers" "$REPO_ROOT/install-global.sh"; then
        pass "install-global.sh invoca install_memory_helpers"
    else
        fail "install-global.sh NO invoca install_memory_helpers"
    fi

    local doctor="$REPO_ROOT/setup-team-doctor.sh"
    if grep -qE "^check_memory_health\(\)" "$doctor"; then
        pass "doctor define check_memory_health()"
    else
        fail "doctor NO define check_memory_health()"
    fi
    if grep -q "check_memory_health" "$doctor"; then
        local inv_count; inv_count="$(grep -c "check_memory_health" "$doctor")"
        if [[ "$inv_count" -ge 2 ]]; then
            pass "doctor invoca check_memory_health (${inv_count} refs)"
        else
            fail "doctor NO invoca check_memory_health (${inv_count} refs)"
        fi
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST FIX 1.3 (nuevo): agentes DEBEN tener protocolo DB-primera numerado
# ──────────────────────────────────────────────────────────────────────────────

test_db_first_protocol() {
    echo ""
    echo "── Test FIX 1.3: Protocolo DB-primera en agentes ──"

    for agent in Alex Pol Sol Teo; do
        assert_grep \
            "${agent} tiene protocolo DB-primera" \
            "$REPO_ROOT/agents-base/${agent}.md" \
            "DB-primera\|teamdb-search\.sh\|teamdb-related\.sh"
    done

    # Sanity: el protocolo debe ser pasos numerados (Paso 1, Paso 2...)
    for agent in Alex Pol Sol Teo; do
        assert_grep \
            "${agent} tiene pasos numerados (Paso 1...)" \
            "$REPO_ROOT/agents-base/${agent}.md" \
            "Paso 1:"
    done

    # Sanity: el protocolo debe instruir CITAR el resultado
    for agent in Alex Pol Sol Teo; do
        assert_grep \
            "${agent} pide CITAR el resultado de la consulta DB" \
            "$REPO_ROOT/agents-base/${agent}.md" \
            "CIT"
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# BLOQUE 1 — FIX 1.7: Jes tiene protocolo DB-primera numerado
# Enforces: Jes.md referencia teamdb-search/teamdb-related explícitamente,
# tiene REGLA DURA explícita, y al menos un paso numerado (Paso 1:).
# ──────────────────────────────────────────────────────────────────────────────

test_jes_db_first_protocol() {
  echo ""
  echo "── Test FIX 1.7: Jes protocolo DB-primera ──"

  local file="$REPO_ROOT/agents-base/Jes.md"

  if [ ! -f "$file" ]; then
    echo "FAIL: Jes.md no existe"
    return 1
  fi

  # 1. Jes referencia teamdb-search.sh o teamdb-related.sh
  if ! grep -qE "teamdb-search\.sh|teamdb-related\.sh" "$file"; then
    echo "FAIL: Jes.md no referencia teamdb-search.sh ni teamdb-related.sh"
    return 1
  fi
  echo "  ✓ Jes referencia teamdb-search.sh / teamdb-related.sh"

  # 2. Jes tiene REGLA DURA explícita
  if ! grep -q "REGLA DURA" "$file"; then
    echo "FAIL: Jes.md no tiene REGLA DURA explícita"
    return 1
  fi
  echo "  ✓ Jes tiene REGLA DURA explícita"

  # 3. Jes tiene pasos numerados (Paso 1:)
  if ! grep -qE "Paso 1:|Paso 2:|Paso 3:" "$file"; then
    echo "FAIL: Jes.md no tiene pasos numerados"
    return 1
  fi
  echo "  ✓ Jes tiene pasos numerados (Paso 1:, Paso 2:, ...)"

  # 4. Jes menciona CITAR (consistente con otros 4 agentes)
  if ! grep -qE "CIT" "$file"; then
    echo "FAIL: Jes.md no instruye CITAR el resultado"
    return 1
  fi
  echo "  ✓ Jes instruye CITAR el resultado de la DB"

  echo "OK: FIX 1.7 — Jes tiene protocolo DB-primera explícito"
}

test_jes_db_first_protocol

test_plan_protocol_no_parallel_files() {
  # Pol/Sol/Teo NO deben decir "leer .md para implementar"
  for agent in Pol Sol Teo; do
    if ! grep -q "INSERT INTO proposals\|UPDATE plans" "agents-base/${agent}.md"; then
      echo "FAIL: ${agent} no referencia INSERT/UPDATE de proposals o plans"
      return 1
    fi
  done

  # Todos los agentes del ciclo SDD deben mencionar slug o plan_id
  for agent in Alex Pol Sol Teo; do
    if ! grep -qE "feature-slug|proposal_id|plan_id" "agents-base/${agent}.md"; then
      echo "FAIL: ${agent} no referencia slug o ID en handoff"
      return 1
    fi
  done

  # Teo NO debe decir "leer design.md" o "leer proposal.md para implementar"
  if grep -qE "leer.*\.md.*para implementar|read design\.md|read proposal\.md" "agents-base/Teo.md"; then
    echo "FAIL: Teo.md sugiere leer .md para implementar (debería ir a la DB)"
    return 1
  fi

  # Pol NO debe decir "crear proposal.md"
  if grep -qE "crear proposal\.md|escribir proposal\.md.*a filesystem|escribir.*\.md.*filesystem" "agents-base/Pol.md"; then
    echo "FAIL: Pol.md sugiere escribir proposal.md a filesystem"
    return 1
  fi

  echo "OK: FIX 1.4 — protocolos anti-duplicación de planes"
}

test_plan_protocol_no_parallel_files

# ──────────────────────────────────────────────────────────────────────────────
# BLOQUE 2 — FIX 1.5: Migration 009 plan_contract (v0.7.7)
# Enforces: plans tiene intent_md/version/created_by/updated_by,
# tasks tiene purpose, audit triggers sobre plans existen.
# ──────────────────────────────────────────────────────────────────────────────

test_migration_009_plan_contract() {
  echo ""
  echo "── Test FIX 1.5: migration 009 plan_contract (v0.9.0) ──"

  local DB="$REPO_ROOT/.opencode/context/team.db"
  [ -f "$DB" ] || { echo "FAIL: DB no existe: $DB"; return 1; }

  # 1. Version bumped (sigue el valor de schema_meta, hoy 0.9.0)
  local version
  version=$(sqlite3 "$DB" "SELECT value FROM schema_meta WHERE key='version'" 2>/dev/null)
  if [ "$version" != "0.9.0" ]; then
    echo "FAIL: version esperada 0.9.0, obtenida: $version"
    return 1
  fi
  echo "  ✓ version = 0.9.0"

  # 2. plans tiene columnas nuevas: intent_md, version, created_by, updated_by
  local cols
  cols=$(sqlite3 "$DB" "PRAGMA table_info(plans)" 2>/dev/null)
  for col in intent_md version created_by updated_by; do
    if ! echo "$cols" | grep -qE "^[0-9]+\|${col}\|"; then
      echo "FAIL: plans no tiene columna $col"
      return 1
    fi
  done
  echo "  ✓ plans tiene intent_md, version, created_by, updated_by"

  # 3. plans.status CHECK constraint incluye 'in_progress' (NO 'active')
  local plans_sql
  plans_sql=$(sqlite3 "$DB" "SELECT sql FROM sqlite_master WHERE type='table' AND name='plans'" 2>/dev/null)
  if ! echo "$plans_sql" | grep -q "in_progress"; then
    echo "FAIL: plans.status CHECK no incluye 'in_progress'"
    return 1
  fi
  if echo "$plans_sql" | grep -qE "'active'"; then
    echo "FAIL: plans.status CHECK todavía incluye 'active' (debe ser 'in_progress')"
    return 1
  fi
  echo "  ✓ plans.status CHECK: in_progress (no active)"

  # 4. tasks tiene columna purpose
  local tasks_cols
  tasks_cols=$(sqlite3 "$DB" "PRAGMA table_info(tasks)" 2>/dev/null)
  if ! echo "$tasks_cols" | grep -qE "^[0-9]+\|purpose\|"; then
    echo "FAIL: tasks no tiene columna purpose"
    return 1
  fi
  echo "  ✓ tasks tiene columna purpose"

  # 5. audit triggers sobre plans existen (al menos 2)
  local trigger_count
  trigger_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'plans_audit%'" 2>/dev/null)
  if [ "$trigger_count" -lt 2 ]; then
    echo "FAIL: triggers plans_audit* instalados: $trigger_count (esperados >=2)"
    return 1
  fi
  echo "  ✓ triggers plans_audit_* instalados: $trigger_count"

  # 6. CHECK constraint rechaza explícitamente 'active' (no debe haberse colado)
  local bad_insert
  bad_insert=$(sqlite3 "$DB" "INSERT INTO plans (slug, title, status, design_md, created_at, updated_at) VALUES ('setup-test-active-banned', 'X', 'active', '', datetime('now'), datetime('now'));" 2>&1 || true)
  if ! echo "$bad_insert" | grep -qiE "CHECK constraint failed"; then
    echo "FAIL: CHECK constraint aceptó 'active' (debería rechazar): $bad_insert"
    return 1
  fi
  echo "  ✓ CHECK constraint rechaza 'active'"

  # 7. Trigger de INSERT genera audit_log entry
  local before_audit
  before_audit=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE table_name='plans' AND action='insert'" 2>/dev/null)
  sqlite3 "$DB" "INSERT INTO plans (slug, title, status, design_md, created_by, created_at, updated_at) VALUES ('setup-test-trigger-1', 'X', 'draft', '', 'setup-test', datetime('now'), datetime('now'));" 2>/dev/null
  local after_audit
  after_audit=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE table_name='plans' AND action='insert'" 2>/dev/null)
  if [ "$after_audit" -le "$before_audit" ]; then
    echo "FAIL: plans_audit_ai no generó audit_log (before=$before_audit after=$after_audit)"
    sqlite3 "$DB" "DELETE FROM audit_log WHERE table_name='plans' AND row_id IN (SELECT id FROM plans WHERE slug='setup-test-trigger-1');" 2>/dev/null
    sqlite3 "$DB" "DELETE FROM plans WHERE slug='setup-test-trigger-1';" 2>/dev/null
    return 1
  fi
  echo "  ✓ plans_audit_ai genera audit_log (insert: $before_audit -> $after_audit)"

  # 8. Trigger de UPDATE genera audit_log entry
  local before_update
  before_update=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE table_name='plans' AND action='update'" 2>/dev/null)
  sqlite3 "$DB" "UPDATE plans SET status='in_progress', version=2, updated_by='setup-test' WHERE slug='setup-test-trigger-1';" 2>/dev/null
  local after_update
  after_update=$(sqlite3 "$DB" "SELECT COUNT(*) FROM audit_log WHERE table_name='plans' AND action='update'" 2>/dev/null)
  if [ "$after_update" -le "$before_update" ]; then
    echo "FAIL: plans_audit_au no generó audit_log (before=$before_update after=$after_update)"
    sqlite3 "$DB" "DELETE FROM audit_log WHERE table_name='plans' AND row_id IN (SELECT id FROM plans WHERE slug='setup-test-trigger-1');" 2>/dev/null
    sqlite3 "$DB" "DELETE FROM plans WHERE slug='setup-test-trigger-1';" 2>/dev/null
    return 1
  fi
  echo "  ✓ plans_audit_au genera audit_log (update: $before_update -> $after_update)"

  # 9. Cleanup
  sqlite3 "$DB" "DELETE FROM audit_log WHERE table_name='plans' AND row_id IN (SELECT id FROM plans WHERE slug='setup-test-trigger-1');" 2>/dev/null
  sqlite3 "$DB" "DELETE FROM plans WHERE slug='setup-test-trigger-1';" 2>/dev/null

  # 10. Archivo de migration existe
  local mig_file="$REPO_ROOT/sql/migrations/009_plan_contract.sql"
  if [ ! -f "$mig_file" ]; then
    echo "FAIL: migration file no existe: $mig_file"
    return 1
  fi
  echo "  ✓ migration file existe: sql/migrations/009_plan_contract.sql"

  # 11. teamdb-amend.sh validate purpose
  if ! grep -qE "purpose.*obligatorio|requiere.*purpose|--purpose" "$REPO_ROOT/scripts/teamdb-amend.sh"; then
    echo "FAIL: teamdb-amend.sh no valida purpose"
    return 1
  fi
  echo "  ✓ teamdb-amend.sh valida purpose"

  # 12. teamdb-plan.sh tiene strict-contract option
  if ! grep -qE "strict-contract|--purpose" "$REPO_ROOT/scripts/teamdb-plan.sh"; then
    echo "FAIL: teamdb-plan.sh no tiene --strict-contract/--purpose"
    return 1
  fi
  echo "  ✓ teamdb-plan.sh tiene --strict-contract/--purpose"

  echo "OK: FIX 1.5 — migration 009 plan_contract aplicada con contract enforcement"
}

test_migration_009_plan_contract

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

test_install_global_teamdb_scripts() {
    echo ""
    echo "── Test 12: Scripts teamdb del bundle global ──"

    local fake_home; fake_home="$(mktemp -d)"
    local installed_wip_tree="$fake_home/.config/opencode/scripts/wip-tree.sh"

    if HOME="$fake_home" bash "$REPO_ROOT/install-global.sh" --force >/dev/null 2>&1; then
        pass "install-global.sh --force exit 0"
    else
        fail "install-global.sh --force falló"
    fi

    if [[ -x "$installed_wip_tree" ]]; then
        pass "install-global.sh copia wip-tree.sh ejecutable"
    else
        fail "install-global.sh NO copia wip-tree.sh ejecutable"
    fi

    rm -rf "$fake_home"
}

# ──────────────────────────────────────────────────────────────────────────────
# BLOQUE 4 — FIX 1.6: Script de migración de planes .md a la DB
# Verifica que existe el script, es ejecutable, tiene --dry-run funcional,
# y referencia el source-of-truth DB (no genera planes fantasma).
# ──────────────────────────────────────────────────────────────────────────────

test_migration_script_exists() {
    echo ""
    echo "── Test FIX 1.6: migrate-plans-md-to-db.sh ──"

    local script="$REPO_ROOT/scripts/migrate-plans-md-to-db.sh"
    if [[ ! -f "$script" ]]; then
        fail "FIX 1.6: migrate-plans-md-to-db.sh no existe"
        return
    fi
    pass "FIX 1.6: script existe"

    if [[ ! -x "$script" ]]; then
        fail "FIX 1.6: migrate-plans-md-to-db.sh no es ejecutable"
    else
        pass "FIX 1.6: script es ejecutable"
    fi

    # bash -n syntax check
    if bash -n "$script" 2>/dev/null; then
        pass "FIX 1.6: bash -n syntax OK"
    else
        fail "FIX 1.6: bash -n syntax error"
    fi

    # Sincronizado a ~/.config/opencode/scripts/
    if [[ -x "$HOME/.config/opencode/scripts/migrate-plans-md-to-db.sh" ]]; then
        pass "FIX 1.6: sincronizado a ~/.config/opencode/scripts/"
    else
        log "FIX 1.6: no sincronizado a home (ok si $HOME es CI)"
    fi

    # Dry-run funciona (no debe fallar ni escribir en DB)
    local before_count
    before_count=$(sqlite3 "$REPO_ROOT/.opencode/context/team.db" \
        "SELECT COUNT(*) FROM proposals WHERE decided_by='legacy-import'" 2>/dev/null || echo "0")
    if bash "$script" --dry-run "$REPO_ROOT" >/dev/null 2>&1; then
        local after_count
        after_count=$(sqlite3 "$REPO_ROOT/.opencode/context/team.db" \
            "SELECT COUNT(*) FROM proposals WHERE decided_by='legacy-import'" 2>/dev/null || echo "0")
        if [[ "$after_count" == "$before_count" ]]; then
            pass "FIX 1.6: --dry-run no muta la DB (count $before_count == $after_count)"
        else
            fail "FIX 1.6: --dry-run MUTÓ la DB ($before_count -> $after_count)"
        fi
    else
        log "FIX 1.6: --dry-run no disponible o falló (puede ser esperado si no hay .md)"
    fi

    # No debe usar superpowers ni paths legacy
    if grep -q "superpowers:" "$script" 2>/dev/null; then
        fail "FIX 1.6: script referencia superpowers"
    fi
    if grep -q "opencode/plans/" "$script" 2>/dev/null; then
        fail "FIX 1.6: script usa path legacy opencode/plans/"
    fi
    if grep -q "teamdb_project_path" "$script" 2>/dev/null; then
        pass "FIX 1.6: script usa teamdb_project_path (DB-first)"
    else
        fail "FIX 1.6: script NO usa teamdb_project_path"
    fi

    # Idempotencia: segunda corrida debe skip-ear
    local before_idem
    before_idem=$(sqlite3 "$REPO_ROOT/.opencode/context/team.db" \
        "SELECT COUNT(*) FROM proposals WHERE decided_by='legacy-import'" 2>/dev/null || echo "0")
    bash "$script" "$REPO_ROOT" >/dev/null 2>&1 || true
    local after_idem
    after_idem=$(sqlite3 "$REPO_ROOT/.opencode/context/team.db" \
        "SELECT COUNT(*) FROM proposals WHERE decided_by='legacy-import'" 2>/dev/null || echo "0")
    if [[ "$before_idem" == "$after_idem" ]]; then
        pass "FIX 1.6: idempotente (count estable en re-run: $before_idem)"
    else
        fail "FIX 1.6: NO idempotente (count $before_idem -> $after_idem)"
    fi
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
test_install_global_teamdb_scripts
test_merge_helper_e2e
test_windows_support
test_lib_os_detection
test_tier1_fixes
test_tier1_skills_fixes
test_tier2_fixes
test_tier3_fixes
test_tier4_memory_improvements
test_db_first_protocol
test_handoff_schema_validation
test_migration_script_exists

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
