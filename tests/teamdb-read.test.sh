#!/usr/bin/env bash
# tests/teamdb-read.test.sh — teamdb-read.sh acepta el proyecto como último
# argumento posicional, igual que el resto de teamdb-*.sh
#
# Bug real (2026-09-13, sesion de uso en apps/web): teamdb-read.sh exigia
# --project AL PRINCIPIO; cualquier otro script de la familia lo toma al
# FINAL. Un agente probando la convención de los otros scripts pasaba el
# path del proyecto como último argumento y disparaba, sin ninguna pista
# util, "Incorrect number of bindings supplied. The current statement uses
# 0, and there are 1 supplied." -- porque ese argumento se trataba
# ciegamente como bind param del SQL.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

FIXTURE="$(mktemp -d)"
trap '[ -n "$FIXTURE" ] && [ -d "$FIXTURE" ] && rm -rf -- "$FIXTURE"' EXIT
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$FIXTURE" >/dev/null 2>&1
DB="$FIXTURE/.opencode/context/team.db"
sqlite3 "$DB" "INSERT INTO proposals(slug,title,intent_md,status) VALUES('p','P','#i','approved')"

# Caso real que rompía: 0 placeholders '?' + proyecto al final.
OUT1="$(bash "$ROOT/scripts/teamdb-read.sh" "SELECT slug,title FROM proposals" "$FIXTURE" 2>&1)"
if printf '%s' "$OUT1" | grep -q '"slug": "p"'; then
  assert_pass "0 placeholders + proyecto al final: funciona (antes daba 'Incorrect number of bindings')"
else
  assert_fail "0 placeholders + proyecto al final: funciona" "out=$OUT1"
fi

# Un bind param real de 1 placeholder no debe confundirse con proyecto,
# aunque --project ya se haya dado al principio.
OUT2="$(bash "$ROOT/scripts/teamdb-read.sh" --project "$FIXTURE" "SELECT slug FROM proposals WHERE slug=?" "p" 2>&1)"
if printf '%s' "$OUT2" | grep -q '"slug": "p"'; then
  assert_pass "1 placeholder + 1 bind param real: no se reinterpreta como proyecto"
else
  assert_fail "1 placeholder + 1 bind param real: no se reinterpreta como proyecto" "out=$OUT2"
fi

# Falso positivo: 1 placeholder + 1 arg que ES un directorio real. No debe
# tratarse como proyecto porque el conteo de sobrantes es 0, no 1.
sqlite3 "$DB" "INSERT INTO proposals(slug,title,intent_md,status) VALUES('$FIXTURE','Dir como valor','#i','approved')"  # lens:ok: FIXTURE viene de mktemp -d, no de input externo
OUT3="$(PROJECT="$FIXTURE" bash "$ROOT/scripts/teamdb-read.sh" \
  "SELECT slug FROM proposals WHERE slug=?" "$FIXTURE" 2>&1)"
if printf '%s' "$OUT3" | grep -qF "$FIXTURE"; then
  assert_pass "1 placeholder + 1 arg que es directorio real: se usa como bind param, no como proyecto"
else
  assert_fail "1 placeholder + 1 arg que es directorio real: se usa como bind param" "out=$OUT3"
fi

# --project al principio (uso documentado) sigue funcionando.
OUT4="$(bash "$ROOT/scripts/teamdb-read.sh" --project "$FIXTURE" "SELECT COUNT(*) FROM proposals" 2>&1)"
if printf '%s' "$OUT4" | grep -q '"COUNT(\*)": 2'; then
  assert_pass "--project al principio sigue funcionando (compatibilidad)"
else
  assert_fail "--project al principio sigue funcionando" "out=$OUT4"
fi

# Solo INSERT/UPDATE/DELETE siguen rechazados (no es una puerta trasera de escritura).
RC5=0
bash "$ROOT/scripts/teamdb-read.sh" "DELETE FROM proposals" "$FIXTURE" >/dev/null 2>&1 || RC5=$?
if [ "$RC5" != "0" ]; then
  assert_pass "DELETE sigue rechazado (teamdb-read.sh solo acepta SELECT/EXPLAIN)"
else
  assert_fail "DELETE sigue rechazado" "rc=$RC5"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$ROOT/scripts/teamdb-read.sh" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "teamdb-read.sh shellcheck 0 errores"
  else
    assert_fail "teamdb-read.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
