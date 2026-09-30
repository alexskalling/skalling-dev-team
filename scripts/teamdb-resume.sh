#!/usr/bin/env bash
# teamdb-resume.sh — cápsula breve para retomar trabajo sin cargar toda la memoria.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Ruta de TeamDB: la del repositorio principal, también desde un worktree.
# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then . "$SCRIPT_DIR/lib-teamdb.sh"; else . "$SCRIPT_DIR/lib/lib-teamdb.sh"; fi

PROJECT="${1:-$(pwd)}"
DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "ERROR: DB no existe: $DB" >&2; exit 1; }

python3 - "$DB" "${2:-}" <<'PY'
import sqlite3
import json
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
conn.row_factory = sqlite3.Row

# Current workflows carry the user's objective; the legacy singleton does not.
if conn.execute("SELECT 1 FROM sqlite_master WHERE name='agent_workflows'").fetchone():
    requested = sys.argv[2]
    if requested:
        rows = conn.execute('SELECT id,body FROM agent_workflows WHERE id=?', (requested,)).fetchall()
        if not rows:
            raise SystemExit('Workflow desconocido: ' + requested)
    else:
        rows = conn.execute("SELECT id,body FROM agent_workflows WHERE json_extract(body,'$.state') "
                            "NOT IN ('completed','superseded','abandoned') ORDER BY id LIMIT 6").fetchall()
    if rows:
        print('━━━ Workflows de Skalling (objetivo persistido)')
        for row in rows[:5]:
            workflow = json.loads(row['body'])
            print(f"- {row['id']} [{workflow['state']}]: {workflow.get('intent') or workflow.get('acceptance', '')}")
            for outcome in workflow.get('outcomes', []):
                print(f"  Resultado {outcome['id']}: {outcome['expected']}")
        if len(rows) > 5:
            print('Hay más workflows: consultar por id.')
        if len(rows) == 1:
            print('Siguiente: skalling_workflow status con id=' + rows[0]['id'] + '; entrega contexto y siguiente acción.')
        else:
            print('Siguiente: asociar el pedido actual a su id y consultar status; no elegir por recencia.')
        raise SystemExit(0)

state = conn.execute(
    "SELECT active_cycle_slug, phase, actor, updated_at FROM workflow_state WHERE id=1"
).fetchone()
cycle = state["active_cycle_slug"] if state else None

if not cycle:
    row = conn.execute(
        "SELECT slug FROM plans WHERE status NOT IN ('completed','abandoned') "
        "ORDER BY updated_at DESC, id DESC LIMIT 1"
    ).fetchone()
    cycle = row["slug"] if row else None

if not cycle:
    print("Resume: no hay trabajo activo.")
    print("Siguiente: describe el objetivo o crea un plan.")
    raise SystemExit(0)

plan = conn.execute(
    "SELECT id, slug, title, status FROM plans WHERE slug=? LIMIT 1", (cycle,)
).fetchone()
print("━━━ Resume de Skalling")
print(f"Ciclo: {cycle}")
if state:
    print(f"Fase: {state['phase'] or '-'}  Actor: {state['actor'] or '-'}")

if not plan:
    print("Plan: no encontrado en la tabla plans")
    print("Siguiente: ejecutar /skalling-status y revisar la memoria del ciclo.")
    raise SystemExit(0)

print(f"Objetivo: {plan['title']} [{plan['status']}]")
tasks = conn.execute(
    "SELECT slug, title, status, owner, blocked_reason FROM tasks "
    "WHERE plan_id=? AND status NOT IN ('approved','resolved','rejected') "
    "ORDER BY CASE status WHEN 'blocked' THEN 0 WHEN 'in_progress' THEN 1 "
    "WHEN 'in_review' THEN 2 ELSE 3 END, order_index LIMIT 5",
    (plan["id"],),
).fetchall()

if not tasks:
    print("Trabajo: sin tareas activas")
    print("Siguiente: cerrar el plan o definir la próxima tarea.")
    raise SystemExit(0)

print("Trabajo activo:")
for task in tasks:
    owner = task["owner"] or "sin owner"
    print(f"- {task['slug']} [{task['status']}, {owner}] — {task['title']}")
    if task["blocked_reason"]:
        print(f"  Bloqueo: {task['blocked_reason']}")

next_task = next((t for t in tasks if t["status"] != "blocked"), tasks[0])
if next_task["status"] == "blocked":
    print(f"Siguiente: resolver el bloqueo de {next_task['slug']}.")
else:
    print(f"Siguiente: continuar {next_task['slug']}.")
PY
