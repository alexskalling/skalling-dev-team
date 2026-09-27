#!/usr/bin/env bash
# tests/audit-regressions.test.sh — Reproducciones de la auditoría externa de
# v0.11.16 (27-09-2026). Cada caso arma el escenario que el informe usó para
# obtener una aprobación inválida o una instalación destructiva, y exige que
# ahora se RECHACE. Fixtures herméticos: nada del checkout ni del HOME real.
#
#   A02  receipt de Jhon sin tests configurados no aprueba (not_run); waiver
#        humano sí, y el gate lo anuncia
#   A03  el candidato cambia mientras corre el test → no se sella
#   A05  cambios .sql/.mjs/YAML necesitan revisión; solo docs quedan exentos
#   A06  setup por proyecto instala el guard de identidad
#   A07  setup conserva y encadena un hook previo; uninstall lo restaura
#   A11  uninstall retira plugins, hooks y scripts
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0
assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }
check() { local name="$1"; shift; if "$@"; then assert_pass "$name"; else assert_fail "$name"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"
unset SKALLING_ROOT SKALLING_RUNTIME_AGENT SKALLING_VERIFY_WAIVER TEAMDB_CLAIM_TREE_HASH TEAMDB_CLAIM_EXIT_CODE

new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.opencode/context"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name Test
  echo "base" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm base --no-verify
  printf '%s\n' "$dir"
}

gate() { (cd "$1" && python3 "$ROOT/scripts/hooks/git-gate.py" pre-commit) >"$WORK/gate.out" 2>&1; }
seal() { local project="$1" agent="$2"; shift 2; env "$@" bash "$ROOT/scripts/teamdb-seal-receipt.sh" task-1 "$agent" "$project" >"$WORK/seal.out" 2>&1; }

# ── A02: sin tests configurados, un receipt de Jhon NO aprueba ─────────────
P="$(new_repo a02)"
bash "$ROOT/scripts/teamdb-init.sh" "$P" >/dev/null 2>&1
printf 'def broken(:\n' > "$P/app.py"          # Python inválido, como en el informe
git -C "$P" add app.py
seal "$P" jhon
EXIT="$(sqlite3 "$P/.opencode/context/team.db" "SELECT exit_code FROM receipts ORDER BY rowid DESC LIMIT 1")"
CMD="$(sqlite3 "$P/.opencode/context/team.db" "SELECT command FROM receipts ORDER BY rowid DESC LIMIT 1")"
check "A02: receipt de jhon sin tests queda exit_code=2 (not_run), no 0" test "$EXIT" = "2"
check "A02: el receipt se identifica como not_run" test "${CMD#not_run:}" != "$CMD"
if gate "$P"; then assert_fail "A02: el gate rechaza un not_run" "$(cat "$WORK/gate.out")"; else assert_pass "A02: el gate rechaza un not_run"; fi
check "A02: el rechazo explica cómo salir (tests, Luz o waiver humano)" grep -q "SKALLING_VERIFY_WAIVER" "$WORK/gate.out"
seal "$P" jhon SKALLING_VERIFY_WAIVER="proyecto sin suite; revisado a mano por el usuario"
if gate "$P"; then assert_pass "A02: waiver humano explícito habilita el commit"; else assert_fail "A02: waiver humano explícito habilita el commit" "$(cat "$WORK/gate.out")"; fi
check "A02: el gate anuncia que se aprobó SIN tests" grep -q "SIN tests" "$WORK/gate.out"
check "A02: el guard impide que un agente fije el waiver" node --input-type=module -e "
  import { identityViolation } from '$ROOT/plugins/lib/git-guard.mjs';
  process.exit(identityViolation('SKALLING_VERIFY_WAIVER=x bash s/teamdb-seal-receipt.sh t jhon') ? 0 : 1);"

# ── A08: identidad ambigua del runtime → los helpers fallan cerrado ───────
if SKALLING_RUNTIME_AGENT=ambiguous bash -c ". '$ROOT/scripts/lib/lib-teamdb.sh'; teamdb_runtime_actor jhon" >/dev/null 2>&1; then
  assert_fail "A08: identidad 'ambiguous' se rechaza en los helpers"
else
  assert_pass "A08: identidad 'ambiguous' se rechaza en los helpers"
fi

# ── A03: carrera entre la prueba y el contenido sellado ────────────────────
P="$(new_repo a03)"
bash "$ROOT/scripts/teamdb-init.sh" "$P" >/dev/null 2>&1
cat > "$P/.opencode/project.yaml" <<'EOF'
testing:
  unit:
    available: true
    command: "python3 -c 'import app; assert app.value == 1' && sleep 2"
EOF
echo "value = 1" > "$P/app.py"
git -C "$P" add app.py
( sleep 0.7; printf 'value = (\n' > "$P/app.py"; git -C "$P" add app.py ) &
RACER=$!
if seal "$P" jhon; then
  assert_fail "A03: cambio concurrente durante el test → no se sella" "$(cat "$WORK/seal.out")"
else
  assert_pass "A03: cambio concurrente durante el test → no se sella"
