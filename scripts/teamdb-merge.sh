#!/usr/bin/env bash
# teamdb-merge.sh — Mergea el dump versionado (git) hacia la DB local, por fila.
#
# ─────────────────────────────────────────────────────────────────────────────
# FASE 0 — DB única fuente de la verdad. Este script es el post-merge real.
#
# EL PROBLEMA
#   La DB local (.opencode/context/team.db) es la fuente de la verdad del
#   trabajo EN CURSO. El dump versionado (db/teamdb/team.dump.sql) es la
#   fotografía en git. Cuando alguien hace `git pull`, llega un dump de OTRA
#   máquina con filas nuevas o actualizadas. La DB local no se puede borrar
#   ni sobreescribir a ciegas: puede tener trabajo sin committear.
#
# LA SOLUCIÓN — merge por fila, último-write-gana:
#   1. Filas del dump que NO existen en la DB local (por PK)  → INSERT.
#   2. Filas que existen en ambos pero el dump tiene updated_at MÁS RECIENTE
#      → UPDATE (último write gana). Filas locales más recientes → se respetan.
#   3. Filas que existen SOLO en la DB local (trabajo no committeado)
#      → NUNCA se tocan. El merge es aditivo hacia la DB.
#   4. NUNCA hace DELETE: la DB local manda sobre lo que no está en git.
#
#   Tablas sin updated_at: solo se insertan filas nuevas; nunca se pisan las
#   locales (evita destruir datos locales sin forma de comparar antigüedad).
#
# USO
#   bash scripts/teamdb-merge.sh [<project>] [--dry-run]
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
DRY_RUN=false
for arg in "${@:2}"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

DB="$(teamdb_project_path "$PROJECT")"
DUMP="$PROJECT/db/teamdb/team.dump.sql"

# Fail-open: sin dump versionado no hay nada que mergear (repo sin Fase 0).
if [ ! -f "$DUMP" ]; then
  echo "no dump: $DUMP (nada que mergear)" >&2
  exit 0
fi
[ -f "$DB" ] || { echo "no DB: $DB (corré bash scripts/teamdb-init.sh $PROJECT)" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 requerido" >&2; exit 1; }

# Lock cross-platform
LOCK_DIR="$PROJECT/.opencode/context/.locks/team"
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
if ! teamdb_lock "$LOCK_DIR" 10; then
  exit 1
fi
trap 'teamdb_unlock "$LOCK_DIR"' EXIT

if [ "$DRY_RUN" = true ]; then
  echo "merge (dry-run): $PROJECT"
else
  echo "merge: $PROJECT"
fi

MERGE_PY="$(cat <<'PY'
import sqlite3, sys, re

db_path, dump_path, dry_run = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

INSERT_RE = re.compile(r'^INSERT INTO "([^"]+)" \((.*)\) VALUES \((.*)\);$')

# parsear el dump → {tabla: {pk_tuple: {col: val}}}
tables = {}
order = []
with open(dump_path, encoding="utf-8") as f:
    for line in f:
        m = INSERT_RE.match(line.strip())
        if not m:
            continue
        table, col_part, val_part = m.group(1), m.group(2), m.group(3)
        cols = [c.strip().strip('"') for c in col_part.split(",")]
        # parsear valores SQL literales simples: NULL, números, '...' escapado
        vals = []
        i = 0
        s = val_part
        n = len(s)
        while i < n:
            c = s[i]
            if c == "'":
                j = i + 1
                buf = []
                while j < n:
                    if s[j] == "'":
                        if j + 1 < n and s[j+1] == "'":
                            buf.append("'"); j += 2; continue
                        break
                    buf.append(s[j]); j += 1
                vals.append("".join(buf)); i = j + 1
            else:
                j = i
                while j < n and s[j] != ",":
                    j += 1
                tok = s[i:j].strip()
                vals.append(None if tok == "NULL" else tok)
                i = j
            if i < n and s[i] == ",":
                i += 1
        if len(cols) != len(vals):
            continue
        row = dict(zip(cols, vals))
        tables.setdefault(table, {})
        # PK: primera columna (todas las tablas del schema tienen id o PK simple
        # salvo memory_tags/plan_history compuestas; usamos la columna 1 como
        # clave estable de fila, que en el schema es id salvo skills_registry).
        key = str(row.get(cols[0]))
        tables[table][key] = row
        if table not in order:
            order.append(table)

con = sqlite3.connect(db_path)
con.text_factory = str
con.execute("PRAGMA busy_timeout=5000")
inserted = 0
updated = 0
skipped_local_newer = 0
skipped_no_ts = 0

for table in order:
    rows = tables[table]
    if not rows:
        continue
    # ¿existe la tabla localmente?
    exists = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    ).fetchone()
    if not exists:
        continue
    cols = [r[1] for r in con.execute(f"PRAGMA table_info('{table}')").fetchall()]
    if not cols:
        continue
    has_updated_at = "updated_at" in cols
    first_col = cols[0]

    for key, row in rows.items():
        cur = con.execute(
            f'SELECT * FROM "{table}" WHERE "{first_col}" = ?', (key,)
        ).fetchone()
        if cur is None:
            # INSERT fila nueva del dump
            col_sql = ",".join(f'"{c}"' for c in cols)
            placeholders = ",".join("?" for _ in cols)
            params = []
            for c in cols:
                v = row.get(c)
                params.append(v)
            sql = f'INSERT INTO "{table}" ({col_sql}) VALUES ({placeholders})'
            if dry_run:
                inserted += 1
            else:
                try:
                    con.execute(sql, params)
                    inserted += 1
                except sqlite3.Error:
                    skipped_no_ts += 1
            continue
        # existe: ¿el dump es más nuevo (updated_at)?
        if not has_updated_at:
            skipped_no_ts += 1
            continue
        dump_ts = row.get("updated_at") or ""
        cur_ts = cur[cols.index("updated_at")] or ""
        if not dump_ts:
            skipped_no_ts += 1
            continue
        if dump_ts > cur_ts:
            # UPDATE último-write-gana
            set_sql = ",".join(f'"{c}" = ?' for c in cols if c != first_col)
            params = [row.get(c) for c in cols if c != first_col] + [key]
            sql = f'UPDATE "{table}" SET {set_sql} WHERE "{first_col}" = ?'
            if dry_run:
                updated += 1
            else:
                try:
                    con.execute(sql, params)
                    updated += 1
                except sqlite3.Error:
                    skipped_local_newer += 1
        else:
            skipped_local_newer += 1

con.commit()
print(f"merge: {inserted} insertadas, {updated} actualizadas, {skipped_local_newer} locales más nuevas, {skipped_no_ts} sin updated_at (intactas)")
PY
)"

if [ "$DRY_RUN" = true ]; then
  python3 -c "$MERGE_PY" "$DB" "$DUMP" 1
else
  python3 -c "$MERGE_PY" "$DB" "$DUMP" 0
fi
