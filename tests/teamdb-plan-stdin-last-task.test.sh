#!/usr/bin/env bash
# tests/teamdb-plan-stdin-last-task.test.sh — teamdb-plan.sh <project> <slug> <title> -
# (stdin) perdia la ULTIMA task en silencio: TASKS_CONTENT="$(cat)" recorta el
# salto de linea final de stdin, y sin devolverlo el archivo temporal queda
# sin newline final -- "while read" descarta la ultima linea sin ningun error
# ni aviso en el conteo reportado. Encontrado auditando un plan real de 18
# tasks (Survan/betterhealth) que quedo en 17 sin que nada lo señalara.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

TEST_DIR="$(mktemp -d)"
trap '[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/.opencode/context"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$TEST_DIR" >/dev/null 2>&1
# shellcheck source=scripts/lib/lib-teamdb.sh
. "$ROOT/scripts/lib/lib-teamdb.sh"
DB="$TEST_DIR/.opencode/context/team.db"

# printf '%s\n' SIEMPRE termina en newline -- el bug no dependia de que el
# caller lo omitiera; $(cat) lo recortaba igual del lado del script.
OUT="$(printf '%s\n' \
  '- [ ] Task uno' \
  '- [ ] Task dos: con parentesis (y) simbolos + varios' \
  '- [ ] Task tres, la ultima de la lista' \
  | bash "$ROOT/scripts/teamdb-plan.sh" "$TEST_DIR" stdin-test "Stdin test" - --by=sol --purpose=p --acceptance=a 2>&1)"

if echo "$OUT" | grep -q '3 tasks'; then
  assert_pass "teamdb-plan reporta 3 tasks (no 2)"
else
  assert_fail "teamdb-plan reporta 3 tasks" "out=$OUT"
fi

COUNT="$(teamdb_exec_value "$DB" "SELECT COUNT(*) FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='stdin-test')")"
if [ "$COUNT" = "3" ]; then
  assert_pass "las 3 tasks quedaron persistidas en TeamDB"
else
  assert_fail "las 3 tasks quedaron persistidas en TeamDB" "count=$COUNT"
fi

LAST="$(teamdb_exec_value "$DB" "SELECT slug FROM tasks WHERE plan_id=(SELECT id FROM plans WHERE slug='stdin-test') ORDER BY order_index DESC LIMIT 1")"
if [ "$LAST" = "task-task-tres-la-ultima-de-la-lista" ]; then
  assert_pass "la ultima task de la lista (antes se perdia) existe: $LAST"
else
  assert_fail "la ultima task de la lista existe" "got: $LAST"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
