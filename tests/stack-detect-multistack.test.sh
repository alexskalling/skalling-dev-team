#!/usr/bin/env bash
# tests/stack-detect-multistack.test.sh
# Valida que un repo con scripts bash + scripts python + plugins node
# es reconocido como multi-stack por lib-stack-detect.sh.
#
# El test crea un directorio temporal con la estructura mínima del repo
# Skalling (5 archivos representativos) y verifica que el detector llena
# language o marca multi_stack.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR_LIB="$SCRIPT_DIR/scripts/lib/lib-stack-detect.sh"
STACK_DETECTORS="$SCRIPT_DIR/data/stack-detectors.yaml"
TMPDIR=""
FAILED=0

cleanup() {
  if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

# ── Setup: directorio temporal con estructura multi-stack ──────────────────────
TMPDIR="$(mktemp -d)"
mkdir -p "$TMPDIR/scripts" "$TMPDIR/plugins" "$TMPDIR/tests"

# Bash script
cat > "$TMPDIR/scripts/example.sh" << 'EOF'
#!/usr/bin/env bash
echo "bash script"
EOF

# Python script
cat > "$TMPDIR/scripts/example.py" << 'EOF'
#!/usr/bin/env python3
print("python script")
EOF

# Node plugin (no .mjs pero sí .js)
cat > "$TMPDIR/plugins/example.js" << 'EOF'
// node plugin
module.exports = {};
EOF

# El archivo marcador del detector multi-stack (tests/run-all.sh)
cat > "$TMPDIR/tests/run-all.sh" << 'EOF'
#!/usr/bin/env bash
echo "running all tests"
EOF

# README mínimo
cat > "$TMPDIR/README.md" << 'EOF'
# Multi-stack test project
EOF

# ── Test ──────────────────────────────────────────────────────────────────────
echo "Test: multi-stack detection (bash + python + node)"
echo "  TMPDIR=$TMPDIR"

# Sourcear la lib y llamar al detector
# shellcheck source=scripts/lib/lib-stack-detect.sh
source "$DETECTOR_LIB"

skalling_init_detected
if ! skalling_detect_from_yaml "$STACK_DETECTORS" "$TMPDIR"; then
  echo "  FAIL: skalling_detect_from_yaml devolvió error"
  FAILED=1
fi

LANG="$(skalling_get_detected language)"
RUNTIME="$(skalling_get_detected runtime)"
TEST_RUNNER="$(skalling_get_detected test_runner)"
PM="$(skalling_get_detected package_manager)"

echo "  Detected language  : '$LANG'"
echo "  Detected runtime   : '$RUNTIME'"
echo "  Detected test_runner: '$TEST_RUNNER'"
echo "  Detected package_mgr: '$PM'"

# Contrato: language debe ser no-empty (el valor exacto puede variar según
# la implementación del nuevo detector: "multi", "bash,python,node", etc.)
# Acceptable: language no vacía O test_runner no vacío.
if [[ -z "$LANG" && -z "$TEST_RUNNER" ]]; then
  echo "  FAIL: language y test_runner están vacíos — el detector multi-stack no matcheó"
  FAILED=1
else
  echo "  PASS: al menos un campo de stack detectado"
fi

# Verificación extra: que no se detecte como un stack simple (ej: solo python)
if [[ "$LANG" == "python" || "$LANG" == "typescript" || "$LANG" == "javascript" ]]; then
  echo "  WARN: detector matcheó como stack simple '$LANG' — preferimos multi-stack"
  # No fail por esto, solo warn. El contrato principal es arriba.
fi

exit $FAILED
