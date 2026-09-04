#!/usr/bin/env bash
# teamdb-dump.sh — Genera el dump canónico versionado de la DB del proyecto.
#
# ─────────────────────────────────────────────────────────────────────────────
# FASE 0 — DB como única fuente de la verdad, con fotografía en git.
#
# EL PROBLEMA QUE RESUELVE
#   Antes: teamdb-export.sh volcaba data_*.sql a .opencode/context/teamdb/, una
#   ruta GITIGNORED. Es decir: el "export" nunca llegaba a git y el post-merge
#   no tenía NADA que importar (el dir estaba vacío). La DB podía cambiar en
#   una máquina y nadie se enteraba en las otras.
#
# LA SOLUCIÓN (este script)
#   Genera UN archivo versionado y mergeable: db/teamdb/team.dump.sql
#   - Una línea = UNA fila (INSERT con columnas explícitas y orden por PK).
#   - Determinista byte a byte: mismo contenido ⇒ mismo archivo ⇒ git diff real.
#   - Mergeable por fila: git mergea líneas independientes sin conflicto.
#   - Sin timestamps ni cabeceras volátiles (nada que genere ruido en el diff).
#   - Excluye: audit_log (trazabilidad local que crece), applied_migrations
#     (estado local de migraciones), schema_meta (se regenera), FTS virtuales
#     (se reconstruyen por triggers).
#   - Fail-closed ante secretos: si una columna nombrada como secreto (o un
#     valor con formato de token/llave) aparece en los datos, el dump NO se
#     escribe y el script falla. Nada de credenciales viajan a git.
#
# USO
#   bash scripts/teamdb-dump.sh [<project>] [--stdout]
#   --stdout   imprime el dump en stdout en vez de escribir el archivo
#              (útil para comparar sin tocar el working tree)
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
STDOUT_MODE=false
if [ "${2:-}" = "--stdout" ]; then STDOUT_MODE=true; fi

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "ERROR: no DB: $DB (corré bash scripts/teamdb-init.sh $PROJECT)" >&2; exit 1; }

# Tablas de DATOS sincronizables entre máquinas (excluye audit_log/migrations).
DUMP_TABLES=(concepts decisions preferences known_problems work_in_progress tags memory_tags memory_links proposals plans specs design_notes tasks task_dependencies task_claims plan_history task_context_capsules skills_registry routing_decisions receipts task_lock_history attempts)

# Directorio de salida versionado (NO en .gitignore)
OUT_DIR="$PROJECT/db/teamdb"
OUT_FILE="$OUT_DIR/team.dump.sql"

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 requerido" >&2; exit 1; }

PYGEN="$(cat <<'PY'
import sqlite3, sys, re

db, tables = sys.argv[1], sys.argv[2:]

SENSITIVE_COL_RE = re.compile(r'(?i)(api[_-]?key|password|passwd|secret|credential|private[_-]?key)')
SENSITIVE_VALUE_RE = re.compile(r'(?i)(ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|AKIA[0-9A-Z]{16}|Bearer [A-Za-z0-9._-]{20,}|BEGIN [A-Z ]*PRIVATE KEY)')

con = sqlite3.connect(db)
con.text_factory = str

out = []
secret_hits = []

for t in tables:
    # Tabla puede no existir en DBs viejas sin migraciones completas: skip.
    exists = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (t,)
    ).fetchone()
    if not exists:
        continue
    cols = [r[1] for r in con.execute(f"PRAGMA table_info('{t}')").fetchall()]
    if not cols:
        continue
    # Orden determinista: por PK explícita si existe, si no por la primera col.
    pk_cols = [r[1] for r in con.execute(f"PRAGMA table_info('{t}')").fetchall() if r[5] > 0]
    order_cols = pk_cols if pk_cols else [cols[0]]
    order_sql = ",".join(f'"{c}"' for c in order_cols)
    # Detecta columnas sensibles POR NOMBRE (valores no nulos ⇒ bloquea)
    for c in cols:
        if SENSITIVE_COL_RE.search(c):
            n = con.execute(
                f'SELECT COUNT(*) FROM "{t}" WHERE "{c}" IS NOT NULL AND "{c}" != ?', ('',)
            ).fetchone()[0]
            if n:
                secret_hits.append(f'{t}.{c} ({n} valores)')

    col_sql = ",".join(f'"{c}"' for c in cols)
    rows = con.execute(f'SELECT {col_sql} FROM "{t}" ORDER BY {order_sql}').fetchall()
    for row in rows:
        vals = []
        for v in row:
            if v is None:
                vals.append("NULL")
            elif isinstance(v, (int, float)):
                vals.append(str(v))
            else:
                s = str(v)
                if SENSITIVE_VALUE_RE.search(s):
                    secret_hits.append(f'{t} valor con formato de secreto')
                vals.append("'" + s.replace("'", "''") + "'")
        out.append(f'INSERT INTO "{t}" ({col_sql}) VALUES ({",".join(vals)});')

if secret_hits:
    sys.stderr.write("ERROR: el dump contiene datos sensibles; no se escribe.\n")
    for h in sorted(set(secret_hits)):
        sys.stderr.write(f"  - {h}\n")
    sys.exit(3)

for line in out:
    sys.stdout.write(line + "\n")
PY
)"

# La generación real: pasar el heredoc a python con argumentos
PY_OUT="$(python3 -c "$PYGEN" "$DB" "${DUMP_TABLES[@]}" 2>&1)" || {
  # Si python falló con exit 3 (secretos), el mensaje ya está en stderr
  rc=$?
  echo "[ERROR] teamdb-dump falló (rc=$rc)" >&2
  exit "$rc"
}

if [ "$STDOUT_MODE" = true ]; then
  printf '%s\n' "-- teamdb dump v1"
  printf '%s\n' "-- Generado por teamdb-dump.sh. NO editar a mano; el diff se mergea por fila."
  printf '%s\n' "-- Source of truth: .opencode/context/team.db (la DB local). Este archivo es su fotografía."
  printf '%s\n' "$PY_OUT"
  exit 0
fi

mkdir -p "$OUT_DIR"
{
  printf '%s\n' "-- teamdb dump v1"
  printf '%s\n' "-- Generado por teamdb-dump.sh. NO editar a mano; el diff se mergea por fila."
  printf '%s\n' "-- Source of truth: .opencode/context/team.db (la DB local). Este archivo es su fotografía."
  printf '%s\n' "$PY_OUT"
} > "$OUT_FILE.tmp"

mv "$OUT_FILE.tmp" "$OUT_FILE"
echo "dump: $OUT_FILE"
echo "hash: $(shasum -a 256 "$OUT_FILE" | cut -c1-16)"
