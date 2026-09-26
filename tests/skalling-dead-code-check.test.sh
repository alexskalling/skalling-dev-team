#!/usr/bin/env bash
# tests/skalling-dead-code-check.test.sh — skalling-dead-code-check.sh debe
# encontrar scripts/plugins instalables que ningún agente, comando, skill,
# hook u otro script invoca de verdad. Motivo: pasó dos veces en la misma
# sesión sin que nada lo señalara (skalling-context-cache.sh instalado y
# nunca llamado; teamdb-task-groups.sh construido y sin wire hasta que un
# humano lo notó).
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
CHECKER="$ROOT/scripts/skalling-dead-code-check.sh"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

FIXTURE="$(mktemp -d)"
trap '[ -n "$FIXTURE" ] && [ -d "$FIXTURE" ] && rm -rf -- "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/scripts" "$FIXTURE/agents-base" "$FIXTURE/command" \
         "$FIXTURE/plugins/lib" "$FIXTURE/skills-base/una-skill" \
         "$FIXTURE/scripts/hooks" "$FIXTURE/tests"

# used-by-agent.sh: un agente lo corre -> NO debe aparecer como huérfano.
cat > "$FIXTURE/scripts/used-by-agent.sh" <<'EOF'
#!/usr/bin/env bash
echo used-by-agent
EOF
cat > "$FIXTURE/agents-base/Alex.md" <<'EOF'
---
description: test
---
bash "$SKALLING_ROOT/scripts/used-by-agent.sh"
EOF

# used-by-command.sh: un comando /skalling-* lo corre -> NO huérfano.
cat > "$FIXTURE/scripts/used-by-command.sh" <<'EOF'
#!/usr/bin/env bash
echo used-by-command
EOF
cat > "$FIXTURE/command/skalling-x.md" <<'EOF'
---
description: test
---
bash "$SK_ROOT/scripts/used-by-command.sh"
EOF

# used-by-other-script.sh: otro script real lo invoca -> NO huérfano.
cat > "$FIXTURE/scripts/used-by-other-script.sh" <<'EOF'
#!/usr/bin/env bash
echo used-by-other-script
EOF
cat > "$FIXTURE/scripts/caller.sh" <<'EOF'
#!/usr/bin/env bash
bash "$(dirname "$0")/used-by-other-script.sh"
EOF

# used-by-skill.sh: un SKILL.md lo instruye -> NO huérfano.
cat > "$FIXTURE/scripts/used-by-skill.sh" <<'EOF'
#!/usr/bin/env bash
echo used-by-skill
EOF
cat > "$FIXTURE/skills-base/una-skill/SKILL.md" <<'EOF'
Correr: bash ~/.config/opencode/scripts/used-by-skill.sh
EOF

# only-in-tests.sh: SOLO un test lo llama -> SÍ debe aparecer como huérfano
# (exactamente el estado de teamdb-task-groups.sh antes de que teamdb-plan.sh
# lo invocara: probado, nunca conectado a un flujo real).
cat > "$FIXTURE/scripts/only-in-tests.sh" <<'EOF'
#!/usr/bin/env bash
echo only-in-tests
EOF
cat > "$FIXTURE/tests/only-in-tests.test.sh" <<'EOF'
#!/usr/bin/env bash
bash "$ROOT/scripts/only-in-tests.sh"
EOF

# truly-orphaned.sh: no lo referencia nada, en ningún lado.
cat > "$FIXTURE/scripts/truly-orphaned.sh" <<'EOF'
#!/usr/bin/env bash
echo truly-orphaned
EOF

# allowlisted-fake.sh: no lo referencia nada, pero está en el allowlist del
# checker real (probamos con uno de los dos nombres reales, migrate-plans-md-
# to-db.sh, para no duplicar la lista de excepciones acá).
cp "$FIXTURE/scripts/truly-orphaned.sh" "$FIXTURE/scripts/migrate-plans-md-to-db.sh"

# Archivos raíz mínimos para que el checker no se caiga buscándolos (deben
# existir, aunque estén vacíos, y NO deben mencionar por accidente el nombre
# de truly-orphaned.sh/only-in-tests.sh).
touch "$FIXTURE/install-global.sh" "$FIXTURE/setup.sh" "$FIXTURE/setup-team-doctor.sh" "$FIXTURE/bootstrap-context.sh"

set +e
OUT="$(bash "$CHECKER" --root "$FIXTURE" 2>&1)"
RC=$?
set -e

if [ "$RC" = "1" ]; then
  assert_pass "exit 1 cuando hay huérfanos reales"
else
  assert_fail "exit 1 cuando hay huérfanos reales" "rc=$RC out=$OUT"
fi

for used in used-by-agent.sh used-by-command.sh used-by-other-script.sh used-by-skill.sh; do
  if grep -q "$used" <<< "$OUT"; then
    assert_fail "$used no aparece como huérfano (tiene caller real)" "out=$OUT"
  else
    assert_pass "$used no aparece como huérfano (tiene caller real)"
  fi
done

if grep -q "only-in-tests.sh" <<< "$OUT"; then
  assert_pass "only-in-tests.sh SÍ aparece como huérfano (solo lo prueba un test, no lo usa nada real)"
else
  assert_fail "only-in-tests.sh SÍ aparece como huérfano (solo lo prueba un test, no lo usa nada real)" "out=$OUT"
fi

if grep -q "truly-orphaned.sh" <<< "$OUT"; then
  assert_pass "truly-orphaned.sh SÍ aparece como huérfano"
else
  assert_fail "truly-orphaned.sh SÍ aparece como huérfano" "out=$OUT"
fi

if grep -q "migrate-plans-md-to-db.sh" <<< "$OUT"; then
  assert_fail "migrate-plans-md-to-db.sh no aparece (está en el allowlist)" "out=$OUT"
else
  assert_pass "migrate-plans-md-to-db.sh no aparece (está en el allowlist)"
fi

# Caso sin huérfanos: exit 0.
FIXTURE_CLEAN="$(mktemp -d)"
mkdir -p "$FIXTURE_CLEAN/scripts" "$FIXTURE_CLEAN/agents-base"
cat > "$FIXTURE_CLEAN/scripts/x.sh" <<'EOF'
echo x
EOF
cat > "$FIXTURE_CLEAN/agents-base/Alex.md" <<'EOF'
bash scripts/x.sh
EOF
touch "$FIXTURE_CLEAN/install-global.sh" "$FIXTURE_CLEAN/setup.sh" "$FIXTURE_CLEAN/setup-team-doctor.sh" "$FIXTURE_CLEAN/bootstrap-context.sh"
if bash "$CHECKER" --root "$FIXTURE_CLEAN" >/dev/null 2>&1; then
  assert_pass "exit 0 cuando no hay huérfanos"
else
  assert_fail "exit 0 cuando no hay huérfanos"
fi
rm -rf "$FIXTURE_CLEAN"

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$CHECKER" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "skalling-dead-code-check.sh shellcheck 0 errores"
  else
    assert_fail "skalling-dead-code-check.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
