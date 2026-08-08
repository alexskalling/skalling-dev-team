#!/usr/bin/env bash
# tests/pre-push.test.sh — Gate pre-push con tree_hash (v0.9.0)
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

# helper: repo con DB teamdb inicializada + dump versionado (guarda del hook,
# Fase 0: el guard es db/teamdb/team.dump.sql, no el dir legacy gitignored)
new_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  bash "$ROOT/scripts/teamdb-init.sh" "$repo" >/dev/null 2>&1
  bash "$ROOT/scripts/teamdb-dump.sh" "$repo" >/dev/null 2>&1
  printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\n' > "$repo/base.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
}

# helper: simula el stdin del hook pre-push. El stdin se pasa por ARCHIVO, no por
# pipe: los guards tempranos del hook (ej: sin teamdb/) hacen exit ANTES de leer
# stdin, y bajo pipefail un productor por pipe podía recibir EPIPE (write con el
# reader ya cerrado) → exit code corrido (rc≠0 sin output) → flake intermitente.
run_hook() {
  local cwd="$1" stdin_text="$2"
  local stdin_file="$TMP/hook-stdin"
  printf '%s\n' "$stdin_text" > "$stdin_file"
  (cd "$cwd" && bash "$ROOT/scripts/hooks/pre-push" < "$stdin_file" 2>&1)
  return $?
}

run_pre_push() {
  local repo="$1" local_sha="$2" remote_sha="$3"
  run_hook "$repo" "refs/heads/main $local_sha refs/heads/main $remote_sha"
  return $?
}

# ── 1. Guard: sin db/teamdb/team.dump.sql → exit 0 ──
NODB_REPO="$TMP/nodb-repo"
mkdir -p "$NODB_REPO"
git -C "$NODB_REPO" init -q
git -C "$NODB_REPO" config user.email "test@test.com"
git -C "$NODB_REPO" config user.name "Test"
printf 'x\n' > "$NODB_REPO/a.txt"
git -C "$NODB_REPO" add -A
git -C "$NODB_REPO" commit -qm init
set +e
GUARD_OUT="$(run_hook "$NODB_REPO" "refs/heads/main $(git -C "$NODB_REPO" rev-parse HEAD) refs/heads/main 0000000000000000000000000000000000000000")"
GUARD_RC=$?
set -e
if [ "$GUARD_RC" = "0" ]; then
  assert_pass "pre-push: sin dump versionado → exit 0 (guard Fase 0)"
else
  assert_fail "pre-push: sin dump versionado → exit 0 (guard Fase 0)" "rc=$GUARD_RC out=$GUARD_OUT"
fi

# ── 2. Ref con local_sha todo-ceros (deleción) → skip, exit 0 ──
DEL_REPO="$TMP/del-repo"
new_repo "$DEL_REPO"
set +e
DEL_OUT="$(run_hook "$DEL_REPO" "refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main 0000000000000000000000000000000000000000")"
DEL_RC=$?
set -e
if [ "$DEL_RC" = "0" ]; then
  assert_pass "pre-push: local_sha todo-ceros (deleción) → exit 0"
else
  assert_fail "pre-push: local_sha todo-ceros (deleción) → exit 0" "rc=$DEL_RC out=$DEL_OUT"
fi

# ── 3. Receipt fresco + refs válidos → exit 0 ──
OK_REPO="$TMP/ok-repo"
new_repo "$OK_REPO"
BASE_SHA="$(git -C "$OK_REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho ok\necho "segunda linea"\n' > "$OK_REPO/base.sh"
git -C "$OK_REPO" add base.sh
# sellar el candidato ANTES de commitear (flujo real: review → commit → push)
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 9 teo "$OK_REPO" >/dev/null 2>&1
git -C "$OK_REPO" commit -qm "feat: candidato revisado"
LOCAL_SHA="$(git -C "$OK_REPO" rev-parse HEAD)"
set +e
OK_OUT="$(run_pre_push "$OK_REPO" "$LOCAL_SHA" "$BASE_SHA")"
OK_RC=$?
set -e
if [ "$OK_RC" = "0" ] && printf '%s' "$OK_OUT" | grep -q "coincide con el receipt sellado"; then
  assert_pass "pre-push: refs válidos + receipt fresco → exit 0"
