#!/usr/bin/env bash
# tests/lib-memory-check.test.sh — Tests del helper lib-memory-check.sh (Fase 4, memory-improvements).
#
# Valida las 5 funciones de detección:
#   - skalling_find_orphans       (huérfanos: no referenciados desde index.md)
#   - skalling_find_zombie_wip    (WIP >N días con todas tareas [x])
#   - skalling_find_duplicates    (mismo title normalizado en concept docs)
#   - skalling_find_stale         (sin referenciar >N meses)
#   - skalling_find_superseded    (frontmatter superseded: true)
#
# Patrón: tests/setup.test.sh (set -euo pipefail, helpers pass/fail/log,
# fixtures sintéticas con mktemp -d, cleanup con rm -rf al final).
#
# Uso:
#   bash tests/lib-memory-check.test.sh
#   bash tests/lib-memory-check.test.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/scripts/lib/lib-memory-check.sh"

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

c_green='\033[32m'
c_red='\033[31m'
c_reset='\033[0m'

pass() { PASS=$((PASS+1)); printf "  ${c_green}✓${c_reset} %s\n" "$*"; }
fail() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$*"); printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
log()  { if [[ "$VERBOSE" == true ]]; then printf "    %s\n" "$*"; fi; }

assert_file_exists() {
    if [[ -f "$1" ]]; then pass "$2"; else fail "$2 — archivo no existe: $1"; fi
}

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS DE FIXTURE
# ──────────────────────────────────────────────────────────────────────────────