fi
wait "$RACER"
check "A03: el error nombra el cambio de candidato" grep -q "cambió mientras corría" "$WORK/seal.out"
COUNT="$(sqlite3 "$P/.opencode/context/team.db" "SELECT count(*) FROM receipts")"
check "A03: no quedó ningún receipt" test "$COUNT" = "0"
if gate "$P"; then assert_fail "A03: el gate bloquea el contenido nuevo"; else assert_pass "A03: el gate bloquea el contenido nuevo"; fi
# Sin carrera, el mismo flujo sí sella y aprueba (control positivo).
echo "value = 1" > "$P/app.py"
git -C "$P" add app.py
if seal "$P" jhon && gate "$P"; then assert_pass "A03: sin carrera, test real verde sella y aprueba"; else assert_fail "A03: sin carrera, test real verde sella y aprueba" "$(cat "$WORK/seal.out" "$WORK/gate.out")"; fi

# ── A05: el gate cubre todo cambio funcional, no una lista de lenguajes ────
for file in migration.sql plugin.mjs config.yaml Dockerfile package.json page.vue .opencode/agents/Teo.md; do
  P="$(new_repo "a05-$(echo "$file" | tr '/.' '__')")"
  mkdir -p "$(dirname "$P/$file")"
  echo "DROP TABLE customers;" > "$P/$file"
  git -C "$P" add "$file"
  if gate "$P"; then assert_fail "A05: $file sin revisión se bloquea" "$(cat "$WORK/gate.out")"; else assert_pass "A05: $file sin revisión se bloquea"; fi
done
P="$(new_repo a05-docs)"
mkdir -p "$P/docs"
echo "# guía" > "$P/docs/guia.md"; echo "png" > "$P/docs/logo.png"
git -C "$P" add docs
if gate "$P"; then assert_pass "A05: solo documentación e imágenes no exigen receipt"; else assert_fail "A05: solo documentación e imágenes no exigen receipt" "$(cat "$WORK/gate.out")"; fi

# ── A06 / A07 / A11: instalación por proyecto ──────────────────────────────
P="$(new_repo a07)"
cat > "$P/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
# hook del equipo: bloquea archivos con TODO-SECRETO
if git diff --cached | grep -q 'TODO-SECRETO'; then echo "hook-del-equipo: bloqueado" >&2; exit 1; fi
EOF
chmod +x "$P/.git/hooks/pre-commit"
ORIGINAL="$(cat "$P/.git/hooks/pre-commit")"
bash "$ROOT/setup.sh" --target "$P" --force --skip-backup >"$WORK/setup.out" 2>&1
RC=$?
check "setup por proyecto termina OK" test "$RC" = "0"
check "A06: setup por proyecto instala skalling-git-guard.js" test -f "$P/.opencode/plugins/skalling-git-guard.js"
check "A06: setup por proyecto instala lib/git-guard.mjs" test -f "$P/.opencode/plugins/lib/git-guard.mjs"
check "A07: el hook previo se conserva como pre-commit.skalling-prev" test "$(cat "$P/.git/hooks/pre-commit.skalling-prev" 2>/dev/null)" = "$ORIGINAL"
check "A07: el pre-commit activo es el de Skalling" grep -q "skalling-hook" "$P/.git/hooks/pre-commit"
echo "TODO-SECRETO" > "$P/notes.md"
git -C "$P" add notes.md
if (cd "$P" && bash .git/hooks/pre-commit) >"$WORK/hook.out" 2>&1; then
  assert_fail "A07: el hook previo sigue corriendo (encadenado)" "$(cat "$WORK/hook.out")"
else
  check "A07: el hook previo sigue corriendo (encadenado)" grep -q "hook-del-equipo" "$WORK/hook.out"
fi
git -C "$P" reset -q notes.md
bash "$ROOT/setup.sh" --target "$P" --force --skip-backup >"$WORK/setup2.out" 2>&1
check "A07: reinstalar no pisa ni duplica el hook conservado" test "$(cat "$P/.git/hooks/pre-commit.skalling-prev" 2>/dev/null)" = "$ORIGINAL"

bash "$ROOT/setup.sh" --target "$P" --uninstall --force --skip-backup >"$WORK/uninstall.out" 2>&1
check "A11: uninstall restaura el hook original del equipo" test "$(cat "$P/.git/hooks/pre-commit" 2>/dev/null)" = "$ORIGINAL"
check "A11: uninstall no deja pre-commit.skalling-prev" test ! -e "$P/.git/hooks/pre-commit.skalling-prev"
check "A11: uninstall retira pre-push de Skalling" test ! -e "$P/.git/hooks/pre-push"
check "A11: uninstall retira los plugins" test ! -e "$P/.opencode/plugins/skalling-git-guard.js"
check "A11: uninstall retira hooks y scripts distribuidos" test ! -e "$P/.opencode/hooks" -a ! -e "$P/.opencode/scripts"

# core.hooksPath (husky, carpeta versionada): no se toca, se avisa
P="$(new_repo a07-hookspath)"
mkdir -p "$P/.husky"
echo '#!/bin/sh' > "$P/.husky/pre-commit"
git -C "$P" config core.hooksPath .husky
bash "$ROOT/setup.sh" --target "$P" --force --skip-backup >"$WORK/setup3.out" 2>&1
check "A07: con core.hooksPath no se modifica la carpeta del equipo" test "$(cat "$P/.husky/pre-commit")" = '#!/bin/sh'
check "A07: con core.hooksPath se avisa cómo integrar el gate" grep -q "core.hooksPath" "$WORK/setup3.out"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
