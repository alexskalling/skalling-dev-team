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
# Consistente (API backup, incluye el WAL) y verificado. Si no se pudo
# respaldar, no se toca nada: la restauración puede reemplazar filas y
# --full-reset borra la base.
if [ -f "$DB" ]; then
  BACKUP_DIR="$(dirname "$DB")/.backups"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="$BACKUP_DIR/team.db.backup-$STAMP"
  if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    echo "ERROR: no se pudo crear $BACKUP_DIR; restauración abortada sin cambios" >&2
    exit 1
  fi
  if teamdb_backup_db "$DB" "$BACKUP_FILE"; then
    echo "backup: $BACKUP_FILE"
  elif [ "$FULL_RESET" = true ]; then
    # Base ilegible (corrupta): el backup lógico no puede leerla, pero
    # --full-reset es justamente para este caso. Se conserva el archivo
    # crudo (con su WAL) y se reconstruye desde el dump.
    CORRUPT_FILE="$BACKUP_DIR/team.db.corrupt-$STAMP"
    for suffix in "" "-wal" "-shm"; do
      if [ -f "$DB$suffix" ] && ! cp -p "$DB$suffix" "$CORRUPT_FILE$suffix"; then
        echo "ERROR: no se pudo conservar la copia cruda de $DB$suffix; restauración abortada sin cambios" >&2
        exit 1
      fi
    done
    BACKUP_FILE=""
    echo "WARN: la base no se pudo respaldar lógicamente (¿corrupta?); copia cruda en $CORRUPT_FILE" >&2
  else
    echo "ERROR: no se pudo respaldar $DB (¿base corrupta?); restauración abortada sin cambios." >&2
    echo "       Para reconstruir desde el dump conservando el archivo actual: --full-reset" >&2
    exit 1
  fi
  BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BACKUP_COUNT" -gt 5 ]; then
    TO_DELETE=$((BACKUP_COUNT - 5))
    find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null \
      | sort | head -n "$TO_DELETE" \
      | while IFS= read -r f; do rm -f -- "$f"; done  # lens:ok: f viene de find sobre BACKUP_DIR, nunca de input externo
  fi
fi

# ── Validar el dump ANTES de tocar la base ───────────────────────────────────
# Solo INSERTs de datos en tablas permitidas; cualquier otra cosa (comandos
# .shell, sentencias DDL/DELETE, tablas desconocidas) aborta sin cambios.
if ! VALIDATION="$(PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 -c '
import sys
from teamdb_dump import parse
rows, problems = parse(sys.argv[1])
for problem in problems[:20]:
    print(problem)
sys.exit(1 if problems else 0)
' "$DUMP" 2>&1)"; then
  echo "ERROR: el dump contiene algo que no son datos; restauración abortada sin cambios:" >&2
  printf '%s\n' "$VALIDATION" >&2
  exit 1
fi

# ── Base candidata: se restaura en un archivo aparte y solo reemplaza a la
# activa si todo salió bien (auditoría de c7517ea: --full-reset borraba la base
# antes de importar, un INSERT con una columna inexistente la dejaba vacía y
# el mensaje decía "sin cambios"). ─────────────────────────────────────────────
CANDIDATE="$DB.restore-$$"
trap 'rm -f "$CANDIDATE" "$CANDIDATE-wal" "$CANDIDATE-shm"; teamdb_unlock "$LOCK_DIR"' EXIT  # lens:ok: CANDIDATE es ruta propia derivada de DB y el PID
rm -f "$CANDIDATE" "$CANDIDATE-wal" "$CANDIDATE-shm"  # lens:ok: ruta propia derivada de DB y el PID
mkdir -p "$(dirname "$DB")"
if [ "$FULL_RESET" = true ] || [ ! -f "$DB" ] || [ -z "${BACKUP_FILE:-}" ]; then
  if [ ! -f "$SCHEMA" ]; then
    echo "ERROR: schema no encontrado: $SCHEMA" >&2
    exit 1
  fi
  sqlite3 "$CANDIDATE" < "$SCHEMA"
  sqlite3 "$CANDIDATE" "PRAGMA journal_mode=WAL" >/dev/null 2>&1 || true
else
  # Copia consistente y verificada de la base actual (el backup recién hecho).
  cp "$BACKUP_FILE" "$CANDIDATE"
fi

# ── Aplicar el dump: filas validadas, parámetros vinculados, una transacción ─
# Idempotente: una fila con la misma PK se reemplaza (DELETE + INSERT, para
# que los triggers de FTS y versión se enteren; INSERT OR REPLACE no dispara
# los de borrado y deja el índice FTS inconsistente).
if ! APPLY_OUT="$(PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 -c '
import sqlite3, sys
from teamdb_dump import TABLES, VERSIONED, parse
db_path, dump_path = sys.argv[1:3]
rows, problems = parse(dump_path)
if problems:
    sys.exit("\n".join(problems[:20]))
con = sqlite3.connect(db_path, timeout=10)
con.execute("PRAGMA busy_timeout=5000")
count = 0
try:
    con.execute("BEGIN IMMEDIATE")
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type=\"table\"")}
    for table in TABLES:
        if table not in rows:
            continue
        info = con.execute("PRAGMA table_info(\"%s\")" % table).fetchall()
        if not info:
            raise ValueError("tabla ausente en la base local: " + table)
        local = {r[1] for r in info}
        pk = [r[1] for r in sorted(info, key=lambda r: r[5]) if r[5] > 0]
        for row in rows[table]:
            version = row.pop("__version", None)
            unknown = set(row) - local
            if unknown:
                raise ValueError("%s: columnas desconocidas %s" % (table, sorted(unknown)))
            if pk and all(c in row for c in pk):
                con.execute("DELETE FROM \"%s\" WHERE %s" % (table, " AND ".join("\"%s\" IS ?" % c for c in pk)),
                            [row[c] for c in pk])
            names = ",".join("\"%s\"" % c for c in row)
            con.execute("INSERT INTO \"%s\" (%s) VALUES (%s)" % (table, names, ",".join("?" * len(row))),
                        list(row.values()))
            if version and table in VERSIONED and "memory_versions" in tables:
                con.execute("INSERT INTO memory_versions(table_name, slug, updated_at) VALUES (?,?,?) "
                            "ON CONFLICT(table_name, slug) DO UPDATE SET updated_at=excluded.updated_at",
                            (table, row.get("slug"), version))
            count += 1
    con.commit()
    if con.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise ValueError("la base restaurada no pasó integrity_check")
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
except (sqlite3.Error, ValueError) as error:
    con.rollback()
    sys.exit("fila no aplicada: %s" % error)
finally:
    con.close()
print(count)
' "$CANDIDATE" "$DUMP" 2>&1)"; then
  echo "ERROR: restore falló aplicando el dump; la base activa queda sin cambios: $APPLY_OUT" >&2
  exit 1
fi

# ── Reemplazo: el WAL de la base vieja ya quedó en el backup (o en la copia
# cruda); si quedara al lado, SQLite lo aplicaría sobre la base nueva. ─────────
rm -f "$DB-wal" "$DB-shm"  # lens:ok: WAL/SHM de la base activa, respaldados arriba
mv -f "$CANDIDATE" "$DB"
rm -f "$CANDIDATE-wal" "$CANDIDATE-shm"  # lens:ok: ruta propia derivada de DB y el PID

echo "restore: $APPLY_OUT filas aplicadas desde $DUMP"
