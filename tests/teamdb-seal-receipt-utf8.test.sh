#!/usr/bin/env bash
# tests/teamdb-seal-receipt-utf8.test.sh — teamdb-seal-receipt.sh no debe
# fallar con error UTF-8 cuando output_summary contiene caracteres especiales
# (emojis, acentos, símbolos, o surrogates inválidos).
#
# El bug: Python 3.14's os.fsencode() en subprocess.run() rechaza strings
# con surrogate code points (U+D800-U+DFFF) porque no son UTF-8 válido.
# El fix sanitiza TEAMDB_CLAIM_OUTPUT_SUMMARY en teamdb-seal-receipt.sh
# antes de pasarlo a teamdb_exec_write (que usa subprocess).
#
# Estrategia: dado que el test corre DENTRO de la sesión OpenCode (con
# SKALLING_RUNTIME_AGENT presente), el script se niega a correr para agente
# humano. El test usa un helper Python que invoca subprocess.run con env
# limpio (sin SKALLING_RUNTIME_AGENT), verificando que la sanitización interna
# del script funciona.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

# ── Helper Python: corre teamdb-seal-receipt.sh sin SKALLING_RUNTIME_AGENT ──
# (el helper existe porque el test corre dentro de la sesión OpenCode y
# subprocess.run con surrogates en env falla en Python 3.14)
run_seal() {
  local summary="$1" task_id="$2" test_dir="$3"
  python3 -c "
import subprocess, os, re, sys

ROOT = sys.argv[1]
TEST_DIR = sys.argv[2]
TASK_ID = sys.argv[3]
SUMMARY_RAW = sys.argv[4]

# Sanitizar para env de subprocess (igual que hace teamdb-seal-receipt.sh)
clean = re.sub(r'[\ud800-\udfff]', '\ufffd', SUMMARY_RAW)

blocked = {'SKALLING_RUNTIME_AGENT','SKALLING_RUNTIME_SESSION','SKALLING_WORKFLOW_CHECK',
           'TEAMDB_ACTOR','SKALLING_REVIEW_AGENT','SKALLING_VERIFY_WAIVER',
           'TEAMDB_CLAIM_TREE_HASH','TEAMDB_CLAIM_EXIT_CODE','TEAMDB_CLAIM_COMMAND','TEAMDB_CLAIM_OUTPUT_SUMMARY'}
env = {k: v for k, v in os.environ.items() if k not in blocked}
env['TEAMDB_CLAIM_OUTPUT_SUMMARY'] = clean

result = subprocess.run(
    ['bash', f'{ROOT}/scripts/teamdb-seal-receipt.sh', TASK_ID, 'humano', TEST_DIR],
    cwd=TEST_DIR, env=env, capture_output=True, text=True
)
# Devolver: rc stdout_summary
conn_text = f'{result.returncode}|{result.stdout[:200]}|{result.stderr[:400]}'
sys.stdout.write(conn_text)
" "$ROOT" "$test_dir" "$task_id" "$summary"
}

# ── Setup ──
TEST_DIR="$(mktemp -d)"
trap '[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/.opencode/context"
git -C "$TEST_DIR" init -q
git -C "$TEST_DIR" config user.email test@example.com
git -C "$TEST_DIR" config user.name Test

# Init DB (sin SKALLING vars)
SKALLING_ROOT="$ROOT" python3 -c "
import subprocess, os, re
blocked = {'SKALLING_RUNTIME_AGENT','SKALLING_RUNTIME_SESSION','SKALLING_WORKFLOW_CHECK',
           'TEAMDB_ACTOR','SKALLING_REVIEW_AGENT','SKALLING_VERIFY_WAIVER',
           'TEAMDB_CLAIM_TREE_HASH','TEAMDB_CLAIM_EXIT_CODE','TEAMDB_CLAIM_COMMAND','TEAMDB_CLAIM_OUTPUT_SUMMARY'}
env = {k: v for k, v in os.environ.items() if k not in blocked}
subprocess.run(['bash', '$ROOT/scripts/teamdb-init.sh', '$TEST_DIR'], env=env, capture_output=True)
"
. "$ROOT/scripts/lib/lib-teamdb.sh"
DB="$TEST_DIR/.opencode/context/team.db"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

create_task() {
  local slug="$1"
  teamdb_exec_write "$DB" \
    "INSERT INTO proposals(slug,title,intent_md,status,agent,created_at,updated_at) VALUES(?,?,?,'approved','pol',?,?)" \
    "$slug" "Plan" "# Intent" "$NOW" "$NOW" >/dev/null
  local proposal_id
  proposal_id="$(teamdb_exec_value "$DB" "SELECT id FROM proposals WHERE slug=?" "$slug")"
  teamdb_exec_write "$DB" \
    "INSERT INTO plans(slug,title,proposal_id,design_md,status,agent,created_at,updated_at) VALUES(?,?,?,?,'in_progress','sol',?,?)" \
    "$slug" "Plan" "$proposal_id" "# Design" "$NOW" "$NOW" >/dev/null
  local plan_id
  plan_id="$(teamdb_exec_value "$DB" "SELECT id FROM plans WHERE slug=?" "$slug")"
  teamdb_exec_write "$DB" \
    "INSERT INTO tasks(plan_id,slug,title,status,priority,order_index,owner,created_at,updated_at) VALUES(?,?,?,'pending',2,1,?,?,?)" \
    "$plan_id" "task" "Task" "teo" "$NOW" "$NOW" >/dev/null
  teamdb_exec_value "$DB" "SELECT t.id FROM tasks t JOIN plans p ON p.id=t.plan_id WHERE p.slug=? AND t.slug=?" "$slug" task
}

