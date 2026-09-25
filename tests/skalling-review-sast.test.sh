#!/usr/bin/env bash
# tests/skalling-review-sast.test.sh — lens "sast" de skalling-review.sh:
# semgrep real (taint-aware) sobre los archivos tocados, no solo el patrón de
# una línea suelta como los otros 4 lenses. Sigue el mismo principio que
# git-gate.py/teamdb-seal-receipt.sh esta sesión: si la herramienta externa
# no está disponible, nunca queda indistinguible de una corrida que sí la
# tuvo -- deja un INFO explícito, sin bloquear (no se puede exigir semgrep
# instalado en toda máquina para siempre bloquear si falta).
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TESTS_DIR")"
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
  printf 'texto\n' > "$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
  bash "$ROOT/scripts/teamdb-init.sh" "$dir" >/dev/null 2>&1
}

# ── sin semgrep instalado: no bloquea, deja INFO explícito ──
NO_SEMGREP_PROJECT="$TMP/no-semgrep"
new_project "$NO_SEMGREP_PROJECT"
printf 'print("hola")\n' > "$NO_SEMGREP_PROJECT/app.py"
git -C "$NO_SEMGREP_PROJECT" add app.py
OUT_NO_SEMGREP="$(PATH="/usr/bin:/bin" bash "$ROOT/scripts/skalling-review.sh" --lens sast --cwd "$NO_SEMGREP_PROJECT" 2>&1)"
if command -v semgrep >/dev/null 2>&1; then
  assert_pass "(semgrep SÍ está instalado en esta máquina -- se salta el caso 'sin semgrep', cubierto abajo con PATH acotado)"
elif grep -q "semgrep no está instalado" <<< "$OUT_NO_SEMGREP" && grep -q "REVIEW: PASS" <<< "$OUT_NO_SEMGREP"; then
  assert_pass "sin semgrep instalado: no bloquea, deja INFO explícito"
else
  assert_fail "sin semgrep instalado: no bloquea, deja INFO explícito" "out=$OUT_NO_SEMGREP"
fi
# Con PATH acotado (sin semgrep aunque esta máquina lo tenga), el mismo caso
# es reproducible siempre, no solo cuando la máquina no lo tiene instalado.
OUT_PATH_SIN_SEMGREP="$(PATH="/usr/bin:/bin" bash "$ROOT/scripts/skalling-review.sh" --lens sast --cwd "$NO_SEMGREP_PROJECT" 2>&1)"
if grep -q "semgrep no está instalado" <<< "$OUT_PATH_SIN_SEMGREP" && grep -q "REVIEW: PASS" <<< "$OUT_PATH_SIN_SEMGREP"; then
  assert_pass "con PATH sin semgrep: no bloquea, deja INFO explícito (reproducible siempre)"
else
  assert_fail "con PATH sin semgrep: no bloquea, deja INFO explícito (reproducible siempre)" "out=$OUT_PATH_SIN_SEMGREP"
fi

if command -v semgrep >/dev/null 2>&1; then
  # ── con semgrep: SQLi multi-hop (taint) real → BLOCKER ──
  VULN_PROJECT="$TMP/vuln"
  new_project "$VULN_PROJECT"
  cat > "$VULN_PROJECT/app.py" <<'EOF'
from flask import Flask, request
import sqlite3
app = Flask(__name__)
@app.route("/user")
def handler():
    conn = sqlite3.connect("db.sqlite")
    cursor = conn.cursor()
    dato = request.args.get("id")
    parte = dato
    query = f"SELECT * FROM t WHERE id = {parte}"
    cursor.execute(query)
    return "ok"
EOF
  git -C "$VULN_PROJECT" add app.py
  OUT_VULN="$(bash "$ROOT/scripts/skalling-review.sh" --lens sast --cwd "$VULN_PROJECT" 2>&1 || true)"
  if grep -q "BLOCKER.*sast" <<< "$OUT_VULN" && grep -q "REVIEW: FAIL" <<< "$OUT_VULN"; then
    assert_pass "SQLi de dos saltos (dato -> parte -> query -> execute) detectado como BLOCKER"
  else
    assert_fail "SQLi de dos saltos (dato -> parte -> query -> execute) detectado como BLOCKER" "out=$OUT_VULN"
  fi

  # ── con semgrep: query parametrizada → sin findings ──
  CLEAN_PROJECT="$TMP/clean"
  new_project "$CLEAN_PROJECT"
  cat > "$CLEAN_PROJECT/app.py" <<'EOF'
from flask import Flask, request
import sqlite3
app = Flask(__name__)
@app.route("/user")
def handler():
    conn = sqlite3.connect("db.sqlite")
    cursor = conn.cursor()
    dato = request.args.get("id")
    cursor.execute("SELECT * FROM t WHERE id = ?", (dato,))
    return "ok"
EOF
  git -C "$CLEAN_PROJECT" add app.py
  OUT_CLEAN="$(bash "$ROOT/scripts/skalling-review.sh" --lens sast --cwd "$CLEAN_PROJECT" 2>&1 || true)"
  if grep -q "REVIEW: PASS (0 findings" <<< "$OUT_CLEAN"; then
    assert_pass "query parametrizada: sin findings, sin falso positivo"
  else
    assert_fail "query parametrizada: sin findings, sin falso positivo" "out=$OUT_CLEAN"
  fi

  # ── con semgrep: lens:ok en cualquier línea del rango del finding lo suprime ──
  OK_PROJECT="$TMP/lens-ok"
  new_project "$OK_PROJECT"
  cat > "$OK_PROJECT/app.py" <<'EOF'
from flask import Flask, request
import sqlite3
app = Flask(__name__)
@app.route("/user")
def handler():
    conn = sqlite3.connect("db.sqlite")
    cursor = conn.cursor()
    dato = request.args.get("id")
    parte = dato
    query = f"SELECT * FROM t WHERE id = {parte}"  # lens:ok: motivo de prueba
    cursor.execute(query)
    return "ok"
EOF
  git -C "$OK_PROJECT" add app.py
  OUT_OK="$(bash "$ROOT/scripts/skalling-review.sh" --lens sast --cwd "$OK_PROJECT" 2>&1 || true)"
  if grep -q "REVIEW: PASS (0 findings" <<< "$OUT_OK"; then
    assert_pass "lens:ok en la línea del source (aunque el finding se reporte en el sink) suprime el hallazgo"
  else
    assert_fail "lens:ok en la línea del source (aunque el finding se reporte en el sink) suprime el hallazgo" "out=$OUT_OK"
  fi
else
  echo "(semgrep no disponible en esta máquina -- se saltan los 3 casos que lo requieren; no cuenta como fallo)"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
