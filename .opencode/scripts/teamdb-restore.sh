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

# ── Modo ───────────────────────────────────────────────────────────────────
# transacción: --force sobre una base sana. El dump se aplica DENTRO de una
#   transacción de SQLite sobre la base activa, con el backup tomado bajo el
#   mismo lock de escritura: los escritores concurrentes (teamdb_exec.py no usa
#   el lock de Skalling) esperan y escriben después, nada se pierde. Antes se
#   reemplazaba el archivo y se perdía lo confirmado entre el backup y el
#   reemplazo (tercera auditoría, sobre e95a388).
# candidata: --full-reset o base ausente. Se arma una base nueva aparte y solo
#   reemplaza a la activa si pasa la importación y el integrity_check; si la
#   activa está corrupta se conserva su copia cruda.
if [ "$FULL_RESET" = true ] || [ ! -f "$DB" ]; then MODE=candidate; else MODE=transaction; fi
BACKUP_DIR="$(dirname "$DB")/.backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/team.db.backup-$STAMP"
PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH

# ── Validar el dump ANTES de tocar nada ──────────────────────────────────────
# Solo INSERTs de datos en tablas permitidas; cualquier otra cosa (comandos
# .shell, sentencias DDL/DELETE, tablas desconocidas) aborta sin cambios.
if ! VALIDATION="$(python3 -c '
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
if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
  echo "ERROR: no se pudo crear $BACKUP_DIR; restauración abortada sin cambios" >&2
  exit 1
fi

rotate_backups() {
  local count
  count=$(find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 5 ]; then
    find "$BACKUP_DIR" -maxdepth 1 -name 'team.db.backup-*' -type f 2>/dev/null \
      | sort | head -n "$((count - 5))" \
      | while IFS= read -r f; do rm -f -- "$f"; done  # lens:ok: f viene de find sobre BACKUP_DIR, nunca de input externo
  fi
}

if [ "$MODE" = transaction ]; then
  if ! APPLY_OUT="$(python3 -c '
import os, sqlite3, sys
from teamdb_dump import apply_rows, parse
db_path, dump_path, backup_path = sys.argv[1:4]
rows, problems = parse(dump_path)
if problems:
    sys.exit("\n".join(problems[:20]))
active = sqlite3.connect(db_path, timeout=30)
active.execute("PRAGMA busy_timeout=30000")
try:
    active.execute("BEGIN IMMEDIATE")          # desde acá nadie más confirma escrituras
    tmp = backup_path + ".partial"
    try:
        src = sqlite3.connect("file:" + db_path + "?mode=ro", uri=True, timeout=30)
        out = sqlite3.connect(tmp)
        src.backup(out)
        ok = out.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        out.close(); src.close()
        if not ok:
            raise sqlite3.DatabaseError("integrity_check del respaldo no dio ok")
        os.chmod(tmp, 0o600); os.replace(tmp, backup_path)
    except (sqlite3.Error, OSError) as error:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise ValueError("no se pudo respaldar la base (¿corrupta?): %s. Para reconstruir desde el dump "
                         "conservando el archivo actual: --full-reset" % error)
    count, conflicts = apply_rows(active, rows)
    if active.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise ValueError("la base restaurada no pasó integrity_check")
    active.commit()
except (sqlite3.Error, ValueError) as error:
    active.rollback()
    sys.exit("fila no aplicada o respaldo imposible: %s" % error)
finally:
    active.close()
for conflict in conflicts:
    print("CONFLICTO en el dump: " + conflict + "; se aplicó la última fila", file=sys.stderr)
print(count)
' "$DB" "$DUMP" "$BACKUP_FILE")"; then
    echo "ERROR: restore falló; la base activa queda sin cambios: $APPLY_OUT" >&2
    exit 1
  fi
  echo "backup: $BACKUP_FILE"
  rotate_backups
  echo "restore: $APPLY_OUT filas aplicadas desde $DUMP"
  exit 0
fi

# ── Modo candidata ─────────────────────────────────────────────────────────
if [ -f "$DB" ]; then
  if teamdb_backup_db "$DB" "$BACKUP_FILE"; then
    echo "backup: $BACKUP_FILE"
    rotate_backups
  else
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
    echo "WARN: la base no se pudo respaldar lógicamente (¿corrupta?); copia cruda en $CORRUPT_FILE" >&2
  fi
fi
if [ ! -f "$SCHEMA" ]; then
  echo "ERROR: schema no encontrado: $SCHEMA" >&2
  exit 1
fi
CANDIDATE="$DB.restore-$$"
trap 'rm -f "$CANDIDATE" "$CANDIDATE-wal" "$CANDIDATE-shm"; teamdb_unlock "$LOCK_DIR"' EXIT  # lens:ok: CANDIDATE es ruta propia derivada de DB y el PID
rm -f "$CANDIDATE" "$CANDIDATE-wal" "$CANDIDATE-shm"  # lens:ok: ruta propia derivada de DB y el PID
mkdir -p "$(dirname "$DB")"
sqlite3 "$CANDIDATE" < "$SCHEMA"
sqlite3 "$CANDIDATE" "PRAGMA journal_mode=WAL" >/dev/null 2>&1 || true

if ! APPLY_OUT="$(python3 -c '
import sqlite3, sys
from teamdb_dump import apply_rows, parse
db_path, dump_path = sys.argv[1:3]
rows, problems = parse(dump_path)
if problems:
    sys.exit("\n".join(problems[:20]))
con = sqlite3.connect(db_path, timeout=10)
try:
    con.execute("BEGIN IMMEDIATE")
    count, conflicts = apply_rows(con, rows)
    con.commit()
    if con.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise ValueError("la base restaurada no pasó integrity_check")
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
except (sqlite3.Error, ValueError) as error:
    con.rollback()
    sys.exit("fila no aplicada: %s" % error)
finally:
    con.close()
for conflict in conflicts:
    print("CONFLICTO en el dump: " + conflict + "; se aplicó la última fila", file=sys.stderr)
print(count)
' "$CANDIDATE" "$DUMP")"; then
  echo "ERROR: restore falló aplicando el dump; la base activa queda sin cambios: $APPLY_OUT" >&2
  exit 1
fi

# Reemplazo: el WAL de la base vieja ya quedó en el backup (o en la copia
# cruda); si quedara al lado, SQLite lo aplicaría sobre la base nueva.
rm -f "$DB-wal" "$DB-shm"  # lens:ok: WAL/SHM de la base activa, respaldados arriba
mv -f "$CANDIDATE" "$DB"
rm -f "$CANDIDATE-wal" "$CANDIDATE-shm"  # lens:ok: ruta propia derivada de DB y el PID

echo "restore: $APPLY_OUT filas aplicadas desde $DUMP"
