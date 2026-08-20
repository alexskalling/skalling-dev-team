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
# Source lib-teamdb.sh ANTES del lock (teamdb_lock vive en lib-teamdb.sh)
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

# Lock cross-platform (mkdir-based, sin flock). v0.9.1
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

# Init base schema si la DB no existe
DB_WAS_MISSING=false
if [ ! -f "$(teamdb_project_path "$PROJECT")" ]; then
  DB_WAS_MISSING=true
fi
teamdb_init_project "$PROJECT"

_run_sql() {
  local mig_file="$1"
  local mig_name
  mig_name=$(basename "$mig_file" .sql)

  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] sqlite3 $DB < $mig_file"
    return 0
  fi

  # Verificar si ya se aplicó (applied_migrations; tabla creada por schema v0.9.1)
  # `|| true`: en DBs pre-v0.9.1 la tabla no existe y el query falla; eso no debe
  # matar el script con set -e (bash 3.2 aborta en command substitution fallida).
  local already_applied
  already_applied="$(sqlite3 "$DB" "SELECT 1 FROM applied_migrations WHERE name='$mig_name' LIMIT 1" 2>/dev/null)" || true

  if [ "$already_applied" = "1" ]; then
    echo "    [skip] $mig_name (ya aplicada)"
    return 0
  fi

  # Aplicar. Toleramos errores de idempotencia (table/index/column ya existe):
  # project-schema.sql crea casi todo, así que las migrations 002-010 son
  # esencialmente no-ops en DBs frescas y devuelven parse errors. Lo que
  # importa es el UPDATE schema_meta version al final.
  local rc=0
  sqlite3 "$DB" < "$mig_file" 2>/dev/null || rc=$?

  if [ "$rc" -ne 0 ]; then
    echo "    [partial] $mig_name (rc=$rc — probablemente ya aplicada)"
  else
    echo "    [apply] $mig_name"
  fi

  # Registrar como aplicada (evita loop en runs subsecuentes)
  sqlite3 "$DB" "INSERT INTO applied_migrations (name, applied_at) VALUES ('$mig_name', datetime('now'))" 2>/dev/null || true

  return 0
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
    # Rotación: mantener últimos 5 (portable BSD/GNU; los stamps son ISO, el
    # orden lexicográfico == orden cronológico, y head negativo es GNU-only)
    BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$BACKUP_COUNT" -gt 5 ]; then
      TO_DELETE=$((BACKUP_COUNT - 5))
      find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null \
        | sort | head -n "$TO_DELETE" \
        | while IFS= read -r f; do rm -f -- "$f"; done
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

# FASE 0: si la DB no existía (clon fresco / nunca instalado) y el repo trae un
# dump versionado, restaurar el estado completo desde git. El dump tiene SOLO
# INSERTs con PK explícita; la DB ya se creó desde el schema arriba.
if [ "$DB_WAS_MISSING" = true ] && [ -f "$PROJECT/db/teamdb/team.dump.sql" ]; then
  RESTORE_SCRIPT=""
  for candidate in \
    "$SKALLING_ROOT_DIR/scripts/teamdb-restore.sh" \
    "$SCRIPT_DIR/teamdb-restore.sh"; do
    if [ -f "$candidate" ]; then
      RESTORE_SCRIPT="$candidate"
      break
    fi
  done
  if [ -n "$RESTORE_SCRIPT" ]; then
    echo "teamdb: dump versionado encontrado, restaurando estado..."
    bash "$RESTORE_SCRIPT" "$PROJECT" --force || {
      echo "WARN: restore desde dump falló; continúo con DB vacía (revisar db/teamdb/team.dump.sql)" >&2
    }
  fi
fi

# Verificar que las migrations dejaron el schema correcto; si no, fallar en vez
# de seguir con una DB degradada (los errores de migración idempotentes, como el
# "duplicate column" de 004 sobre DBs nuevas, se toleran arriba).
EXPECTED_VERSION="0.9.3"
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

# Fail-closed: si la DB no se puede abrir, abortar
if ! sqlite3 "$DB" ".tables" >/dev/null 2>&1; then
  echo "ERROR: team.db está corrupta o no se puede abrir" >&2
  echo "       Para regenerar: rm $DB && bash $0 $PROJECT" >&2
  exit 1
fi

# Validar que la DB responde (sin timeout porque macOS no tiene gtimeout)
if ! sqlite3 "$DB" ".tables" >/dev/null 2>&1; then
  echo "ERROR: team.db no responde (corrupta o bloqueada)" >&2
  exit 1
fi

# Fail-closed: verificar que todas las tablas críticas existen
REQUIRED_TABLES="concepts decisions preferences work_in_progress memory_links receipts routing_decisions"
for table in $REQUIRED_TABLES; do
  if ! sqlite3 "$DB" ".tables" | grep -qw "$table"; then
    echo "ERROR: tabla '$table' falta en $DB" >&2
    exit 1
  fi
done

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
