#!/usr/bin/env bash
# tests/skalling-privacy.test.sh — skalling-privacy.sh marca un proyecto
# como "interno" (memoria compartida vía git, comportamiento de siempre) o
# "externo" (la memoria de Skalling nunca se commitea ni se pushea).
#
# Motivo: por diseño Skalling commitea una fotografía completa de TeamDB
# (db/teamdb/team.dump.sql) para compartir memoria en equipo. En un proyecto
# ajeno (de un cliente, no de la propia empresa) eso filtra cómo trabaja el
# equipo hacia un repositorio que no es propio -- pedido explícito del
# usuario, con la preocupación puntual de que ni la memoria ni los agentes
# queden rastreados por git.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
SCRIPT="$ROOT/scripts/skalling-privacy.sh"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap '[ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"' EXIT

new_project() {
  local dir="$1"
  git init -q "$dir"
  git -C "$dir" config user.email test@test.com
  git -C "$dir" config user.name Test
  printf 'x\n' > "$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
  bash "$ROOT/scripts/teamdb-init.sh" "$dir" >/dev/null 2>&1
}

PROJECT="$TMP/proj"
new_project "$PROJECT"

# ── status antes de elegir nada: distingue "nunca preguntado" de "interno a propósito" ──
OUT_UNSET="$(bash "$SCRIPT" status "$PROJECT")"
if grep -q "sin-configurar" <<< "$OUT_UNSET"; then
  assert_pass "status antes de elegir: sin-configurar (no confundido con 'internal' elegido)"
else
  assert_fail "status antes de elegir: sin-configurar (no confundido con 'internal' elegido)" "out=$OUT_UNSET"
fi

# ── externo: agrega el bloque, guarda el modo ──
OUT_EXT="$(bash "$SCRIPT" external "$PROJECT")"
if grep -q "privacy_mode: external" <<< "$OUT_EXT" && [ -f "$PROJECT/.gitignore" ] \
   && grep -q "^\.opencode/$" "$PROJECT/.gitignore" && grep -q "^db/teamdb/$" "$PROJECT/.gitignore"; then
  assert_pass "external: agrega .opencode/ y db/teamdb/ al .gitignore, guarda el modo"
else
  assert_fail "external: agrega .opencode/ y db/teamdb/ al .gitignore, guarda el modo" "out=$OUT_EXT"
fi

# ── idempotencia: correrlo de nuevo no duplica el bloque ──
bash "$SCRIPT" external "$PROJECT" >/dev/null
BLOCK_COUNT="$(grep -c "modo externo" "$PROJECT/.gitignore")"
if [ "$BLOCK_COUNT" = "1" ]; then
  assert_pass "external corrido dos veces: el bloque no se duplica"
else
  assert_fail "external corrido dos veces: el bloque no se duplica" "count=$BLOCK_COUNT"
fi

# ── alias en español ──
PROJECT_ES="$TMP/proj-es"
new_project "$PROJECT_ES"
bash "$SCRIPT" externo "$PROJECT_ES" >/dev/null
if grep -q "modo externo" "$PROJECT_ES/.gitignore" 2>/dev/null; then
  assert_pass "alias 'externo' (español) funciona igual que 'external'"
else
  assert_fail "alias 'externo' (español) funciona igual que 'external'"
fi
bash "$SCRIPT" interno "$PROJECT_ES" >/dev/null
if ! grep -q "modo externo" "$PROJECT_ES/.gitignore" 2>/dev/null; then
  assert_pass "alias 'interno' (español) funciona igual que 'internal'"
else
  assert_fail "alias 'interno' (español) funciona igual que 'internal'"
fi

# ── volver a interno: saca el bloque, preserva el resto del .gitignore ──
PROJECT2="$TMP/proj2"
new_project "$PROJECT2"
printf 'node_modules/\n*.log\n' > "$PROJECT2/.gitignore"
bash "$SCRIPT" external "$PROJECT2" >/dev/null
bash "$SCRIPT" internal "$PROJECT2" >/dev/null
GITIGNORE_AFTER="$(cat "$PROJECT2/.gitignore")"
if grep -q "node_modules/" <<< "$GITIGNORE_AFTER" && grep -q "\*.log" <<< "$GITIGNORE_AFTER" \
   && ! grep -q "modo externo" <<< "$GITIGNORE_AFTER"; then
  assert_pass "internal: saca SOLO el bloque de Skalling, preserva el resto del .gitignore"
else
  assert_fail "internal: saca SOLO el bloque de Skalling, preserva el resto del .gitignore" "out=$GITIGNORE_AFTER"
fi

# ── aviso si algo ya estaba commiteado ANTES de marcar externo ──
PROJECT3="$TMP/proj3"
new_project "$PROJECT3"
mkdir -p "$PROJECT3/.opencode"
echo 'stack: nextjs' > "$PROJECT3/.opencode/project.yaml"
git -C "$PROJECT3" add .opencode/project.yaml
git -C "$PROJECT3" commit -qm "ya commiteado antes de marcar externo"
OUT_WARN="$(bash "$SCRIPT" external "$PROJECT3" 2>&1)"
if grep -q "AVISO IMPORTANTE" <<< "$OUT_WARN" && grep -q "project.yaml" <<< "$OUT_WARN"; then
  assert_pass "avisa si algo bajo .opencode/ ya estaba commiteado antes de marcar externo"
else
  assert_fail "avisa si algo bajo .opencode/ ya estaba commiteado antes de marcar externo" "out=$OUT_WARN"
fi

# ── sin nada commiteado bajo .opencode/: no hay aviso ──
PROJECT4="$TMP/proj4"
new_project "$PROJECT4"
OUT_NOWARN="$(bash "$SCRIPT" external "$PROJECT4" 2>&1)"
if ! grep -q "AVISO IMPORTANTE" <<< "$OUT_NOWARN"; then
  assert_pass "sin nada commiteado antes: sin aviso de falso positivo"
else
  assert_fail "sin nada commiteado antes: sin aviso de falso positivo" "out=$OUT_NOWARN"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$SCRIPT" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "skalling-privacy.sh shellcheck 0 errores"
  else
    assert_fail "skalling-privacy.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