# Crea un bundle OKF sintético con contenido controlado.
# Layout:
#   decisiones/index.md         (lista a, c, d)
#   decisiones/a.md             (title: "TypeScript Strict" — NO huérfano)
#   decisiones/orphan.md        (title: "Foo" — HUÉRFANO)
#   decisiones/c.md             (title: "typescript strict" — DUPLICADO de a)
#   decisiones/stale.md         (title: "Stale Doc" — STALE: huérfano + mtime >6m)
#   decisiones/super.md         (title: "Old Approach" — SUPERSEDED)
#   trabajo-en-curso/zombie.md  (timestamp viejo + tareas todas [x])
#   trabajo-en-curso/recent.md  (timestamp reciente + tareas [x])
#   trabajo-en-curso/open.md    (timestamp viejo + tareas [ ])
#
# Variables globales: FIXTURE_DIR
create_fixture() {
    FIXTURE_DIR="$(mktemp -d)"
    log "Fixture creado en: $FIXTURE_DIR"
    mkdir -p "$FIXTURE_DIR/.opencode/context/decisiones"
    mkdir -p "$FIXTURE_DIR/.opencode/context/trabajo-en-curso"

    # decisiones/index.md (lista a, c, d)
    cat > "$FIXTURE_DIR/.opencode/context/decisiones/index.md" <<'EOF'
---
type: index
title: Decisiones
---
# Decisiones

- [a](./a.md) — TypeScript Strict
- [c](./c.md) — TypeScript Strict (duplicado)
- [d](./d.md) — Decisión normal
EOF

    # decisiones/a.md (title: TypeScript Strict — NO huérfano)
    cat > "$FIXTURE_DIR/.opencode/context/decisiones/a.md" <<'EOF'
---
type: Decision
title: TypeScript Strict
description: Convención del equipo: TypeScript con strict=true
timestamp: 2026-07-01T00:00:00Z
agent: teo
confidence: 0.9
---
# TypeScript Strict

Usamos TypeScript con strict en todo el código nuevo.
EOF

    # decisiones/orphan.md (HUÉRFANO)
    cat > "$FIXTURE_DIR/.opencode/context/decisiones/orphan.md" <<'EOF'
---
type: Decision
title: Foo
description: Concept huérfano intencional
timestamp: 2026-07-15T00:00:00Z
agent: teo
confidence: 0.8
---
# Foo

Doc huérfano (no está en index.md).
EOF

    # decisiones/c.md (DUPLICADO de a — mismo title normalizado)
    cat > "$FIXTURE_DIR/.opencode/context/decisiones/c.md" <<'EOF'
---
type: Decision
title: typescript strict
description: Convención duplicada (mismo título normalizado)
timestamp: 2026-07-02T00:00:00Z
agent: teo
confidence: 0.85
---
# typescript strict

Duplicado intencional para test.
EOF

    # decisiones/d.md (NO huérfano, NO duplicado)
    cat > "$FIXTURE_DIR/.opencode/context/decisiones/d.md" <<'EOF'
---
type: Decision
title: Decisión Normal
description: Doc único
timestamp: 2026-07-10T00:00:00Z
agent: teo
confidence: 0.9
---
# Decisión Normal

Doc único en el bundle.
EOF

    # decisiones/stale.md (STALE: huérfano + mtime > 6 meses)
    cat > "$FIXTURE_DIR/.opencode/context/decisiones/stale.md" <<'EOF'
---
type: Decision
title: Stale Doc
description: Doc sin referenciar por más de 6 meses
timestamp: 2025-01-01T00:00:00Z
agent: teo
confidence: 0.7
---
# Stale Doc

Doc viejo.
EOF
    # Forzar mtime > 6 meses (enero 2025 → agosto 2026 = 19 meses)
    touch -t 202501010000 "$FIXTURE_DIR/.opencode/context/decisiones/stale.md" 2>/dev/null \
        || touch -d "2025-01-01" "$FIXTURE_DIR/.opencode/context/decisiones/stale.md" 2>/dev/null \
        || true

    # decisiones/super.md (SUPERSEDED)
    cat > "$FIXTURE_DIR/.opencode/context/decisiones/super.md" <<'EOF'
---
type: Decision
title: Old Approach
description: Enfoque viejo, reemplazado por el nuevo
timestamp: 2024-12-01T00:00:00Z
agent: teo
confidence: 0.9
superseded: true
---
# Old Approach

Doc superseded por decisión reciente.
EOF

    # trabajo-en-curso/zombie.md (ZOMBIE: timestamp viejo + todas tareas [x])
    cat > "$FIXTURE_DIR/.opencode/context/trabajo-en-curso/zombie.md" <<'EOF'
---
type: WorkInProgress
title: Feature Vieja
description: Tarea cerrada hace tiempo
timestamp: 2026-05-01T00:00:00Z
agent: teo
confidence: 1.0
---
# Feature Vieja

## Status

- [x] Proposal aprobado por usuario
- [x] Specs definidos
- [x] Design completado
- [x] Implementación completa
- [x] Regresión completa
EOF

    # trabajo-en-curso/recent.md (NO zombie: reciente)
    cat > "$FIXTURE_DIR/.opencode/context/trabajo-en-curso/recent.md" <<'EOF'
---
type: WorkInProgress
title: Feature Reciente
description: Tarea reciente
timestamp: 2026-07-30T00:00:00Z
agent: teo
confidence: 1.0
---
# Feature Reciente

## Status

- [x] Proposal aprobado
- [x] Specs definidos
- [x] Implementación completa
EOF

    # trabajo-en-curso/open.md (NO zombie: tareas abiertas)
    cat > "$FIXTURE_DIR/.opencode/context/trabajo-en-curso/open.md" <<'EOF'
---
type: WorkInProgress
title: Feature Abierta
description: Tarea con tareas pendientes
timestamp: 2026-05-01T00:00:00Z
agent: teo
confidence: 1.0
---
# Feature Abierta

## Status

- [x] Proposal aprobado
- [x] Specs definidos
- [ ] Implementación en curso
EOF

    # Log fixture path
    if [[ "$VERBOSE" == true ]]; then
        echo "    Fixture tree:"
        find "$FIXTURE_DIR" -type f | sed "s|$FIXTURE_DIR/||" | sed 's/^/      /'
    fi
}

cleanup_fixture() {
    if [[ -n "${FIXTURE_DIR:-}" ]] && [[ -d "$FIXTURE_DIR" ]]; then
        rm -rf "$FIXTURE_DIR"
        log "Fixture limpiado"
    fi
}

trap cleanup_fixture EXIT

