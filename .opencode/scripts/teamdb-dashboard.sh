#!/usr/bin/env bash
# teamdb-dashboard.sh — inicia/detiene el dashboard de TeamDB
# Uso: teamdb-dashboard.sh [proyecto]
#   Sin args: usa el proyecto actual (pwd)
#   Si el server ya corre: abre el browser (no reinicia)
#   Auto-stop después de 5 min de inactividad

set -euo pipefail

OPENCODE_DIR="${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}"
SERVER_SCRIPT="$OPENCODE_DIR/scripts/dashboard-server.py"
HTML_PATH="$OPENCODE_DIR/web/teamdb-dashboard.html"
PIDFILE="/tmp/teamdb-dashboard.pid"
TIMEOUT_FILE="/tmp/teamdb-dashboard.lastaccess"
TIMEOUT_SECS=300

PROJECT="${1:-$(pwd)}"
DB_PATH="$(realpath "$PROJECT/.opencode/context/team.db" 2>/dev/null || echo "")"
PROJECT_NAME="$(basename "$PROJECT")"

if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
  echo "ERROR: no hay team.db en $PROJECT/.opencode/context/" >&2
  echo "   Ejecutá /skalling-init primero" >&2
  exit 1
fi

find_port() {
  local port=3741
  while nc -z 127.0.0.1 $port 2>/dev/null; do port=$((port+1)); done
  echo $port
}

start_server() {
  local port; port=$(find_port)

  env \
    TDB_DB="$DB_PATH" \
    TDB_HTML="$HTML_PATH" \
    TDB_PROJECT="$PROJECT_NAME" \
    TDB_PORT="$port" \
    TDB_TIMEOUT_FILE="$TIMEOUT_FILE" \
    python3 "$SERVER_SCRIPT" &
  echo $! > "$PIDFILE"
  echo "$port" > "/tmp/teamdb-dashboard.port"

  # Monitor de inactividad
  (
    while kill -0 "$(cat "$PIDFILE")" 2>/dev/null; do
      sleep 30
      if [ -f "$TIMEOUT_FILE" ]; then
        since=$(($(date +%s) - $(cat "$TIMEOUT_FILE")))
        if [ $since -gt $TIMEOUT_SECS ]; then
          kill "$(cat "$PIDFILE")" 2>/dev/null && echo "Server detenido por inactividad (${since}s)"
          rm -f "$PIDFILE" "$TIMEOUT_FILE" "/tmp/teamdb-dashboard.port"
          exit 0
        fi
      fi
    done
  ) &
}

stop_server() {
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null && echo "Server detenido"
    rm -f "$PIDFILE" "$TIMEOUT_FILE" "/tmp/teamdb-dashboard.port"
  fi
}

# Si el server ya corre, abrir browser y salir
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  port=$(cat "/tmp/teamdb-dashboard.port" 2>/dev/null || echo "3741")
  echo "Dashboard ya corriendo en http://localhost:$port/"
  open "http://localhost:$port/"
  exit 0
fi

# Verificar que el server script existe
if [ ! -f "$SERVER_SCRIPT" ]; then
  echo "ERROR: $SERVER_SCRIPT no encontrado. Corr&eacute; install-global.sh" >&2
  exit 1
fi

if [ ! -f "$HTML_PATH" ]; then
  echo "ERROR: $HTML_PATH no encontrado. Corr&eacute; install-global.sh" >&2
  exit 1
fi

start_server
port=$(cat "/tmp/teamdb-dashboard.port")
sleep 1
echo "Dashboard: http://localhost:$port/"
echo "Server corriendo. Se detiene automáticamente después de 5 min de inactividad."
open "http://localhost:$port/"