else
  assert_fail "pre-push: refs válidos + receipt fresco → exit 0" "rc=$OK_RC out=$OK_OUT"
fi

# ── 4. Cambio post-seal → exit 1 ──
POST_REPO="$TMP/post-repo"
new_repo "$POST_REPO"
BASE_SHA="$(git -C "$POST_REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v1\n' > "$POST_REPO/base.sh"
git -C "$POST_REPO" add base.sh
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 10 teo "$POST_REPO" >/dev/null 2>&1
git -C "$POST_REPO" commit -qm "feat: v1 revisado"
# cambiar una línea DESPUÉS del seal y commitear el cambio no revisado
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v2-tocado\n' > "$POST_REPO/base.sh"
git -C "$POST_REPO" add base.sh
git -C "$POST_REPO" commit -qm "feat: cambio post-seal"
LOCAL_SHA="$(git -C "$POST_REPO" rev-parse HEAD)"
set +e
POST_OUT="$(run_pre_push "$POST_REPO" "$LOCAL_SHA" "$BASE_SHA")"
POST_RC=$?
set -e
if [ "$POST_RC" = "1" ] && printf '%s' "$POST_OUT" | grep -q "no coincide con el último receipt sellado"; then
  assert_pass "pre-push: cambio post-seal → exit 1"
else
  assert_fail "pre-push: cambio post-seal → exit 1" "rc=$POST_RC out=$POST_OUT"
fi

# ── 5. Sin receipt sellado → exit 1 (fail-closed) ──
NOREC_REPO="$TMP/norec-repo"
new_repo "$NOREC_REPO"
BASE_SHA="$(git -C "$NOREC_REPO" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v1\n' > "$NOREC_REPO/base.sh"
git -C "$NOREC_REPO" add base.sh
git -C "$NOREC_REPO" commit -qm "feat: sin sellar"
LOCAL_SHA="$(git -C "$NOREC_REPO" rev-parse HEAD)"
set +e
NOREC_OUT="$(run_pre_push "$NOREC_REPO" "$LOCAL_SHA" "$BASE_SHA")"
NOREC_RC=$?
set -e
if [ "$NOREC_RC" = "1" ] && printf '%s' "$NOREC_OUT" | grep -q "no hay receipt sellado"; then
  assert_pass "pre-push: sin receipt → exit 1 (fail-closed)"
else
  assert_fail "pre-push: sin receipt → exit 1 (fail-closed)" "rc=$NOREC_RC out=$NOREC_OUT"
fi

# ── 6. Branch nuevo sin upstream (remote_sha todo-ceros) → usa merge-base con HEAD ──
NEWBR_REPO="$TMP/newbr-repo"
new_repo "$NEWBR_REPO"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho v1\n' > "$NEWBR_REPO/base.sh"
git -C "$NEWBR_REPO" add base.sh
bash "$ROOT/scripts/teamdb-seal-receipt.sh" 11 teo "$NEWBR_REPO" >/dev/null 2>&1
git -C "$NEWBR_REPO" commit -qm "feat: candidato"
git -C "$NEWBR_REPO" branch -M main 2>/dev/null || true
LOCAL_SHA="$(git -C "$NEWBR_REPO" rev-parse HEAD)"
set +e
NEWBR_OUT="$(run_hook "$NEWBR_REPO" "refs/heads/main $LOCAL_SHA refs/heads/main 0000000000000000000000000000000000000000")"
NEWBR_RC=$?
set -e
# base = merge-base(local_sha, HEAD) = local_sha → diff vacío → skip (exit 0)
if [ "$NEWBR_RC" = "0" ]; then
  assert_pass "pre-push: branch nuevo (remote todo-ceros) → exit 0"
