#!/usr/bin/env bash
# tests/audit-log-actor.test.sh — Validación plumbing TEAMDB_ACTOR (T-1.7)
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

# 1. lib-teamdb.sh referencia TEAMDB_ACTOR (fundación)
if grep -q "TEAMDB_ACTOR" "$ROOT/scripts/lib/lib-teamdb.sh"; then
  assert_pass "lib-teamdb.sh referencia TEAMDB_ACTOR"
else
  assert_fail "lib-teamdb.sh referencia TEAMDB_ACTOR" "no aparece"
fi

# 2. Existe helper _actor_or_unknown
if grep -q "_actor_or_unknown" "$ROOT/scripts/lib/lib-teamdb.sh"; then
  assert_pass "lib-teamdb.sh define _actor_or_unknown"
else
  assert_fail "lib-teamdb.sh define _actor_or_unknown" "no aparece"
fi

# 3. teamdb_init_project setea TEAMDB_ACTOR default
if grep -q "TEAMDB_ACTOR=" "$ROOT/scripts/lib/lib-teamdb.sh"; then
  assert_pass "lib-teamdb.sh setea TEAMDB_ACTOR (default)"
else
  assert_fail "lib-teamdb.sh setea TEAMDB_ACTOR (default)" "no aparece"
fi

# 4. teamdb-init.sh setea TEAMDB_ACTOR
LIB="$ROOT/scripts/lib/lib-teamdb.sh"
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$LIB"

unset TEAMDB_ACTOR
TMP_INIT="$(mktemp -d)"
teamdb_init_project "$TMP_INIT" >/dev/null 2>&1
if [ -n "${TEAMDB_ACTOR:-}" ]; then
  assert_pass "teamdb_init_project setea TEAMDB_ACTOR si no existe"
else
  assert_fail "teamdb_init_project setea TEAMDB_ACTOR si no existe" "TEAMDB_ACTOR vacio"
fi
rm -rf "$TMP_INIT"

# 5. teamdb_init_project respeta TEAMDB_ACTOR existente
unset TEAMDB_ACTOR
export TEAMDB_ACTOR=pol
TMP_INIT2="$(mktemp -d)"
teamdb_init_project "$TMP_INIT2" >/dev/null 2>&1
if [ "${TEAMDB_ACTOR:-}" = "pol" ]; then
  assert_pass "teamdb_init_project respeta TEAMDB_ACTOR existente"
else
  assert_fail "teamdb_init_project respeta TEAMDB_ACTOR existente" "TEAMDB_ACTOR=${TEAMDB_ACTOR:-}"
fi
rm -rf "$TMP_INIT2"

# 6. _actor_or_unknown retorna TEAMDB_ACTOR si existe
TEAMDB_ACTOR=teo
result="$(_actor_or_unknown)"
if [ "$result" = "teo" ]; then
  assert_pass "_actor_or_unknown retorna TEAMDB_ACTOR"
else
  assert_fail "_actor_or_unknown retorna TEAMDB_ACTOR" "result=$result"
fi

# 7. _actor_or_unknown retorna 'unknown' si no existe
unset TEAMDB_ACTOR
result="$(_actor_or_unknown)"
if [ "$result" = "unknown" ]; then
  assert_pass "_actor_or_unknown retorna 'unknown' si no existe"
else
  assert_fail "_actor_or_unknown retorna 'unknown' si no existe" "result=$result"
fi

# 8. teamdb-init.sh setea TEAMDB_ACTOR en su ejecución
unset TEAMDB_ACTOR
TMP="$(mktemp -d)"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TMP" >/dev/null 2>&1
# Verificamos que el helper de lib se llamo: el archivo se inicializo y existe DB
if [ -f "$TMP/.opencode/context/team.db" ]; then
  assert_pass "teamdb-init.sh inicializa DB"
else
  assert_fail "teamdb-init.sh inicializa DB" "DB no existe"
fi
rm -rf "$TMP"

# 9. bootstrap-context.sh exporta TEAMDB_ACTOR
if grep -q "TEAMDB_ACTOR" "$ROOT/bootstrap-context.sh" 2>/dev/null; then
  assert_pass "bootstrap-context.sh exporta TEAMDB_ACTOR"
else
  assert_fail "bootstrap-context.sh exporta TEAMDB_ACTOR" "no aparece (puede ser opcional, marcado como warning)"
fi

# 10. shellcheck no se queja
SHELLCHECK_RC=0
shellcheck "$ROOT/scripts/lib/lib-teamdb.sh" >/dev/null 2>&1 || SHELLCHECK_RC=$?
if [ "$SHELLCHECK_RC" = "0" ]; then
  assert_pass "lib-teamdb.sh shellcheck 0 errores"
else
  assert_fail "lib-teamdb.sh shellcheck 0 errores" "rc=$SHELLCHECK_RC"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
