#!/usr/bin/env bash
# Centro de control TeamDB: instancia persistente y aislada por proyecto.
set -euo pipefail

usage() {
  cat <<'HELP'
Uso: teamdb-dashboard.sh [start|stop|status] [proyecto]

  start   Inicia (o reutiliza) el dashboard y abre el navegador. Es el predeterminado.
  stop    Detiene solamente el dashboard de este proyecto.
  status  Muestra URL y estado, sin abrir el navegador.

El servidor permanece activo hasta ejecutar stop. El dashboard es de solo lectura.
HELP
}

ACTION="start"
case "${1:-}" in
  start|stop|status) ACTION="$1"; shift ;;
  --help|-h) usage; exit 0 ;;
esac

PROJECT="${1:-$(pwd)}"
if [ ! -d "$PROJECT" ]; then
  echo "ERROR: el proyecto no existe: $PROJECT" >&2
  exit 1
fi
PROJECT="$(cd "$PROJECT" && pwd -P)"
PROJECT_NAME="$(basename "$PROJECT")"
DB_PATH="$PROJECT/.opencode/context/team.db"
PROJECT_KEY="$(printf '%s' "$PROJECT" | cksum | awk '{print $1}')"
STATE_DIR="${TMPDIR:-/tmp}/skalling-dashboard-$PROJECT_KEY"
PIDFILE="$STATE_DIR/server.pid"
PORTFILE="$STATE_DIR/server.port"
LOGFILE="$STATE_DIR/server.log"

OPENCODE_DIR="${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}"
SERVER_SCRIPT="$OPENCODE_DIR/scripts/dashboard-server.py"
HTML_PATH="$OPENCODE_DIR/web/teamdb-dashboard.html"
mkdir -p "$STATE_DIR"

is_running() {
  [ -f "$PIDFILE" ] || return 1
  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -Fq "$SERVER_SCRIPT"
}

dashboard_url() {
  [ -f "$PORTFILE" ] && printf 'http://127.0.0.1:%s/' "$(cat "$PORTFILE")"
}

open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1
  elif command -v wslview >/dev/null 2>&1; then wslview "$url" >/dev/null 2>&1
  elif command -v cmd.exe >/dev/null 2>&1; then cmd.exe /c start "" "$url" >/dev/null 2>&1
  else echo "Abre esta URL: $url"
  fi
}

stop_server() {
  if is_running; then
    local pid
    pid="$(cat "$PIDFILE")"
    kill "$pid"
    for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    echo "Dashboard detenido para $PROJECT_NAME"
  else
    echo "El dashboard de $PROJECT_NAME no estaba activo."
  fi
  rm -f "$PIDFILE" "$PORTFILE"
}

if [ "$ACTION" = "stop" ]; then stop_server; exit 0; fi

if [ "$ACTION" = "status" ]; then
  if is_running; then echo "Activo: $(dashboard_url) ($PROJECT_NAME)"; else echo "Detenido: $PROJECT_NAME"; fi
  exit 0
fi

for required in "$DB_PATH" "$SERVER_SCRIPT" "$HTML_PATH"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: falta $required" >&2
    echo "Ejecuta /skalling-init o install-global.sh y vuelve a intentar." >&2
    exit 1
  fi
done

if ! is_running; then
  rm -f "$PIDFILE" "$PORTFILE"
  PORT="$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")"
  env TDB_DB="$DB_PATH" TDB_HTML="$HTML_PATH" TDB_PROJECT="$PROJECT_NAME" TDB_PORT="$PORT" \
    nohup python3 "$SERVER_SCRIPT" >"$LOGFILE" 2>&1 &
  PID=$!
  printf '%s\n' "$PID" > "$PIDFILE"
  printf '%s\n' "$PORT" > "$PORTFILE"

  READY=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$PORT/api/health', timeout=.3).read()" 2>/dev/null; then READY=1; break; fi
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.1
  done
  if [ "$READY" -ne 1 ]; then
    echo "ERROR: el dashboard no pudo iniciar. Registro: $LOGFILE" >&2
    stop_server >/dev/null 2>&1 || true
    exit 1
  fi
fi

URL="$(dashboard_url)"
echo "Dashboard: $URL"
echo "Solo lectura · se detiene con: teamdb-dashboard.sh stop \"$PROJECT\""
open_url "$URL"
