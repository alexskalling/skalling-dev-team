#!/usr/bin/env bash
# teamdb-init.sh — Inicializa teamdb proyecto (idempotente, aplica migrations pendientes)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) PROJECT="$1"; shift ;;
  esac
done
PROJECT="${PROJECT:-$(pwd)}"
SKALLING_ROOT_DIR="$(dirname "$SCRIPT_DIR")"
export SKALLING_ROOT="$SKALLING_ROOT_DIR"
# Fallback: funciona en repo (lib/lib-teamdb.sh) y en global (lib-teamdb.sh)
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

# Init base schema si la DB no existe
teamdb_init_project "$PROJECT"

_run_sql() {
  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] sqlite3 $DB < $1"
  else
    sqlite3 "$DB" < "$1" 2>/dev/null || true
  fi
}

# Si la DB existe pero le faltan tablas nuevas (migrations), aplicarlas (T-2.9)
DB="$(teamdb_project_path "$PROJECT")"

# Backup automático antes de migrar (protege 6 meses de trabajo del usuario)
if [ -f "$DB" ]; then
  BACKUP_DIR="$(dirname "$DB")/.backups"
  mkdir -p "$BACKUP_DIR"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="$BACKUP_DIR/team.db.backup-$STAMP"
  if cp "$DB" "$BACKUP_FILE" 2>/dev/null; then
    echo "teamdb backup: $BACKUP_FILE"
    # Rotación: mantener últimos 5
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/team.db.backup-* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$BACKUP_COUNT" -gt 5 ]; then
      ls -1t "$BACKUP_DIR"/team.db.backup-* | tail -n +6 | xargs -r rm -f
    fi
  else
    echo "WARN: backup de team.db falló (¿permisos?)" >&2
  fi
fi

MIG_DIR="$SKALLING_ROOT_DIR/sql/migrations"
if [ -d "$MIG_DIR" ]; then
  for mig in "$MIG_DIR"/*.sql; do
    [ -f "$mig" ] || continue
    _run_sql "$mig"
  done
fi

# Verificar que las migrations dejaron el schema correcto; si no, fallar en vez
# de seguir con una DB degradada (los errores de migración idempotentes, como el
# "duplicate column" de 004 sobre DBs nuevas, se toleran arriba).
EXPECTED_VERSION="0.7.6"
VERSION="$(sqlite3 "$DB" "SELECT value FROM schema_meta WHERE key='version'" 2>/dev/null || true)"
if [ "$VERSION" != "$EXPECTED_VERSION" ]; then
  echo "ERROR: teamdb schema version=$VERSION, esperado $EXPECTED_VERSION (migrations incompletas)" >&2
  exit 1
fi
HAS_ACTOR_SOURCE="$(sqlite3 "$DB" "SELECT count(*) FROM pragma_table_info('audit_log') WHERE name='actor_source'" 2>/dev/null || true)"
if [ "${HAS_ACTOR_SOURCE:-0}" -lt 1 ]; then
  echo "ERROR: audit_log.actor_source ausente tras migrations (correr git pull + teamdb-init)" >&2
  exit 1
fi

echo "teamdb init: $PROJECT"

# Verificar dashboard (R-7: el dashboard es parte del bundle, no opcional)
OPENCODE_DIR="${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}"
DASHBOARD_HTML="$OPENCODE_DIR/web/teamdb-dashboard.html"
DASHBOARD_SERVER="$OPENCODE_DIR/scripts/dashboard-server.py"
DASHBOARD_LAUNCHER="$OPENCODE_DIR/scripts/teamdb-dashboard.sh"

if [ -f "$DASHBOARD_HTML" ] && [ -f "$DASHBOARD_SERVER" ] && [ -f "$DASHBOARD_LAUNCHER" ]; then
  echo "teamdb dashboard: disponible (corro /skalling-dashboard para abrir)"
else
  echo "teamdb dashboard: archivos faltantes — corro install-global.sh:"
  MISSING=()
  [ ! -f "$DASHBOARD_HTML" ] && MISSING+=("web/teamdb-dashboard.html")
  [ ! -f "$DASHBOARD_SERVER" ] && MISSING+=("scripts/dashboard-server.py")
  [ ! -f "$DASHBOARD_LAUNCHER" ] && MISSING+=("scripts/teamdb-dashboard.sh")
  printf '   - %s\n' "${MISSING[@]}"
  echo "   bash $SKALLING_ROOT_DIR/install-global.sh"
fi
