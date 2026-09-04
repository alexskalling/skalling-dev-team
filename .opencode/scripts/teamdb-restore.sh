#!/usr/bin/env bash
# teamdb-restore.sh — Restaura la DB del proyecto DESDE el dump versionado.
#
# ─────────────────────────────────────────────────────────────────────────────
# FASE 0 — DB única fuente de la verdad: el dump en git es la fotografía.
#
# CUÁNDO SE USA
#   1. Perfil "nunca lo instaló": repo recién clonado. No hay team.db.
#      setup.sh/teamdb-init.sh detecta que no existe DB, ve el dump en git y
#      restaura → el clon levanta TODO el estado (proposals, plans, tasks...).
#   2. Perfil "acaba de hacer pull": la DB local se borró o se corrompió.
#      --force restaura desde la última fotografía commiteada.
#
# SEGURIDAD
#   - NO sobreescribe una DB existente sin --force (evita destruir trabajo).
#   - Con --force hace backup previo en .opencode/context/.backups/ (rotación 5).
#   - El dump contiene SOLO INSERTs (ver teamdb-dump.sh): aplicar sobre una DB
#     creada desde el schema actual es seguro y no duplica (los INSERT llevan
#     PK explícita; el restore usa INSERT OR REPLACE para idempotencia).
#   - Con --full-reset: recrea la DB desde el schema + dump (caso corrupción).
#
# USO
#   bash scripts/teamdb-restore.sh [<project>] [--force] [--full-reset]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

PROJECT="${1:-$(pwd)}"
FORCE=false
FULL_RESET=false
for arg in "${@:2}"; do
  case "$arg" in
    --force) FORCE=true ;;
    --full-reset) FULL_RESET=true; FORCE=true ;;
  esac
done

DB="$(teamdb_project_path "$PROJECT")"
DUMP="$PROJECT/db/teamdb/team.dump.sql"
SCHEMA="${SKALLING_ROOT:-$(dirname "$SCRIPT_DIR")}/sql/project-schema.sql"

# Fail-closed: sin dump versionado no hay nada que restaurar.
if [ ! -f "$DUMP" ]; then
  echo "no dump: $DUMP (nada que restaurar)" >&2
  exit 1
fi

# ── Guard de no-sobreescritura ────────────────────────────────────────────────
if [ -f "$DB" ] && [ "$FORCE" = false ]; then
  echo "ERROR: la DB ya existe: $DB" >&2
  echo "       Usá --force para restaurar encima (con backup previo)." >&2
  exit 1
fi

# Lock cross-platform
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

# ── Backup previo a sobreescritura (rotación 5) ──────────────────────────────
if [ -f "$DB" ]; then
  BACKUP_DIR="$(dirname "$DB")/.backups"
  mkdir -p "$BACKUP_DIR"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="$BACKUP_DIR/team.db.backup-$STAMP"
  if cp "$DB" "$BACKUP_FILE" 2>/dev/null; then
    echo "backup: $BACKUP_FILE"
    BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$BACKUP_COUNT" -gt 5 ]; then
      TO_DELETE=$((BACKUP_COUNT - 5))
      find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null \
        | sort | head -n "$TO_DELETE" \
        | while IFS= read -r f; do rm -f -- "$f"; done
    fi
  else
    echo "WARN: backup falló (¿permisos?)" >&2
  fi
fi

# ── Full reset: recrear desde schema (usa el mismo mecanismo de init) ────────
if [ "$FULL_RESET" = true ]; then
  rm -f "$DB" "$DB-wal" "$DB-shm"
fi

if [ ! -f "$DB" ]; then
  if [ ! -f "$SCHEMA" ]; then
    echo "ERROR: schema no encontrado: $SCHEMA" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$DB")"
  sqlite3 "$DB" < "$SCHEMA"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON" 2>/dev/null || true
  echo "db creada desde schema: $DB"
fi

# ── Aplicar el dump (INSERTs con PK explícita; OR REPLACE = idempotente) ─────
# El dump no trae CREATE TABLE; la DB ya existe (nueva o previa con --force).
# Se transforma INSERT INTO → INSERT OR REPLACE INTO para que re-restaurar
# sobre una DB con datos no duplique ni falle por PK.
INSERT_COUNT="$(grep -c "^INSERT INTO " "$DUMP" 2>/dev/null || true)"
if [ "$INSERT_COUNT" -eq 0 ]; then
  echo "restore: dump vacío (sin INSERTs)" >&2
  exit 0
fi

sed 's/^INSERT INTO /INSERT OR REPLACE INTO /' "$DUMP" | sqlite3 "$DB" 2>&1 || {
  echo "ERROR: restore falló aplicando el dump" >&2
  exit 1
}

echo "restore: $INSERT_COUNT filas aplicadas desde $DUMP"
