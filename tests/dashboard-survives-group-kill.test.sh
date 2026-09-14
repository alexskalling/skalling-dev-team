#!/usr/bin/env bash
# tests/dashboard-survives-group-kill.test.sh — dashboard-server.py sobrevive
# a que se mate el process group de quien lo lanzó.
#
# Bug real reportado en uso: "/skalling-dashboard se cierra solo, no me deja
# ver los planes". Causa: teamdb-dashboard.sh lo lanza con "nohup ... &",
# pero nohup solo ignora SIGHUP -- no saca al proceso del process group del
# bash que lo lanzó. En un script no interactivo (sin job control) un hijo
# en background hereda el MISMO process group que el script padre. Muchos
# harnesses de agentes (OpenCode entre ellos, probablemente) matan el
# process group completo de cada invocación de shell cuando esa invocación
# "termina" -- y un dashboard nohup'd sin más muere con él.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_pass() { echo "✓ $1"; PASS=$((PASS+1)); }
assert_fail() { echo "✗ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 no disponible, se salta"; exit 0; }

FIXTURE="$(mktemp -d)"
FIXTURE="$(cd "$FIXTURE" && pwd -P)"  # misma resolución de symlinks que hace teamdb-dashboard.sh
cleanup() {
  bash "$ROOT/scripts/teamdb-dashboard.sh" stop "$FIXTURE" >/dev/null 2>&1 || true
  [ -n "$FIXTURE" ] && [ -d "$FIXTURE" ] && rm -rf -- "$FIXTURE"
}
trap cleanup EXIT
SKALLING_ROOT="$ROOT" bash "$ROOT/scripts/teamdb-init.sh" "$FIXTURE" >/dev/null 2>&1

export SKALLING_OPENCODE_DIR="$ROOT"

# set -m activa job control aunque el script no sea interactivo: cada job en
# background pasa a tener su PROPIO process group (PGID = su PID). Sin esto,
# un script no interactivo hereda el mismo group que su padre y el test no
# podría aislar "el group de quien lanza" del suyo propio.
set -m
( bash "$ROOT/scripts/teamdb-dashboard.sh" start "$FIXTURE" >/tmp/dashboard-group-kill-test.log 2>&1 ) &
LAUNCHER_PID=$!
set +m

PROJECT_KEY="$(printf '%s' "$FIXTURE" | cksum | awk '{print $1}')"
STATE_DIR="${TMPDIR:-/tmp}/skalling-dashboard-$PROJECT_KEY"

SERVER_PID=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$STATE_DIR/server.pid" ] && SERVER_PID="$(cat "$STATE_DIR/server.pid" 2>/dev/null || true)"
  [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null && break
  sleep 0.2
done

if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
  assert_pass "el dashboard arranca y escribe su PID"
else
  assert_fail "el dashboard arranca y escribe su PID"
  echo "PASS=$PASS FAIL=$FAIL"
  exit 1
fi

# Matar el process group completo del lanzador -- simula lo que hace un
# harness de agente al terminar la invocación de shell que corrió el comando.
kill -TERM -- "-$LAUNCHER_PID" 2>/dev/null || true
sleep 0.5

if kill -0 "$SERVER_PID" 2>/dev/null; then
  assert_pass "el server sobrevive a que se mate el group de quien lo lanzó (setsid)"
else
  assert_fail "el server sobrevive a que se mate el group de quien lo lanzó" "PID $SERVER_PID ya no existe"
fi

PORT="$(cat "$STATE_DIR/server.port" 2>/dev/null || true)"
if [ -n "$PORT" ] && python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$PORT/api/health', timeout=2).read()" >/dev/null 2>&1; then
  assert_pass "el dashboard sigue respondiendo HTTP después del group kill"
else
  assert_fail "el dashboard sigue respondiendo HTTP después del group kill"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
