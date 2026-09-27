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
# LA SOLUCIÓN — merge por entidad, último-write-gana:
#   0. Cada máquina asigna ids propios, así que las filas se emparejan por
#      clave natural (slug, name, plan+slug...) y no por id. Los ids remotos
#      se traducen a ids locales y las FKs de los hijos (tasks.plan_id,
#      memory_tags.memory_id...) se reescriben con esa traducción.
#   1. Entidades del dump que NO existen localmente → INSERT (conserva el id
#      remoto si está libre; si no, SQLite asigna uno nuevo).
#   2. Entidades en ambos lados con updated_at del dump MÁS RECIENTE
#      → UPDATE (último write gana). Locales más recientes → se respetan.
#   3. Filas que existen SOLO en la DB local (trabajo no committeado)
#      → NUNCA se tocan. El merge es aditivo hacia la DB.
#   4. NUNCA hace DELETE: la DB local manda sobre lo que no está en git.
#
#   Tablas sin updated_at: solo se insertan entidades nuevas; nunca se pisan
#   las locales. Los registros de eventos sin clave natural (plan_history,
#   routing_decisions...) se comparan por fila completa para no duplicarlos.
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

# Cada máquina asigna ids autoincrementales por su cuenta: el id de una fila
# remota NO identifica la misma entidad en la DB local (Alice y Bob crean
# ambos el concepto id=1). Las entidades se emparejan por clave natural, los
# ids remotos se traducen a ids locales y las claves foráneas de los hijos se
# reescriben con esa traducción. Orden: padres antes que hijos.
#   tabla: (clave natural, {columna FK: tabla padre})
# Una clave None = registro de eventos sin clave natural: se compara la fila
# completa (sin id) para no duplicarla.
SPECS = [
    ("concepts", ("slug",), {}),
    ("decisions", ("slug",), {}),
    ("preferences", ("slug",), {}),
    ("known_problems", ("slug",), {}),
    ("work_in_progress", ("slug",), {"parent_id": "work_in_progress"}),
    ("tags", ("name",), {}),
    ("proposals", ("slug",), {}),
    ("plans", ("slug",), {"proposal_id": "proposals"}),
    ("specs", ("plan_id", "slug"), {"plan_id": "plans"}),
    ("design_notes", ("plan_id", "slug"), {"plan_id": "plans"}),
    ("tasks", ("plan_id", "slug"), {"plan_id": "plans"}),
    ("task_dependencies", ("task_id", "depends_on_task_id"), {"task_id": "tasks", "depends_on_task_id": "tasks"}),
    ("task_claims", ("task_id",), {"task_id": "tasks"}),
    ("plan_history", None, {"plan_id": "plans"}),
    ("task_context_capsules", ("task_id", "memory_table", "memory_id"), {"task_id": "tasks", "memory_id": ("memory_table",)}),
    ("task_lock_history", None, {"task_id": "tasks"}),
    ("memory_tags", ("memory_table", "memory_id", "tag_id"), {"memory_id": ("memory_table",), "tag_id": "tags"}),
    ("memory_links", ("from_table", "from_id", "to_table", "to_id", "link_type"),
     {"from_id": ("from_table",), "to_id": ("to_table",)}),
    ("skills_registry", ("name",), {}),
    ("routing_decisions", None, {}),
    ("receipts", ("id",), {}),
    ("attempts", ("token",), {}),
    ("agent_workflows", ("id",), {}),
]

INSERT_RE = re.compile(r'^INSERT INTO "([^"]+)" \((.*?)\) VALUES \((.*)\);$', re.S)

# Los valores los evalúa SQLite (comillas, NULL, números, 'a'||char(10)||'b'),
# no un tokenizador propio: el anterior leía línea por línea y descartaba en
# silencio toda fila con saltos de línea (conceptos, decisiones, planes).
# El dump viene de git (otra máquina): solo se permite SELECT de literales.
literal_db = sqlite3.connect(":memory:")
literal_db.text_factory = str
ALLOWED = {sqlite3.SQLITE_SELECT, sqlite3.SQLITE_FUNCTION}
literal_db.set_authorizer(lambda action, *_: sqlite3.SQLITE_OK if action in ALLOWED else sqlite3.SQLITE_DENY)


def statements(path):
    # Acumula hasta una sentencia completa: acepta dumps nuevos (una línea por
    # fila) y los viejos con strings multilínea.
    buf = ""
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not buf and (line.startswith("--") or not line.strip()):
                continue
            buf += line
            if sqlite3.complete_statement(buf):
                yield buf.strip()
                buf = ""


remote = {}
unparsed = 0
for stmt in statements(dump_path):
    m = INSERT_RE.match(stmt)
    if not m:
        unparsed += 1
        continue
    table, col_part, val_part = m.group(1), m.group(2), m.group(3)
    cols = [c.strip().strip('"') for c in col_part.split(",")]
    try:
        vals = literal_db.execute("SELECT " + val_part).fetchone()
    except sqlite3.Error:
        unparsed += 1
        continue
    if len(cols) != len(vals):
        unparsed += 1
        continue
    remote.setdefault(table, []).append(dict(zip(cols, vals)))

con = sqlite3.connect(db_path)
con.text_factory = str
con.execute("PRAGMA busy_timeout=5000")

# idmap[tabla][id remoto] = [ids locales candidatos]. Normalmente uno; más de
# uno solo si un merge=union dejó en el dump dos entidades distintas con el
# mismo id remoto (una por rama).
idmap = {}
stats = {"inserted": 0, "updated": 0, "local_newer": 0, "unchanged": 0, "remapped": 0}
errors = []


def local_columns(table):
    return [r[1] for r in con.execute(f"PRAGMA table_info('{table}')").fetchall()]


