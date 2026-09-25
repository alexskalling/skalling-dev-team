#!/usr/bin/env bash
# teamdb-task-groups.sh — agrupa las tasks pendientes de un plan en lotes
# seguros para trabajar en paralelo, usando SOLO evidencia real de
# task_dependencies. Nunca infiere independencia por "no debería tocar los
# mismos archivos" -- esa señal no existe en el schema, así que no se inventa.
#
# Uso: teamdb-task-groups.sh <project> <plan-slug>
#
# Regla (deliberadamente conservadora, a pedido explícito): CUALQUIER fila en
# task_dependencies que conecte dos tasks -- sea type 'blocks', 'relates_to'
# o 'supersedes' -- las fuerza a la MISMA secuencia. No solo 'blocks'. Un
# 'relates_to' es un atisbo de relación igual, y ante la duda van en serie.
#
# Salida (JSON):
#   not_ready: tasks pendientes bloqueadas por una dependencia sin resolver
#              todavía -- no pueden ni empezar, ni en paralelo ni en serie.
#   parallel_groups: listas de tasks. Cada lista interna es una cadena que
#              debe correr en secuencia (tiene algún vínculo). Listas
#              DISTINTAS no tienen ningún vínculo entre sí -- esas sí se
#              pueden trabajar en paralelo (un worktree por lista).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}"
PROJECT="${1:?Uso: teamdb-task-groups.sh <project> <plan-slug>}"
PLAN_SLUG="${2:?Uso: teamdb-task-groups.sh <project> <plan-slug>}"
DB="$PROJECT/.opencode/context/team.db"

[ -f "$DB" ] || { echo "ERROR: TeamDB no existe: $DB" >&2; exit 1; }

python3 - "$DB" "$PLAN_SLUG" <<'PY'
import json, sys
from teamdb_guard import connect as protected_connect

db_path, plan_slug = sys.argv[1:]
TERMINAL = ("approved", "resolved")

with protected_connect("file:" + db_path + "?mode=ro", uri=True) as db:
    db.row_factory = None
    plan = db.execute("SELECT id FROM plans WHERE slug=?", (plan_slug,)).fetchone()
    if not plan:
        print(json.dumps({"error": f"plan no encontrado: {plan_slug}"}))
        sys.exit(1)
    plan_id = plan[0]

    tasks = db.execute(
        "SELECT id, slug, status FROM tasks WHERE plan_id=? ORDER BY priority, order_index, id",
        (plan_id,),
    ).fetchall()
    by_id = {row[0]: {"id": row[0], "slug": row[1], "status": row[2]} for row in tasks}
    pending_ids = {tid for tid, t in by_id.items() if t["status"] == "pending"}

    edges = db.execute(
        "SELECT task_id, depends_on_task_id, type FROM task_dependencies"
    ).fetchall()

# Paso 1: una task pendiente que "blocks" (prerequisito real, no relates_to
# ni supersedes) sobre otra task que todavia no llego a un estado terminal
# no esta lista para arrancar -- ni sola ni en grupo. Se excluye de todo lo
# demas. relates_to/supersedes no impiden arrancar; solo fuerzan secuencia
# en el Paso 2, una vez que ambas tasks ya estan listas.
not_ready = {}
for task_id, dep_id, dep_type in edges:
    if dep_type != "blocks":
        continue
    if task_id in pending_ids:
        dep = by_id.get(dep_id)
        if dep and dep["status"] not in TERMINAL:
            not_ready[task_id] = {
                "slug": by_id[task_id]["slug"],
                "blocked_by": dep["slug"],
                "type": dep_type,
            }

ready_ids = pending_ids - set(not_ready.keys())

# Paso 2: entre las tasks YA listas para arrancar, cualquier vinculo
# registrado (en cualquier direccion, cualquier type) las une a la MISMA
# cadena secuencial -- deliberadamente conservador, a pedido explicito.
parent = {tid: tid for tid in ready_ids}

def find(node):
    while parent[node] != node:
        parent[node] = parent[parent[node]]
        node = parent[node]
    return node

def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb:
        parent[ra] = rb

for task_id, dep_id, _dep_type in edges:
    if task_id in ready_ids and dep_id in ready_ids:
        union(task_id, dep_id)

groups_by_root = {}
for tid in ready_ids:
    groups_by_root.setdefault(find(tid), []).append(tid)

# Orden estable: por id de task minimo en cada grupo, y dentro del grupo por
# id (que ya refleja priority/order_index via el SELECT de arriba).
parallel_groups = []
for root in sorted(groups_by_root, key=lambda r: min(groups_by_root[r])):
    ids = sorted(groups_by_root[root])
    parallel_groups.append([by_id[i]["slug"] for i in ids])

result = {
    "plan": plan_slug,
    "not_ready": sorted(not_ready.values(), key=lambda x: x["slug"]),
    "parallel_groups": parallel_groups,
    "note": (
        "parallel_groups distintos no tienen NINGUN vinculo registrado entre "
        "si -- son candidatos seguros para un worktree cada uno. Esto solo "
        "mira task_dependencies; no detecta si dos tasks tocarian el mismo "
        "archivo sin que eso este declarado como dependencia."
    ),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
PY