else
  assert_fail "pre-push: branch nuevo (remote todo-ceros) → exit 0" "rc=$NEWBR_RC out=$NEWBR_OUT"
fi

# ── 7. BUG A: to_epoch parsea UTC en pre-commit (GNU date / BSD date) ──
# El hook DEBE detectar el flavor de `date` antes de usar date -j: en Linux
# (GNU) `date -j` no existe y devolvía 0 → AGE>600 → bloqueaba commits con
# receipts frescos en CI (reproducido en la auditoría). Y el timestamp del
# receipt (sqlite datetime('now')) es UTC: parsearlo como hora LOCAL corría el
# epoch por el offset de TZ (en TZ positiva un receipt fresco se veía futuro).
# Estructural: dentro del bloque BEGIN/END-TO-EPOCH, la rama BSD usa `-u` y la
# GNU el sufijo " UTC"; fuera del bloque no puede haber `date -j`.
if awk '
  /^# BEGIN-TO-EPOCH/ { active=1 }
  /^# END-TO-EPOCH/ { active=0 }
  active && /date -j/ && /-u/ { bsd=1 }
  active && /\$1 UTC/ { gnu=1 }
  !active && /date -j/ { bad=1 }
  END { exit !(bsd && gnu && !bad) }
' "$ROOT/scripts/hooks/pre-commit"; then
  assert_pass "pre-commit: to_epoch parsea UTC (BSD -u + GNU ' UTC', solo en el bloque)"
else
  assert_fail "pre-commit: to_epoch parsea UTC (BSD -u + GNU ' UTC', solo en el bloque)"
fi
# Funcional: to_epoch autoselecciona el flavor (GNU -d / BSD -j) y convierte un
# timestamp UTC reciente (formato datetime('now') de sqlite) a epoch reciente.
eval "$(sed -n '/^# BEGIN-TO-EPOCH/,/^# END-TO-EPOCH/p' "$ROOT/scripts/hooks/pre-commit" | grep -vE '^[[:space:]]*#')"
FRESH="$(date -u +"%Y-%m-%d %H:%M:%S")"
NOW="$(date +%s)"
EPOCH="$(to_epoch "$FRESH" 2>/dev/null || true)"
if [ -n "$EPOCH" ] && [ "$EPOCH" -gt $((NOW - 120)) ] && [ "$EPOCH" -le "$NOW" ]; then
  assert_pass "pre-commit: to_epoch convierte receipt fresco UTC ($EPOCH, ahora=$NOW)"
else
  assert_fail "pre-commit: to_epoch convierte receipt fresco UTC" "epoch=$EPOCH now=$NOW fresh=$FRESH"
fi
# Funcional 2: un timestamp UTC conocido, parseado bajo una TZ NO-UTC, debe dar
# el MISMO epoch canónico UTC. Si to_epoch interpretara hora local (el bug),
# TZ=America/Argentina/Buenos_Aires sumaría 3h → epoch ≠ esperado.
KNOWN="2026-08-07 23:42:00"
EXPECTED="$(date -u -j -f "%Y-%m-%d %H:%M:%S" "$KNOWN" +%s 2>/dev/null || date -u -d "$KNOWN" +%s 2>/dev/null || echo "")"
set +e
TZ_EPOCH="$(TZ=America/Argentina/Buenos_Aires to_epoch "$KNOWN" 2>/dev/null || true)"
set -e
if [ -n "$EXPECTED" ] && [ -n "$TZ_EPOCH" ] && [ "$TZ_EPOCH" = "$EXPECTED" ]; then
  assert_pass "pre-commit: to_epoch convierte timestamp UTC como UTC, no hora local ($TZ_EPOCH)"
else
  assert_fail "pre-commit: to_epoch convierte timestamp UTC como UTC" "expected=$EXPECTED got=$TZ_EPOCH"
