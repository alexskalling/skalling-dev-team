#!/usr/bin/env bash
# tests/attempts.test.sh — Ledger de intentos (teamdb-attempt.sh, v0.9.0)
set -euo pipefail

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

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/.opencode/context"
DB="$TEST_DIR/.opencode/context/team.db"

# ── 1. Migration 015 crea la tabla attempts en una DB pre-015 ──
BARE="$TEST_DIR/bare.db"
sqlite3 "$BARE" "CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);"
sqlite3 "$BARE" < "$ROOT/sql/migrations/015_add_attempts.sql"
HAS_BARE=$(sqlite3 "$BARE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='attempts'")
if [ "$HAS_BARE" = "1" ]; then
  assert_pass "migración 015: crea tabla attempts en DB pre-015"
else
  assert_fail "migración 015: crea tabla attempts en DB pre-015" "count=$HAS_BARE"
fi

# ── 2. Schema base incluye attempts (project-schema.sql) ──
if grep -q "CREATE TABLE IF NOT EXISTS attempts" "$ROOT/sql/project-schema.sql"; then
  assert_pass "project-schema.sql incluye tabla attempts"
else
  assert_fail "project-schema.sql incluye tabla attempts"
fi

# ── 3. teamdb-init (fresh) crea attempts + registra migration ──
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
HAS_DB=$(sqlite3 "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='attempts'")
MIG_LOG=$(sqlite3 "$DB" "SELECT COUNT(*) FROM applied_migrations WHERE name='015_add_attempts'")
if [ "$HAS_DB" = "1" ]; then
  assert_pass "teamdb-init: tabla attempts presente"
else
  assert_fail "teamdb-init: tabla attempts presente" "count=$HAS_DB"
fi
if [ "$MIG_LOG" = "1" ]; then
  assert_pass "teamdb-init: migration 015 registrada en applied_migrations"
else
  assert_fail "teamdb-init: migration 015 registrada en applied_migrations" "count=$MIG_LOG"
fi

# ── 4. acquire → state=proceed + token ──
ACQ_OUT="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-x --request-id req-1 "$TEST_DIR")"
TOKEN1="$(printf '%s\n' "$ACQ_OUT" | sed -n 's/^state=proceed token=//p')"
if printf '%s' "$ACQ_OUT" | grep -q "^state=proceed token=atmp_"; then
  assert_pass "acquire: imprime state=proceed token=<tok>"
else
  assert_fail "acquire: imprime state=proceed token=<tok>" "out=$ACQ_OUT"
fi
ROW_STATE=$(sqlite3 "$DB" "SELECT state FROM attempts WHERE token='$TOKEN1'")
ROW_CHANGE=$(sqlite3 "$DB" "SELECT change_name FROM attempts WHERE token='$TOKEN1'")
if [ "$ROW_STATE" = "proceed" ] && [ "$ROW_CHANGE" = "feat-x" ]; then
  assert_pass "acquire: inserta fila state=proceed para el change"
else
  assert_fail "acquire: inserta fila state=proceed para el change" "state=$ROW_STATE change=$ROW_CHANGE"
fi

# ── 5. acquire del mismo change sin settle → state=blocked (no inserta) ──
BEFORE=$(sqlite3 "$DB" "SELECT COUNT(*) FROM attempts")
BLOCK_OUT="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-x --request-id req-1 "$TEST_DIR")"
AFTER=$(sqlite3 "$DB" "SELECT COUNT(*) FROM attempts")
if printf '%s' "$BLOCK_OUT" | grep -q "^state=blocked" && [ "$AFTER" = "$BEFORE" ]; then
  assert_pass "acquire: mismo change sin settle → state=blocked, no inserta"
else
  assert_fail "acquire: mismo change sin settle → state=blocked, no inserta" "out=$BLOCK_OUT before=$BEFORE after=$AFTER"
fi

# ── 6. settle con request-id incorrecto → error ──
set +e
BAD_SETTLE="$(bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN1" --request-id otro-req --outcome ok "$TEST_DIR" 2>&1)"
BAD_SETTLE_RC=$?
set -e
if [ "$BAD_SETTLE_RC" != "0" ] && printf '%s' "$BAD_SETTLE" | grep -q "request_id no coincide"; then
  assert_pass "settle: request_id distinto → error"
