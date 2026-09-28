#!/usr/bin/env bash
# teamdb-ensure-current.sh — migra la TeamDB del proyecto si está atrasada.
#
# Las migraciones solo corrían con /skalling-init, setup.sh o teamdb-init.sh a
# mano: después de un /skalling-update o de un pull que trae scripts nuevos, la
# base de cada persona quedaba en la versión vieja hasta que alguien se
# acordara (en 0.13.0 eso rompió toda escritura de memoria). Lo llaman
# skalling-session-start.sh (inicio de cada sesión) y el hook post-merge.
#
# Solo migra hacia adelante (base más vieja que los scripts); las migraciones
# son aditivas e idempotentes. Nunca crea una base: sin team.db no hace nada.
#
# Uso: teamdb-ensure-current.sh <proyecto>
# Salida: una línea si migró; silencio si ya estaba al día. Exit 1 si falló.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:?Uso: teamdb-ensure-current.sh <proyecto>}"
DB="$PROJECT/.opencode/context/team.db"
INIT="$SCRIPT_DIR/teamdb-init.sh"

[ -f "$DB" ] && [ -f "$INIT" ] || exit 0
command -v sqlite3 >/dev/null 2>&1 || exit 0

EXPECTED="$(sed -n 's/^EXPECTED_VERSION="\(.*\)"$/\1/p' "$INIT" | head -1)"
CURRENT="$(sqlite3 "file:$DB?mode=ro" "SELECT value FROM schema_meta WHERE key='version'" 2>/dev/null || true)"
[ -n "$EXPECTED" ] && [ -n "$CURRENT" ] || exit 0
[ "$CURRENT" = "$EXPECTED" ] && exit 0

# Solo hacia adelante: una base más nueva que estos scripts (otra instalación
# más reciente en la misma máquina) no se toca.
if ! python3 -c 'import sys
v = lambda s: tuple(int(x) for x in s.split("."))
sys.exit(0 if v(sys.argv[1]) < v(sys.argv[2]) else 1)' "$CURRENT" "$EXPECTED" 2>/dev/null; then
  exit 0
fi

if bash "$INIT" "$PROJECT" >/dev/null 2>&1; then
  echo "TeamDB del proyecto actualizada: $CURRENT → $EXPECTED"
else
  echo "AVISO: no se pudo actualizar TeamDB ($CURRENT → $EXPECTED): correr bash $INIT \"$PROJECT\" y revisar el error" >&2
  exit 1
fi