fi
# El mismo patrón de flavor-guard aplica al lib de memory-check (ISO 8601).
if grep -q "date --version" "$ROOT/scripts/lib/lib-memory-check.sh"; then
  assert_pass "lib-memory-check: _skalling_timestamp_to_epoch detecta flavor de date"
else
  assert_fail "lib-memory-check: _skalling_timestamp_to_epoch detecta flavor de date"
fi
set +e
LIB_EPOCH="$(bash -c '
  set -euo pipefail
  source "$1"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  _skalling_timestamp_to_epoch "$ts"
' _ "$ROOT/scripts/lib/lib-memory-check.sh" 2>/dev/null)"
LIB_RC=$?
set -e
# NOW se captura DESPUÉS de la conversión: si el subshell cruzara un cambio de
# segundo, LIB_EPOCH = segundo siguiente y LIB_EPOCH -le NOW daría falso (flake).
NOW="$(date +%s)"
if [ "$LIB_RC" = "0" ] && [ -n "$LIB_EPOCH" ] && [ "$LIB_EPOCH" -gt $((NOW - 120)) ] && [ "$LIB_EPOCH" -le "$NOW" ]; then
  assert_pass "lib-memory-check: _skalling_timestamp_to_epoch convierte ISO fresco ($LIB_EPOCH)"
else
  assert_fail "lib-memory-check: _skalling_timestamp_to_epoch convierte ISO fresco" "rc=$LIB_RC epoch=$LIB_EPOCH"
fi

# ── 8. FASE 1: dump desactualizado (DB mutada sin refresh) → exit 1 ──
STALE_REPO="$TMP/stale-repo"
new_repo "$STALE_REPO"
# Mutar la DB directamente, simulando un script de escritura SIN teamdb_refresh_dump
sqlite3 "$STALE_REPO/.opencode/context/team.db" "INSERT INTO concepts(slug, title, body_md, category, updated_at) VALUES('stale-test', 'Stale Test', 'sin refresh', 'test', datetime('now'))" >/dev/null 2>&1
LOCAL_SHA="$(git -C "$STALE_REPO" rev-parse HEAD)"
set +e
STALE_OUT="$(run_pre_push "$STALE_REPO" "$LOCAL_SHA" "$LOCAL_SHA")"
STALE_RC=$?
set -e
if [ "$STALE_RC" = "1" ] && printf '%s' "$STALE_OUT" | grep -q "DESACTUALIZADO"; then
  assert_pass "pre-push: FASE 1 dump desactualizado → exit 1"
else
  assert_fail "pre-push: FASE 1 dump desactualizado → exit 1" "rc=$STALE_RC out=$STALE_OUT"
fi

# ── 9. FASE 1: DB mutada + refresh del dump → gate barato pasa ──
FRESH_REPO="$TMP/fresh-repo"
new_repo "$FRESH_REPO"
sqlite3 "$FRESH_REPO/.opencode/context/team.db" "INSERT INTO concepts(slug, title, body_md, category, updated_at) VALUES('fresh-test', 'Fresh Test', 'con refresh', 'test', datetime('now'))" >/dev/null 2>&1
# Simular teamdb_refresh_dump (lo que hacen los scripts de escritura en Fase 1)
bash "$ROOT/scripts/teamdb-dump.sh" "$FRESH_REPO" >/dev/null 2>&1
LOCAL_SHA="$(git -C "$FRESH_REPO" rev-parse HEAD)"
set +e
FRESH_OUT="$(run_pre_push "$FRESH_REPO" "$LOCAL_SHA" "$LOCAL_SHA")"
FRESH_RC=$?
set -e
if [ "$FRESH_RC" = "0" ] && ! printf '%s' "$FRESH_OUT" | grep -q "DESACTUALIZADO"; then
  assert_pass "pre-push: FASE 1 dump fresco tras refresh → exit 0"
else
  assert_fail "pre-push: FASE 1 dump fresco tras refresh → exit 0" "rc=$FRESH_RC out=$FRESH_OUT"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