else
  assert_fail "settle: request_id distinto → error" "rc=$BAD_SETTLE_RC out=$BAD_SETTLE"
fi

# ── 7. settle ok → state=complete, attempts_used=1 ──
SETTLE_OUT="$(bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN1" --request-id req-1 --outcome ok --evidence "tests verdes" "$TEST_DIR")"
if printf '%s' "$SETTLE_OUT" | grep -q "^state=complete"; then
  assert_pass "settle: outcome=ok → state=complete"
else
  assert_fail "settle: outcome=ok → state=complete" "out=$SETTLE_OUT"
fi
USED1=$(sqlite3 "$DB" "SELECT attempts_used FROM attempts WHERE token='$TOKEN1'")
OUT1=$(sqlite3 "$DB" "SELECT outcome FROM attempts WHERE token='$TOKEN1'")
if [ "$USED1" = "1" ] && [ "$OUT1" = "ok" ]; then
  assert_pass "settle: ok incrementa attempts_used a 1 y guarda outcome"
else
  assert_fail "settle: ok incrementa attempts_used a 1 y guarda outcome" "used=$USED1 outcome=$OUT1"
fi

# ── 8. settle fail hasta el tope → blocked (max_attempts=2) ──
TOKEN2="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-y --request-id req-2 --max-attempts 2 "$TEST_DIR" | sed -n 's/^state=proceed token=//p')"
S1="$(bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN2" --request-id req-2 --outcome fail "$TEST_DIR")"
if printf '%s' "$S1" | grep -q "^state=proceed"; then
  assert_pass "settle: fail #1 de 2 → state=proceed (aún hay presupuesto)"
else
  assert_fail "settle: fail #1 de 2 → state=proceed (aún hay presupuesto)" "out=$S1"
fi
TOKEN3="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-y --request-id req-2 --max-attempts 2 "$TEST_DIR" | sed -n 's/^state=proceed token=//p')"
if [ -n "$TOKEN3" ]; then
  assert_pass "acquire: feat-y con presupuesto restante → proceed de nuevo"
else
  assert_fail "acquire: feat-y con presupuesto restante → proceed de nuevo" "out=$TOKEN3"
fi
S2="$(bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN3" --request-id req-2 --outcome fail "$TEST_DIR")"
if printf '%s' "$S2" | grep -q "^state=blocked"; then
  assert_pass "settle: fail #2 de 2 → state=blocked (presupuesto agotado)"
else
  assert_fail "settle: fail #2 de 2 → state=blocked (presupuesto agotado)" "out=$S2"
fi
BLOCKED_ACQ="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-y --request-id req-2 --max-attempts 2 "$TEST_DIR")"
if printf '%s' "$BLOCKED_ACQ" | grep -q "^state=blocked"; then
  assert_pass "acquire: change con presupuesto agotado → state=blocked"
else
  assert_fail "acquire: change con presupuesto agotado → state=blocked" "out=$BLOCKED_ACQ"
fi

# ── 9. settle abandoned NO consume intento ──
TOKEN4="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-z --request-id req-3 "$TEST_DIR" | sed -n 's/^state=proceed token=//p')"
bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN4" --request-id req-3 --outcome abandoned "$TEST_DIR" >/dev/null
USED4=$(sqlite3 "$DB" "SELECT attempts_used FROM attempts WHERE token='$TOKEN4'")
if [ "$USED4" = "0" ]; then
  assert_pass "settle: abandoned no incrementa attempts_used"
else
  assert_fail "settle: abandoned no incrementa attempts_used" "used=$USED4"
fi

# ── 10. status lista intentos y filtra por --change ──
STATUS_ALL="$(bash "$ROOT/scripts/teamdb-attempt.sh" status "$TEST_DIR")"
N_ALL=$(printf '%s\n' "$STATUS_ALL" | grep -c "atmp_" || true)
STATUS_X="$(bash "$ROOT/scripts/teamdb-attempt.sh" status --change feat-x "$TEST_DIR")"
N_X=$(printf '%s\n' "$STATUS_X" | grep -c "atmp_" || true)
if [ "$N_ALL" -ge 4 ] && [ "$N_X" = "1" ]; then
  assert_pass "status: lista todos los intentos y --change filtra ($N_ALL totales, $N_X para feat-x)"