def surrogate_id(table, cols):
    # id entero autoincremental (no los ids de texto de receipts/agent_workflows).
    info = {r[1]: (r[2] or "").upper() for r in con.execute(f"PRAGMA table_info('{table}')")}
    return "id" in cols and info.get("id") == "INTEGER"


def find_local(table, key, row):
    where = " AND ".join(f'"{c}" IS ?' for c in key)
    return con.execute(f'SELECT * FROM "{table}" WHERE {where}', [row.get(c) for c in key]).fetchone()


def candidates(parent, rid):
    if rid is None:
        return [None]
    mapped = idmap.get(parent, {}).get(str(rid))
    if mapped:
        return mapped
    # El padre no vino en este dump: si existe localmente con ese id, es el
    # mismo registro (dump parcial o ya fusionado antes).
    return [rid]


def translations(row, fks):
    # Todas las combinaciones de FKs traducidas (casi siempre una sola).
    options = [dict(row)]
    for col, parent in fks.items():
        if col not in row:
            continue
        parent_table = row.get(parent[0]) if isinstance(parent, tuple) else parent
        expanded = []
        for option in options:
            for local_id in candidates(parent_table, row[col]):
                new = dict(option)
                new[col] = local_id
                expanded.append(new)
        options = expanded
    return options


for table, key, fks in SPECS:
    rows = remote.get(table)
    if not rows:
        continue
    cols = local_columns(table)
    if not cols:
        continue
    has_updated_at = "updated_at" in cols
    surrogate = surrogate_id(table, cols)
    match_cols = key or tuple(c for c in cols if c != "id")
    # Si una rama duplicó la misma entidad (merge=union), gana la más reciente.
    rows = sorted(rows, key=lambda r: (str(r.get("updated_at") or ""), str(r.get("id") or "")))
    deferred_parent = []
    for row in rows:
        options = translations(row, fks)
        chosen = next((o for o in options if find_local(table, match_cols, o)), options[-1])
        local = find_local(table, match_cols, chosen)
        values = {c: chosen.get(c) for c in cols if c in chosen}
        if local is not None:
            local_row = dict(zip(cols, local))
            if surrogate:
                idmap.setdefault(table, {}).setdefault(str(row.get("id")), [])
                if local_row["id"] not in idmap[table][str(row.get("id"))]:
                    idmap[table][str(row.get("id"))].append(local_row["id"])
                if local_row["id"] != row.get("id"):
                    stats["remapped"] += 1
            if not has_updated_at or not row.get("updated_at"):
                stats["unchanged"] += 1
                continue
            remote_ts, local_ts = str(row.get("updated_at")), str(local_row.get("updated_at") or "")
            if remote_ts <= local_ts:
                stats["unchanged" if remote_ts == local_ts else "local_newer"] += 1
                continue
            changes = {c: v for c, v in values.items() if c != "id"}
            if not dry_run:
                sets = ",".join(f'"{c}"=?' for c in changes)
                where = " AND ".join(f'"{c}" IS ?' for c in match_cols)
                try:
                    con.execute(f'UPDATE "{table}" SET {sets} WHERE {where}',
                                list(changes.values()) + [local_row[c] for c in match_cols])
                except sqlite3.Error as exc:
                    errors.append(f"{table} {[chosen.get(c) for c in match_cols]}: {exc}")
                    continue
            stats["updated"] += 1
            continue
        # Fila nueva: conserva el id remoto si está libre; si no, SQLite asigna uno.
        insert = dict(values)
        if surrogate:
            taken = con.execute(f'SELECT 1 FROM "{table}" WHERE id=?', (row.get("id"),)).fetchone()
            if taken:
                insert.pop("id", None)
                stats["remapped"] += 1
        if dry_run:
            stats["inserted"] += 1
            continue
        names = ",".join(f'"{c}"' for c in insert)
        try:
            cursor = con.execute(f'INSERT INTO "{table}" ({names}) VALUES ({",".join("?" for _ in insert)})',
                                 list(insert.values()))
        except sqlite3.Error as exc:
            errors.append(f"{table} {[chosen.get(c) for c in match_cols]}: {exc}")
            continue
        stats["inserted"] += 1
        if surrogate:
            new_id = insert.get("id", cursor.lastrowid)
            idmap.setdefault(table, {}).setdefault(str(row.get("id")), []).append(new_id)
            if table == "work_in_progress" and row.get("parent_id") is not None:
                deferred_parent.append((new_id, row.get("parent_id")))
    # Autorreferencia: el padre pudo llegar después que el hijo.
    for child_id, remote_parent in deferred_parent:
        parents = candidates("work_in_progress", remote_parent)
        if len(parents) == 1 and not dry_run:
            con.execute('UPDATE work_in_progress SET parent_id=? WHERE id=?', (parents[0], child_id))

con.commit()
print(f"merge: {stats['inserted']} insertadas, {stats['updated']} actualizadas, "
      f"{stats['local_newer']} locales más nuevas, {stats['unchanged']} sin cambios, "
      f"{stats['remapped']} ids traducidos")
for e in errors:
    print(f"ERROR fila no aplicada: {e}", file=sys.stderr)
if unparsed:
    print(f"ERROR: {unparsed} sentencias del dump no se pudieron leer", file=sys.stderr)
if errors or unparsed:
    sys.exit(2)
PY
)"

if [ "$DRY_RUN" = true ]; then
  python3 -c "$MERGE_PY" "$DB" "$DUMP" 1
else
  python3 -c "$MERGE_PY" "$DB" "$DUMP" 0
  # FASE 1: dump fresco post-escritura (la DB es la fuente, el dump la fotografía)
  teamdb_refresh_dump "$PROJECT" >/dev/null 2>&1 || true
fi