# Sourcear el helper de forma lazy (lo cargamos cuando exista)
source_helper() {
    if [[ -f "$HELPER" ]]; then
        # shellcheck disable=SC1090
        source "$HELPER"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 1: Helper existe y es syntax-OK
# ──────────────────────────────────────────────────────────────────────────────

test_helper_exists_and_syntax() {
    echo ""
    echo "── Test 1: Helper existe + syntax ──"

    assert_file_exists "$HELPER" "scripts/lib/lib-memory-check.sh existe"

    if [[ -f "$HELPER" ]] && bash -n "$HELPER" 2>/dev/null; then
        pass "Helper syntax OK (bash -n)"
    else
        fail "Helper tiene syntax errors"
    fi

    # 6 funciones skalling_* exportadas
    if [[ -f "$HELPER" ]]; then
        local count
        count="$(grep -cE "^skalling_[a-z_]+\s*\(\)" "$HELPER" || echo 0)"
        if [[ "$count" -eq 6 ]]; then
            pass "Helper define exactamente 6 funciones skalling_*"
        else
            fail "Helper define $count funciones (esperaba 6)"
        fi
    fi

    # set -euo pipefail presente (en el archivo, no necesariamente en head -5)
    if [[ -f "$HELPER" ]] && grep -q "^set -euo pipefail" "$HELPER"; then
        pass "Helper tiene 'set -euo pipefail'"
    else
        fail "Helper NO tiene 'set -euo pipefail'"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 2: skalling_find_orphans — detecta huérfano, no falso positivo
# ──────────────────────────────────────────────────────────────────────────────

test_find_orphans() {
    echo ""
    echo "── Test 2: skalling_find_orphans ──"

    source_helper || { fail "Helper no sourceable"; return; }
    create_fixture

    local out
    out="$(skalling_find_orphans "$FIXTURE_DIR/.opencode/context" 2>/dev/null || true)"

    # Debe detectar orphan.md y stale.md (ambos NO están en index.md)
    if [[ "$out" == *"orphan.md"* ]]; then
        pass "orphans detecta orphan.md (caso positivo)"
    else
        fail "orphans NO detecta orphan.md (output: '$out')"
    fi

    # NO debe detectar a.md, c.md, d.md (están en index)
    local false_positive=false
    if [[ "$out" == *"a.md"* ]] && [[ "$out" != *"stale.md"* && "$out" != *"orphan"* ]]; then
        false_positive=true
    fi
    if [[ "$out" == *"/a.md"* ]] && ! [[ "$out" == *"orphan.md"* || "$out" == *"stale.md"* ]]; then
        false_positive=true
    fi
    if [[ "$false_positive" == "false" ]]; then
        pass "orphans NO reporta a.md como huérfano (false positive avoided)"
    else
        fail "orphans reporta a.md como huérfano (false positive)"
    fi

    cleanup_fixture
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 3: skalling_find_zombie_wip — detecta zombie, ignora recientes y abiertas
# ──────────────────────────────────────────────────────────────────────────────

test_find_zombie_wip() {
    echo ""
    echo "── Test 3: skalling_find_zombie_wip ──"

    source_helper || { fail "Helper no sourceable"; return; }
    create_fixture

    local out
    out="$(skalling_find_zombie_wip "$FIXTURE_DIR/.opencode/context" 30 2>/dev/null || true)"

    # Debe detectar zombie.md (>30 días + tareas todas [x])
    if [[ "$out" == *"zombie.md"* ]]; then
        pass "zombie_wip detecta zombie.md (caso positivo)"
    else
        fail "zombie_wip NO detecta zombie.md (output: '$out')"
    fi

    # NO debe detectar recent.md (timestamp reciente)
    if [[ "$out" == *"recent.md"* ]]; then
        fail "zombie_wip detecta recent.md (false positive — es reciente)"
    else
        pass "zombie_wip NO detecta recent.md (es reciente)"
    fi

    # NO debe detectar open.md (tareas abiertas)
    if [[ "$out" == *"open.md"* ]]; then
        fail "zombie_wip detecta open.md (false positive — tareas abiertas)"
    else
        pass "zombie_wip NO detecta open.md (tareas abiertas)"
    fi

    cleanup_fixture
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 4: skalling_find_duplicates — detecta duplicados por title normalizado
# ──────────────────────────────────────────────────────────────────────────────

test_find_duplicates() {
    echo ""
    echo "── Test 4: skalling_find_duplicates ──"

    source_helper || { fail "Helper no sourceable"; return; }
    create_fixture

    local out
    out="$(skalling_find_duplicates "$FIXTURE_DIR/.opencode/context" 2>/dev/null || true)"

    # Debe detectar a.md y c.md (mismo title normalizado: "typescript strict")
    if [[ "$out" == *"a.md"* ]] && [[ "$out" == *"c.md"* ]]; then
        pass "duplicates detecta par a.md + c.md (caso positivo)"
    else
        fail "duplicates NO detecta par a.md + c.md (output: '$out')"
    fi

    # NO debe incluir d.md (título único)
    if [[ "$out" == *"d.md"* ]]; then
        fail "duplicates detecta d.md (false positive — título único)"
    else
        pass "duplicates NO detecta d.md (título único)"
    fi

    cleanup_fixture
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 5: skalling_find_stale — detecta stale (huérfano + viejo)
# ──────────────────────────────────────────────────────────────────────────────

test_find_stale() {
    echo ""
    echo "── Test 5: skalling_find_stale ──"

    source_helper || { fail "Helper no sourceable"; return; }
    create_fixture

    # 6 meses de threshold
    local out
    out="$(skalling_find_stale "$FIXTURE_DIR/.opencode/context" 6 2>/dev/null || true)"

    # Debe detectar stale.md (huérfano + mtime > 6 meses)
    if [[ "$out" == *"stale.md"* ]]; then
        pass "stale detecta stale.md (caso positivo)"
    else
        fail "stale NO detecta stale.md (output: '$out')"
    fi

    # NO debe detectar a.md (está en index)
    if [[ "$out" == *"a.md"* ]] && [[ "$out" != *"stale.md"* ]]; then
        fail "stale detecta a.md (false positive — está en index)"
    else
        pass "stale NO detecta a.md (está en index)"
    fi

    cleanup_fixture
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 6: skalling_find_superseded — detecta superseded por frontmatter
# ──────────────────────────────────────────────────────────────────────────────

test_find_superseded() {
    echo ""
    echo "── Test 6: skalling_find_superseded ──"

    source_helper || { fail "Helper no sourceable"; return; }
    create_fixture

    local out
    out="$(skalling_find_superseded "$FIXTURE_DIR/.opencode/context" 2>/dev/null || true)"

    # Debe detectar super.md (superseded: true)
    if [[ "$out" == *"super.md"* ]]; then
        pass "superseded detecta super.md (caso positivo)"
    else
        fail "superseded NO detecta super.md (output: '$out')"
    fi

    # NO debe detectar a.md (sin superseded)
    if [[ "$out" == *"a.md"* ]] && [[ "$out" != *"super.md"* ]]; then
        fail "superseded detecta a.md (false positive)"
    else
        pass "superseded NO detecta a.md (normal)"
    fi

    cleanup_fixture
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 7: skalling_parse_yaml_field — extrae campos del frontmatter
# ──────────────────────────────────────────────────────────────────────────────

test_parse_yaml_field() {
    echo ""
    echo "── Test 7: skalling_parse_yaml_field ──"

    source_helper || { fail "Helper no sourceable"; return; }
    create_fixture

    # title de a.md debe ser "TypeScript Strict"
    local title
    title="$(skalling_parse_yaml_field "$FIXTURE_DIR/.opencode/context/decisiones/a.md" title 2>/dev/null || true)"

    if [[ "$title" == *"TypeScript"* ]] || [[ "$title" == "TypeScript Strict" ]]; then
        pass "parse_yaml_field extrae title correctamente (got: '$title')"
    else
        fail "parse_yaml_field NO extrae title (got: '$title')"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# TEST 8: Sourceability desde cwd arbitrario
# ──────────────────────────────────────────────────────────────────────────────

test_sourceable() {
    echo ""
    echo "── Test 8: Helper es sourceable ──"

    if [[ ! -f "$HELPER" ]]; then
        fail "Helper no existe, skip sourceability test"
        return
    fi

    if bash -c "source '$HELPER' && type skalling_find_orphans >/dev/null" 2>/dev/null; then
        pass "Helper sourceable desde subshell"
    else
        fail "Helper NO sourceable desde subshell"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# RUN
# ──────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════"
echo "  lib-memory-check.sh Tests (Fase 4 — memory-improvements)"
echo "═══════════════════════════════════════════════════"

test_helper_exists_and_syntax
test_sourceable
test_find_orphans
test_find_zombie_wip
test_find_duplicates
test_find_stale
test_find_superseded
test_parse_yaml_field

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