else
  assert_fail "status: lista todos los intentos y --change filtra" "all=$N_ALL x=$N_X"
fi

# ── 11. acquire sin --change / sin --request-id → error de uso ──
set +e
NOCHANGE="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --request-id r "$TEST_DIR" 2>&1)"
NOCHANGE_RC=$?
set -e
if [ "$NOCHANGE_RC" != "0" ] && printf '%s' "$NOCHANGE" | grep -q "requiere --change"; then
  assert_pass "acquire: falta --change → error de uso"
else
  assert_fail "acquire: falta --change → error de uso" "rc=$NOCHANGE_RC out=$NOCHANGE"
fi

# ── 12. settle replay idempotente: mismo token+request NO vuelve a incrementar ──
TOKEN5="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-w --request-id req-4 --max-attempts 3 "$TEST_DIR" | sed -n 's/^state=proceed token=//p')"
bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN5" --request-id req-4 --outcome fail "$TEST_DIR" >/dev/null
REPLAY="$(bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN5" --request-id req-4 --outcome fail "$TEST_DIR")"
USED_REPLAY=$(sqlite3 "$DB" "SELECT attempts_used FROM attempts WHERE token='$TOKEN5'")
if printf '%s' "$REPLAY" | grep -q "replay idempotente" && [ "$USED_REPLAY" = "1" ]; then
  assert_pass "settle: replay del mismo token+outcome → no incrementa (sigue 1/3)"
else
  assert_fail "settle: replay del mismo token+outcome → no incrementa" "used=$USED_REPLAY out=$REPLAY"
fi
# El replay NO quemó el presupuesto: un nuevo acquire del change sigue con
# intentos restantes (el bug original agotaba 1/3→2/3→3/3 sin trabajo real).
TOKEN5B="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-w --request-id req-4 --max-attempts 3 "$TEST_DIR" | sed -n 's/^state=proceed token=//p')"
if [ -n "$TOKEN5B" ]; then
  assert_pass "settle: tras el replay el change sigue con presupuesto (acquire → proceed)"
else
  assert_fail "settle: tras el replay el change sigue con presupuesto (acquire → proceed)" "out=$TOKEN5B"
fi
# Y el tope (3) sigue aplicando con fails REALES: cada fail usa un token nuevo.
bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN5B" --request-id req-4 --outcome fail "$TEST_DIR" >/dev/null
TOKEN5C="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-w --request-id req-4 --max-attempts 3 "$TEST_DIR" | sed -n 's/^state=proceed token=//p')"
bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN5C" --request-id req-4 --outcome fail "$TEST_DIR" >/dev/null
BLOCKED5="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-w --request-id req-4 --max-attempts 3 "$TEST_DIR")"
if printf '%s' "$BLOCKED5" | grep -q "^state=blocked"; then
  assert_pass "settle: 3 fails reales → acquire bloqueado (tope respetado)"
else
  assert_fail "settle: 3 fails reales → acquire bloqueado (tope respetado)" "out=$BLOCKED5"
fi

# ── 13. settle post-complete con outcome DISTINTO → error, no incrementa ──
TOKEN6="$(bash "$ROOT/scripts/teamdb-attempt.sh" acquire --change feat-v --request-id req-5 "$TEST_DIR" | sed -n 's/^state=proceed token=//p')"
bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN6" --request-id req-5 --outcome ok "$TEST_DIR" >/dev/null
set +e
CONTRADICT="$(bash "$ROOT/scripts/teamdb-attempt.sh" settle --token "$TOKEN6" --request-id req-5 --outcome fail "$TEST_DIR" 2>&1)"
CONTRADICT_RC=$?
set -e
USED6=$(sqlite3 "$DB" "SELECT attempts_used FROM attempts WHERE token='$TOKEN6'")
if [ "$CONTRADICT_RC" != "0" ] && printf '%s' "$CONTRADICT" | grep -q "contradicción de estados" && [ "$USED6" = "1" ]; then
  assert_pass "settle: complete con outcome distinto → error y no incrementa"
else
  assert_fail "settle: complete con outcome distinto → error y no incrementa" "rc=$CONTRADICT_RC used=$USED6 out=$CONTRADICT"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
