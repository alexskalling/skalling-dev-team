#!/usr/bin/env bash
# tests/teamdb-init-migration-bookkeeping.test.sh — teamdb-init.sh no debe
# marcar el bootstrap como exitoso si falla la escritura que registra una
# migration como aplicada. Encontrado en vivo en un proyecto real (actas3.0.0):
# la migration 009_plan_contract corrió y comiteó sus cambios reales, pero la
# escritura posterior a applied_migrations no se registró (motivo exacto no
# reconstruible -- lock, timeout, interrupción). Como _run_sql() no chequeaba
# el resultado de esa escritura, el bootstrap "tuvo éxito" igual, y cada
# bootstrap futuro reintentaba 009 contra un schema que YA tenía sus cambios,
# fallando siempre con "duplicate column name".
#
# No se puede deshacer una migration ya comiteada desde acá -- lo único que
# se puede hacer es fallar fuerte para que alguien se entere, en vez de dejarlo
# pasar en silencio. Este test simula esa escritura fallando (reemplazando
# teamdb_exec.py por un stub que siempre sale con error) y confirma que
# teamdb-init.sh ahora sí falla, en vez de reportar éxito.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap '[ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"' EXIT

# Sandbox: copia de scripts/ + sql/ con teamdb_exec.py reemplazado por un
# stub que siempre falla -- así la escritura de bookkeeping (que pasa por
# teamdb_exec.py) falla, sin tocar el repo real ni depender de manipular el
# PATH (que en este entorno rompe binarios de macOS simlinkeados a mano).
SANDBOX="$TMP/sandbox"
mkdir -p "$SANDBOX"
cp -r "$ROOT/scripts" "$SANDBOX/scripts"
cp -r "$ROOT/sql" "$SANDBOX/sql"
cat > "$SANDBOX/scripts/teamdb_exec.py" <<'PY'
#!/usr/bin/env python3
import sys
sys.exit(1)
PY
chmod +x "$SANDBOX/scripts/teamdb_exec.py"

# ── caso 1: bookkeeping falla en el camino "baseline" (proyecto nuevo) ──
PROJECT1="$TMP/project1"
git init -q "$PROJECT1"
git -C "$PROJECT1" config user.email test@test.com
git -C "$PROJECT1" config user.name Test
printf 'x\n' > "$PROJECT1/README.md"
git -C "$PROJECT1" add -A
git -C "$PROJECT1" commit -qm init

set +e
OUT1="$(bash "$SANDBOX/scripts/teamdb-init.sh" "$PROJECT1" 2>&1)"
RC1=$?
set -e
if [ "$RC1" != "0" ] && grep -q "no se pudo registrar" <<< "$OUT1"; then
  assert_pass "bookkeeping falla en baseline (proyecto nuevo) → teamdb-init.sh falla, no reporta éxito"
else
  assert_fail "bookkeeping falla en baseline (proyecto nuevo) → teamdb-init.sh falla, no reporta éxito" "rc=$RC1 out=$OUT1"
fi

DB1="$PROJECT1/.opencode/context/team.db"
APPLIED_COUNT1="$(sqlite3 "$DB1" "SELECT COUNT(*) FROM applied_migrations" 2>/dev/null || echo "?")"
if [ "$APPLIED_COUNT1" = "0" ]; then
  assert_pass "applied_migrations queda vacía (no queda un registro a medias)"
else
  assert_fail "applied_migrations queda vacía (no queda un registro a medias)" "count=$APPLIED_COUNT1"
fi

# ── caso 2: con teamdb_exec.py real (sin fallas inyectadas), el bootstrap
#      sigue funcionando normal -- el fix no rompe el camino feliz ──
REAL_SANDBOX="$TMP/real-sandbox"
mkdir -p "$REAL_SANDBOX"
cp -r "$ROOT/scripts" "$REAL_SANDBOX/scripts"
cp -r "$ROOT/sql" "$REAL_SANDBOX/sql"
PROJECT2="$TMP/project2"
git init -q "$PROJECT2"
git -C "$PROJECT2" config user.email test@test.com
git -C "$PROJECT2" config user.name Test
printf 'x\n' > "$PROJECT2/README.md"
git -C "$PROJECT2" add -A
git -C "$PROJECT2" commit -qm init

if bash "$REAL_SANDBOX/scripts/teamdb-init.sh" "$PROJECT2" >/dev/null 2>&1; then
  assert_pass "sin fallas inyectadas, el bootstrap sigue funcionando normal (sin regresión)"
else
  assert_fail "sin fallas inyectadas, el bootstrap sigue funcionando normal (sin regresión)"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$ROOT/scripts/teamdb-init.sh" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "teamdb-init.sh shellcheck 0 errores"
  else
    assert_fail "teamdb-init.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