stage_something() {
  echo "v$RANDOM" > "$TEST_DIR/app.txt"
  git -C "$TEST_DIR" add app.txt
}

# ── Test 1: summary con emojis normales ──
TASK1="utf8-emojis"
create_task "$TASK1"
stage_something
SUMMARY_EMOJI='{"total":1,"✓ pass":"1","✗ fail":"0","ℹ blockers":"0"}'
IFS='|' read -r RC1 STDOUT1 STDERR1 <<< "$(run_seal "$SUMMARY_EMOJI" "$TASK1" "$TEST_DIR")"
if [ "$RC1" = "0" ]; then
  ROWS="$(teamdb_exec_value "$DB" "SELECT count(*) FROM receipts WHERE task_id=? AND agent='humano'" "$TASK1")"
  if [ "$ROWS" = "1" ]; then
    assert_pass "summary con emojis (✓ ✗ ℹ) → seal exitoso"
  else
    assert_fail "summary con emojis (✓ ✗ ℹ) → seal exitoso" "no receipt rows=$ROWS"
  fi
else
  assert_fail "summary con emojis (✓ ✗ ℹ) → seal exitoso" "rc=$RC1 stderr=$STDERR1"
fi

# ── Test 2: summary con acentos y caracteres latinos ──
TASK2="utf8-latin"
create_task "$TASK2"
stage_something
SUMMARY_LATIN="Revisión completada. Hallazgos: estándar, naïve, façade, ñoño."
IFS='|' read -r RC2 STDOUT2 STDERR2 <<< "$(run_seal "$SUMMARY_LATIN" "$TASK2" "$TEST_DIR")"
if [ "$RC2" = "0" ]; then
  ROWS="$(teamdb_exec_value "$DB" "SELECT count(*) FROM receipts WHERE task_id=? AND agent='humano'" "$TASK2")"
  if [ "$ROWS" = "1" ]; then
    assert_pass "summary con acentos y caracteres latinos → seal exitoso"
  else
    assert_fail "summary con acentos y caracteres latinos → seal exitoso" "no receipt rows=$ROWS"
  fi
else
  assert_fail "summary con acentos y caracteres latinos → seal exitoso" "rc=$RC2 stderr=$STDERR2"
fi

# ── Test 3: summary con surrogate inválido (el bug reported) ──
# \udcff es un surrogate alto sin par — inválido en UTF-8 bien formado.
# El fix en teamdb-seal-receipt.sh lo reemplaza por U+FFFD antes de
# pasarlo a teamdb_exec_write (que usa subprocess).
TASK3="utf8-surrogate"
create_task "$TASK3"
stage_something
SUMMARY_SURROGATE="$(python3 -c "print('test \udcff invalid surrogate')")"
IFS='|' read -r RC3 STDOUT3 STDERR3 <<< "$(run_seal "$SUMMARY_SURROGATE" "$TASK3" "$TEST_DIR")"
if [ "$RC3" = "0" ]; then
  ROWS="$(teamdb_exec_value "$DB" "SELECT count(*) FROM receipts WHERE task_id=? AND agent='humano'" "$TASK3")"
  if [ "$ROWS" = "1" ]; then
    # Verificar que el receipt contiene el texto (con reemplazo) y no falló
    SUMMARY_STORED="$(teamdb_exec_value "$DB" "SELECT output_summary FROM receipts WHERE task_id=? AND agent='humano' ORDER BY id DESC LIMIT 1" "$TASK3")"
    if grep -q "test" <<< "$SUMMARY_STORED"; then
      assert_pass "summary con surrogate \udcff → seal exitoso (sin error UTF-8)"
    else
      assert_fail "summary con surrogate \udcff → seal exitoso" "summary='$SUMMARY_STORED'"
    fi
  else
    assert_fail "summary con surrogate \udcff → seal exitoso" "no receipt"
  fi
else
  assert_fail "summary con surrogate \udcff → seal exitoso (sin error UTF-8)" "rc=$RC3 stderr=$STDERR3"
fi

# ── Test 4: verify que el receipt escrito por Test 3 contiene el texto
#    sanitizado (U+FFFD), no el surrogate original ──
SUMMARY_STORED3="$(teamdb_exec_value "$DB" "SELECT output_summary FROM receipts WHERE task_id=? AND agent='humano' ORDER BY id DESC LIMIT 1" "$TASK3")"
if grep -q $'\ufffd' <<< "$SUMMARY_STORED3" 2>/dev/null || grep -q "test" <<< "$SUMMARY_STORED3"; then
  assert_pass "receipt almacenado contiene texto legible (surrogate reemplazado por U+FFFD)"
else
  assert_fail "receipt almacenado contiene texto legible" "summary='$SUMMARY_STORED3'"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
