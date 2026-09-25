#!/usr/bin/env bash
# tests/teamdb-plan-parallel-groups.test.sh — teamdb-plan.sh anota automática-
# mente en el plan mismo (design_md + plan_history) qué tasks son candidatas
# a paralelo, corriendo teamdb-task-groups.sh al cerrar la creación del plan.
# Antes, esa detección existía como script suelto (teamdb-task-groups.sh)
# pero nadie lo invocaba solo: dependía de que un humano se acordara de
# correrlo a mano y armara los worktrees él mismo — la feature no generaba
# ningún valor real hasta que alguien la usara manualmente.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TEST_DIR="$(mktemp -d)"
trap '[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/.opencode/context"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
DB="$TEST_DIR/.opencode/context/team.db"

# ── 1. Plan con 2 tasks independientes + 1 dependiente de ambas: el plan
#      creado queda anotado con las 3 cosas que un humano hoy tendría que ir
#      a buscar a mano con teamdb-task-groups.sh. ──
cat > "$TEST_DIR/tasks.md" <<'EOF'
- [ ] Crear endpoint A
- [ ] Crear endpoint B
- [ ] Integrar endpoint A y B _depends: [task-crear-endpoint-a, task-crear-endpoint-b]
EOF
OUT="$(bash "$ROOT/scripts/teamdb-plan.sh" "$TEST_DIR" demo-parale "Demo paralelizacion" "$TEST_DIR/tasks.md" --by sol)"
if grep -q "Paralelización" <<< "$OUT"; then
  assert_pass "teamdb-plan.sh imprime la anotación de paralelización al crear el plan"
else
  assert_fail "teamdb-plan.sh imprime la anotación de paralelización al crear el plan" "out=$OUT"
fi

DESIGN="$(sqlite3 "$DB" "SELECT design_md FROM plans WHERE slug='demo-parale'")"
if grep -q "task-crear-endpoint-a, task-crear-endpoint-b" <<< "$DESIGN" \
   && grep -q "bloqueada por task-crear-endpoint-b" <<< "$DESIGN"; then
  assert_pass "design_md del plan queda con las tasks paralelizables y las bloqueadas"
else
  assert_fail "design_md del plan queda con las tasks paralelizables y las bloqueadas" "design_md=$DESIGN"
fi

HISTORY_OP="$(sqlite3 "$DB" "SELECT operation FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='demo-parale') ORDER BY version DESC LIMIT 1")"
if [ "$HISTORY_OP" = "amended" ]; then
  assert_pass "queda un plan_history versionado de la anotación automática (auditable)"
else
  assert_fail "queda un plan_history versionado de la anotación automática (auditable)" "operation=$HISTORY_OP"
fi

# ── 2. Plan trivial (1 sola task, sin dependencias): no hay nada interesante
#      que anotar -- el plan no se ensucia con una nota vacía ni se crea un
#      plan_history de más. ──
cat > "$TEST_DIR/tasks-simple.md" <<'EOF'
- [ ] Unica task del plan
EOF
bash "$ROOT/scripts/teamdb-plan.sh" "$TEST_DIR" demo-simple "Demo simple" "$TEST_DIR/tasks-simple.md" --by sol >/dev/null
DESIGN_SIMPLE="$(sqlite3 "$DB" "SELECT design_md FROM plans WHERE slug='demo-simple'")"
HISTORY_COUNT_SIMPLE="$(sqlite3 "$DB" "SELECT COUNT(*) FROM plan_history WHERE plan_id=(SELECT id FROM plans WHERE slug='demo-simple')")"
if ! grep -q "Paralelización" <<< "$DESIGN_SIMPLE" && [ "$HISTORY_COUNT_SIMPLE" = "1" ]; then
  assert_pass "plan trivial (1 task, sin deps) no recibe ninguna nota ni historial de más"
else
  assert_fail "plan trivial (1 task, sin deps) no recibe ninguna nota ni historial de más" \
    "design_md=$DESIGN_SIMPLE history_count=$HISTORY_COUNT_SIMPLE"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$ROOT/scripts/teamdb-plan.sh" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "teamdb-plan.sh shellcheck 0 errores"
  else
    assert_fail "teamdb-plan.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
