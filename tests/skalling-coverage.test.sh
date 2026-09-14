#!/usr/bin/env bash
# tests/skalling-coverage.test.sh — skalling-coverage.sh corre el comando de
# cobertura detectado en project.yaml, parsea formatos conocidos (Istanbul,
# coverage.py, go tool cover) y nunca inventa un porcentaje.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

FIXTURE="$(mktemp -d)"
trap '[ -n "$FIXTURE" ] && [ -d "$FIXTURE" ] && rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/.opencode" "$FIXTURE/coverage"
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$FIXTURE" >/dev/null 2>&1
DB="$FIXTURE/.opencode/context/team.db"

last_row() {
  sqlite3 "$DB" "SELECT format||'|'||percent||'|'||lines_covered||'|'||lines_total
                  FROM coverage_runs ORDER BY id DESC LIMIT 1"
}

write_yaml() {
  local command="$1"
  cat > "$FIXTURE/.opencode/project.yaml" <<YAML
testing:
  unit:
    available: true
    command: "npm run test"
  coverage:
    available: true
    command: "$command"
YAML
}

# Caso 1: sin comando configurado -> no corre nada, no escribe filas.
write_yaml ""
if ! bash "$ROOT/scripts/skalling-coverage.sh" "$FIXTURE" >/dev/null 2>&1; then
  assert_pass "sin comando configurado: falla en vez de inventar un número"
else
  assert_fail "sin comando configurado: falla en vez de inventar un número"
fi
COUNT0="$(sqlite3 "$DB" "SELECT COUNT(*) FROM coverage_runs")"
if [ "$COUNT0" = "0" ]; then
  assert_pass "sin comando configurado: no escribe ninguna fila"
else
  assert_fail "sin comando configurado: no escribe ninguna fila" "count=$COUNT0"
fi

# Caso 2: formato Istanbul (vitest/jest/nyc) reconocido correctamente.
cat > "$FIXTURE/fake-coverage.sh" <<'SH'
#!/usr/bin/env bash
cat > coverage/coverage-summary.json <<'JSON'
{"total":{"lines":{"total":200,"covered":150,"pct":75}}}
JSON
SH
chmod +x "$FIXTURE/fake-coverage.sh"
write_yaml "bash fake-coverage.sh"
OUT2="$(bash "$ROOT/scripts/skalling-coverage.sh" "$FIXTURE" 2>&1)"
ROW2="$(last_row)"
if [ "$ROW2" = "istanbul|75.0|150|200" ]; then
  assert_pass "formato Istanbul: percent/lines_covered/lines_total correctos"
else
  assert_fail "formato Istanbul: percent/lines_covered/lines_total correctos" "row=$ROW2 out=$OUT2"
fi

# Caso 3: un coverage-summary.json VIEJO (de una corrida anterior) no cuenta
# como fresco si el comando de esta corrida no lo regenera -- si no, un
# resultado stale se reportaría como si fuera de ahora.
sleep 1.1
cat > "$FIXTURE/fake-coverage.sh" <<'SH'
#!/usr/bin/env bash
echo "salida que no vamos a parsear, no toca coverage-summary.json"
SH
OUT3="$(bash "$ROOT/scripts/skalling-coverage.sh" "$FIXTURE" 2>&1)"
FORMAT3="$(sqlite3 "$DB" "SELECT format FROM coverage_runs ORDER BY id DESC LIMIT 1")"
PERCENT3="$(sqlite3 "$DB" "SELECT percent IS NULL FROM coverage_runs ORDER BY id DESC LIMIT 1")"
if [ "$FORMAT3" = "unknown" ] && [ "$PERCENT3" = "1" ]; then
  assert_pass "un coverage-summary.json viejo no se reporta como corrida fresca"
else
  assert_fail "un coverage-summary.json viejo no se reporta como corrida fresca" \
    "format=$FORMAT3 percent_null=$PERCENT3 out=$OUT3"
fi

# Caso 4: coverage.py (formato "coverage json" de Python).
cat > "$FIXTURE/fake-coverage.sh" <<'SH'
#!/usr/bin/env bash
cat > coverage.json <<'JSON'
{"totals":{"percent_covered":88.5,"covered_lines":885,"num_statements":1000}}
JSON
SH
OUT4="$(bash "$ROOT/scripts/skalling-coverage.sh" "$FIXTURE" 2>&1)"
ROW4="$(last_row)"
if [ "$ROW4" = "coverage.py|88.5|885|1000" ]; then
  assert_pass "formato coverage.py: percent/lines_covered/lines_total correctos"
else
  assert_fail "formato coverage.py: percent/lines_covered/lines_total correctos" "row=$ROW4 out=$OUT4"
fi

# Caso 5: comando que falla (exit != 0) -> no escribe ninguna fila nueva.
COUNT_BEFORE="$(sqlite3 "$DB" "SELECT COUNT(*) FROM coverage_runs")"
cat > "$FIXTURE/fake-coverage.sh" <<'SH'
#!/usr/bin/env bash
echo "algo salió mal" >&2
exit 1
SH
if ! bash "$ROOT/scripts/skalling-coverage.sh" "$FIXTURE" >/dev/null 2>&1; then
  assert_pass "comando que falla: el script también falla"
else
  assert_fail "comando que falla: el script también falla"
fi
COUNT_AFTER="$(sqlite3 "$DB" "SELECT COUNT(*) FROM coverage_runs")"
if [ "$COUNT_AFTER" = "$COUNT_BEFORE" ]; then
  assert_pass "comando que falla: no escribe ninguna fila nueva"
else
  assert_fail "comando que falla: no escribe ninguna fila nueva" "antes=$COUNT_BEFORE después=$COUNT_AFTER"
fi

if command -v shellcheck >/dev/null 2>&1; then
  SC_RC=0
  shellcheck "$ROOT/scripts/skalling-coverage.sh" >/dev/null 2>&1 || SC_RC=$?
  if [ "$SC_RC" = "0" ]; then
    assert_pass "skalling-coverage.sh shellcheck 0 errores"
  else
    assert_fail "skalling-coverage.sh shellcheck 0 errores" "rc=$SC_RC"
  fi
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
