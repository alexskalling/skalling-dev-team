#!/usr/bin/env bash
# tests/install-orphan-cleanup.test.sh — install-global.sh poda scripts
# skalling-*.{sh,py} instalados cuya fuente ya no existe.
#
# Bug real (2026-09-13): el loop de install_scripts() solo copiaba lo que
# existe hoy en scripts/, nunca borraba lo que dejó de existir. Cuando se
# borró skalling-context-cache.sh del repo (script muerto, sin caller real),
# quedó instalado para siempre en instalaciones ya existentes -- confirmado
# en vivo reinstalando sobre ~/.config/opencode real. Mismo patrón que ya se
# había arreglado puntualmente para teamdb-claim-task.sh, ahora generalizado.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

FAKE_HOME="$(mktemp -d)"
trap '[ -n "$FAKE_HOME" ] && [ -d "$FAKE_HOME" ] && rm -rf -- "$FAKE_HOME"' EXIT

HOME="$FAKE_HOME" bash "$ROOT/install-global.sh" --force >/dev/null 2>&1

SCRIPTS_DIR="$FAKE_HOME/.config/opencode/scripts"
GHOST="$SCRIPTS_DIR/skalling-fake-ghost-orphan.sh"
printf '#!/usr/bin/env bash\necho fantasma\n' > "$GHOST"
chmod +x "$GHOST"

HOME="$FAKE_HOME" bash "$ROOT/install-global.sh" >/dev/null 2>&1

if [ ! -f "$GHOST" ]; then
  assert_pass "reinstall poda un skalling-*.sh cuya fuente ya no existe"
else
  assert_fail "reinstall poda un skalling-*.sh cuya fuente ya no existe" "sigue en $GHOST"
fi

if [ -f "$SCRIPTS_DIR/skalling-metrics.sh" ]; then
  assert_pass "reinstall conserva un skalling-*.sh que sí existe en la fuente"
else
  assert_fail "reinstall conserva un skalling-*.sh que sí existe en la fuente"
fi

# Dry-run: detecta el huérfano y lo reporta sin borrar nada de verdad.
touch "$GHOST"
DRY_OUT="$(HOME="$FAKE_HOME" bash "$ROOT/install-global.sh" --dry-run 2>&1)"
if printf '%s' "$DRY_OUT" | grep -q "skalling-fake-ghost-orphan.sh"; then
  assert_pass "dry-run reporta el huérfano sin necesidad de aplicar"
else
  assert_fail "dry-run reporta el huérfano sin necesidad de aplicar"
fi
if [ -f "$GHOST" ]; then
  assert_pass "dry-run no borra nada de verdad"
else
  assert_fail "dry-run no borra nada de verdad" "el huérfano desapareció en modo --dry-run"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
