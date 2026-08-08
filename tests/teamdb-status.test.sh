#!/usr/bin/env bash
# tests/teamdb-status.test.sh — Fase 2: due_date + tablero teamdb-status (v0.9.1)
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# helper: repo con DB teamdb inicializada (v0.9.1, migración 016 aplicada)
new_db() {
  local repo="$1"
  mkdir -p "$repo"
  bash "$ROOT/scripts/teamdb-init.sh" "$repo" >/dev/null 2>&1
}

new_plan() {
  local repo="$1" slug="$2"
  printf '%s\n' "- [ ] Intro task" > "$repo/tasks.md"
  bash "$ROOT/scripts/teamdb-plan.sh" "$repo" "$slug" "$slug plan" "$repo/tasks.md" --by=teo --purpose="test" >/dev/null 2>&1
}

# ── 1. Migración 016 idempotente: dos inits → 0.9.1 ──
REPO1="$TMP/repo1"
new_db "$REPO1"
VER1=$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT value FROM schema_meta WHERE key='version'")
bash "$ROOT/scripts/teamdb-init.sh" "$REPO1" >/dev/null 2>&1
RC2=$?
VER2=$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT value FROM schema_meta WHERE key='version'")
if [ "$VER1" = "0.9.1" ] && [ "$VER2" = "0.9.1" ] && [ "$RC2" = "0" ]; then
  assert_pass "init idempotente: versión 0.9.1 tras dos corridas"
else
  assert_fail "init idempotente: versión 0.9.1 tras dos corridas" "v1=$VER1 v2=$VER2 rc2=$RC2"
fi
# schema_meta.tasks tiene due_date
DD=$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT count(*) FROM pragma_table_info('tasks') WHERE name='due_date'")
if [ "$DD" = "1" ]; then
  assert_pass "tasks.due_date existe tras migración 016"
else
  assert_fail "tasks.due_date existe tras migración 016" "count=$DD"
fi

# ── 2. due_date en add-task ──
new_plan "$REPO1" demo
bash "$ROOT/scripts/teamdb-amend.sh" demo --add-task="Nueva con fecha" --purpose="x" --due-date=2025-05-05 "$REPO1" >/dev/null 2>&1
DUE_ADD=$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT due_date FROM tasks WHERE slug='nueva-con-fecha'")
STATUS_ADD=$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT status FROM tasks WHERE slug='nueva-con-fecha'")
if [ "$DUE_ADD" = "2025-05-05" ] && [ "$STATUS_ADD" = "pending" ]; then
  assert_pass "add-task con --due-date persiste fecha y status pending"
else
  assert_fail "add-task con --due-date persiste fecha y status pending" "due=$DUE_ADD status=$STATUS_ADD"
fi

# ── 3. due_date en modify-task ──
bash "$ROOT/scripts/teamdb-amend.sh" demo --modify-task=task-intro-task --new-title="Intro task" --due-date=2030-01-01 "$REPO1" >/dev/null 2>&1
DUE_MOD=$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT due_date FROM tasks WHERE slug='task-intro-task'")
if [ "$DUE_MOD" = "2030-01-01" ]; then
  assert_pass "modify-task con --due-date actualiza la fecha"
else
  assert_fail "modify-task con --due-date actualiza la fecha" "due=$DUE_MOD"
fi

# ── 4. Tablero: OVERDUE (pasada) y sin marca (futura) ──
STATUS_OUT="$(bash "$ROOT/scripts/teamdb-status.sh" "" "$REPO1")"
if printf '%s\n' "$STATUS_OUT" | grep -q "nueva-con-fecha \[OVERDUE\]"; then
  assert_pass "tablero marca [OVERDUE] para due_date pasada"
else
  assert_fail "tablero marca [OVERDUE] para due_date pasada" "$STATUS_OUT"
fi
if ! printf '%s\n' "$STATUS_OUT" | grep -q "task-intro-task \[OVERDUE\]"; then
  assert_pass "tablero NO marca [OVERDUE] para due_date futura"
else
  assert_fail "tablero NO marca [OVERDUE] para due_date futura" "$STATUS_OUT"
fi
if printf '%s\n' "$STATUS_OUT" | grep -q "Resumen global: pending:2"; then
  assert_pass "tablero muestra resumen global"
else
  assert_fail "tablero muestra resumen global" "$STATUS_OUT"
fi

# ── 5. Filtro por slug ──
FILTERED="$(bash "$ROOT/scripts/teamdb-status.sh" demo "$REPO1")"
if printf '%s\n' "$FILTERED" | grep -q "demo plan" && ! printf '%s\n' "$FILTERED" | grep -q "Resumen global"; then
  assert_pass "filtro por slug muestra solo ese plan"
else
  assert_fail "filtro por slug muestra solo ese plan" "$FILTERED"
fi

# ── 6. Solo lectura: el tablero no altera la DB ──
SLUGS_BEFORE="$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT group_concat(slug, '|') FROM tasks ORDER BY slug")"
bash "$ROOT/scripts/teamdb-status.sh" "" "$REPO1" >/dev/null 2>&1
SLUGS_AFTER="$(sqlite3 "$REPO1/.opencode/context/team.db" "SELECT group_concat(slug, '|') FROM tasks ORDER BY slug")"
if [ "$SLUGS_BEFORE" = "$SLUGS_AFTER" ]; then
  assert_pass "tablero es solo lectura (tasks intactas)"
else
  assert_fail "tablero es solo lectura (tasks intactas)" "$SLUGS_BEFORE → $SLUGS_AFTER"
fi

echo
echo "teamdb-status.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
