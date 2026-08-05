#!/usr/bin/env bash
# tests/handoff-schema-validation.test.sh — Condicionales del handoff schema (T-3.3)
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() {
  local name="$1"
  echo "✓ $name"
  PASS=$((PASS+1))
}

assert_fail() {
  local name="$1"
  local detail="${2:-}"
  echo "✗ $name${detail:+ — $detail}"
  FAIL=$((FAIL+1))
}

# Localizar un python con jsonschema (system primero, luego .venv del repo)
PY=""
if python3 -c "import jsonschema" 2>/dev/null; then
  PY="python3"
elif "$ROOT/.venv/bin/python" -c "import jsonschema" 2>/dev/null; then
  PY="$ROOT/.venv/bin/python"
fi

if [ -z "$PY" ]; then
  echo "FAIL: jsonschema no instalado (pip install jsonschema o crear .venv)" >&2
  echo "PASS=0 FAIL=1"
  exit 1
fi
echo "usando $PY"

OUT="$("$PY" - "$ROOT/templates/handoff.schema.json" <<'EOF'
import json, sys
import jsonschema

schema = json.load(open(sys.argv[1]))

fails = []

# 1. SOL → TEO sin project_context debe FALLAR
bad_teo_handoff = {
    "from": "SOL", "to": "TEO",
    "task": "Implement login JWT",
    "summary": "Build the login module with TDD.",
    "next_action": "Run task 1 of the plan with TDD."
}
try:
    jsonschema.validate(bad_teo_handoff, schema)
    fails.append("TEO handoff sin project_context aceptado")
except jsonschema.ValidationError:
    pass

# 2. TEO → JHON sin verification debe FALLAR
bad_jhon_handoff = {
    "from": "TEO", "to": "JHON",
    "task": "Verify module tests",
    "summary": "Login implemented with TDD; 8 tests pass.",
    "next_action": "Run full suite.",
    "project_context": {"stack": {"language": "ts"}}
}
try:
    jsonschema.validate(bad_jhon_handoff, schema)
    fails.append("JHON handoff sin verification aceptado")
except jsonschema.ValidationError:
    pass

# 3. Handoff válido pasa
good = {
    "from": "SOL", "to": "TEO",
    "task": "Implement login JWT",
    "summary": "Build the login module with TDD.",
    "next_action": "Run task 1 of the plan with TDD.",
    "project_context": {
        "stack": {"language": "ts", "test_runner": "vitest"},
        "has_ui": True,
        "design_system_exists": False,
        "okf_bundle_valid": True
    }
}
try:
    jsonschema.validate(good, schema)
except jsonschema.ValidationError as e:
    fails.append("handoff válido rechazado: %s" % e.message)

if fails:
    print("FAIL: " + "; ".join(fails))
    sys.exit(1)
print("OK: condicionales correctos")
EOF
)"
RC=$?

if [ "$RC" -eq 0 ]; then
  assert_pass "schema condicional (if/then) correcto"
else
  assert_fail "schema condicional (if/then) correcto" "$OUT"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
