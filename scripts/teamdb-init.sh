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
  mig_name="$(basename "$mig_file")"
  mig_name="${mig_name%.*}"

  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] sqlite3 $DB < $mig_file"
    return 0
  fi

  if [ "$DB_WAS_MISSING" = true ]; then
    echo "    [baseline] $mig_name (incluida en schema actual)"
    return 0
  fi
  case $'\n'"$APPLIED_MIGRATIONS"$'\n' in
    *$'\n'"$mig_name"$'\n'*)
      echo "    [skip] $mig_name (ya aplicada)"
      return 0 ;;
  esac

  local migration_error
  migration_error="$(mktemp)"
  local migration_rc=0
  case "$mig_file" in
    *.py) python3 "$mig_file" "$DB" 2>"$migration_error" || migration_rc=$? ;;
    *) sqlite3 "$DB" < "$mig_file" 2>"$migration_error" || migration_rc=$? ;;
  esac
  if [ "$migration_rc" -ne 0 ]; then
    echo "ERROR: falló migration $mig_name; no se registrará como aplicada" >&2
    sed -n '1,12p' "$migration_error" >&2
    rm -f "$migration_error"
    return 1
  fi
  rm -f "$migration_error"
  echo "    [apply] $mig_name"

  # $mig_name YA corrió y comiteó de verdad (la migration tiene su propio
  # BEGIN/COMMIT) -- esto solo registra el hecho. Si ESTA escritura falla
  # (lock, timeout, lo que sea) y se ignora en silencio, la migration queda
  # invisible para siempre: el próximo bootstrap la va a reintentar contra un
  # schema que YA tiene sus cambios, y va a fallar con "duplicate column
  # name"/"already exists" -- exactamente lo que le pasó a un proyecto real
  # con la migration 009. No hay forma de deshacer $mig_name desde acá (ya
  # comiteó); lo único que se puede hacer es fallar fuerte para que alguien
  # se entere y corrija el registro a mano, en vez de que quede corrompido
  # en silencio.
  if ! teamdb_exec_write "$DB" \
        "INSERT INTO applied_migrations(name, applied_at) VALUES(?, datetime('now'))" \
        "$mig_name" >/dev/null; then
    echo "ERROR: $mig_name aplicó sus cambios reales (ya comiteados, no se pueden deshacer) pero no se pudo registrar en applied_migrations. Un bootstrap futuro va a reintentarla y va a fallar con 'ya existe'/'duplicate column'. Registrar la fila a mano: INSERT INTO applied_migrations(name, applied_at) VALUES('$mig_name', datetime('now'));" >&2
    return 1
  fi

  return 0
}

# Si la DB existe pero le faltan tablas nuevas (migrations), aplicarlas (T-2.9)
DB="$(teamdb_project_path "$PROJECT")"

# Leer el inventario una vez: no lanzar tres Python por cada migración.
MIG_DIR="$SKALLING_ROOT_DIR/sql/migrations"
MIGRATIONS="$(python3 - "$MIG_DIR" <<'PYLIST'
from pathlib import Path
import sys
root = Path(sys.argv[1])
print('\n'.join(sorted(p.name for p in root.iterdir() if p.suffix in {'.sql', '.py'}))) if root.is_dir() else None
PYLIST
)"
APPLIED_MIGRATIONS="$(sqlite3 "$DB" 'SELECT name FROM applied_migrations' 2>/dev/null || true)"
PENDING=false
while IFS= read -r mig_base; do
  [ -n "$mig_base" ] || continue
  case $'\n'"$APPLIED_MIGRATIONS"$'\n' in
    *$'\n'"${mig_base%.*}"$'\n'*) ;;
    *) PENDING=true ;;
  esac
done <<< "$MIGRATIONS"

# El schema nuevo ya contiene las migraciones: registrar el baseline de modo
# atómico por la misma frontera protegida que las escrituras individuales.
if [ "$DB_WAS_MISSING" = true ] && [ "$DRY_RUN" = false ]; then
  BASELINE_BATCHES="$(python3 - "$MIGRATIONS" <<'PYBASE'
import json, sys
print(json.dumps([{'sql': "INSERT OR IGNORE INTO applied_migrations(name, applied_at) VALUES(?, datetime('now'))",
                   'params': [name.rsplit('.', 1)[0]]} for name in sys.argv[1].splitlines() if name]))
PYBASE
)"
  if ! teamdb_exec_multi "$DB" "$BASELINE_BATCHES" >/dev/null; then
    echo "ERROR: no se pudo registrar el baseline de migraciones; inicialización incompleta" >&2
    exit 1
  fi
fi

# Respaldar solo antes de modificar una base existente.
# Backup automático antes de migrar (protege 6 meses de trabajo del usuario)
if [ "$DB_WAS_MISSING" = false ] && [ "$PENDING" = true ] && [ "$DRY_RUN" = false ]; then
  BACKUP_DIR="$(dirname "$DB")/.backups"
  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="$BACKUP_DIR/team.db.backup-$STAMP"
  # Consistente (API backup, incluye el WAL) y verificado; sin respaldo no se
  # migra: una migración puede fallar a medias.
  if teamdb_backup_db "$DB" "$BACKUP_FILE"; then
    echo "teamdb backup: $BACKUP_FILE"
    bash "$SCRIPT_DIR/teamdb-prune-backups.sh" "$PROJECT" --keep 5
  else
    echo "ERROR: no se pudo respaldar $DB; no se aplican migraciones sin respaldo" >&2
    exit 1
  fi
fi

MIG_DIR="$SKALLING_ROOT_DIR/sql/migrations"
if [ -d "$MIG_DIR" ]; then
  # .sql y .py en orden numérico (un .py es DDL condicional que SQL no puede).
  while IFS= read -r mig_base; do
    [ -n "$mig_base" ] || continue
    _run_sql "$MIG_DIR/$mig_base"
  done <<< "$MIGRATIONS"
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
    # teamdb-restore.sh toma el mismo lock: con el nuestro tomado esperaba 10 s
    # y fallaba, así que un clon nuevo nunca restauraba la memoria del equipo.
    teamdb_unlock "$LOCK_DIR"
    RESTORE_RC=0
    bash "$RESTORE_SCRIPT" "$PROJECT" --force || RESTORE_RC=$?
    if ! teamdb_lock "$LOCK_DIR" 10; then
      echo "ERROR: no se pudo retomar el lock de TeamDB tras restaurar" >&2
      exit 1
    fi
    [ "$RESTORE_RC" -eq 0 ] || {
      echo "ERROR: restore desde dump falló; TeamDB no quedó inicializada" >&2
      exit 1
    }
  fi
fi

# Verificar que las migrations dejaron el schema correcto; si no, fallar en vez
# de seguir con una DB degradada (los errores de migración idempotentes, como el
# "duplicate column" de 004 sobre DBs nuevas, se toleran arriba).
EXPECTED_VERSION="0.15.3"
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
