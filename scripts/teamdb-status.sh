#!/usr/bin/env bash
# teamdb-status.sh — Tablero de estado del ciclo de tasks (v0.9.0 Fase 2)
# Vista de lectura del circuito: pending → in_progress → in_review → approved
# → resolved (+ rejected/blocked). Muestra por plan: tasks activas con status,
# owner, due_date y marca de OVERDUE (due_date < hoy y status no terminal).
# Solo lectura: NO regenera el dump (mismo criterio que teamdb-execute-plan.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
if [ -f "$SCRIPT_DIR/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib-teamdb.sh"
elif [ -f "$SCRIPT_DIR/lib/lib-teamdb.sh" ]; then
  source "$SCRIPT_DIR/lib/lib-teamdb.sh"
else
  echo "ERROR: lib-teamdb.sh no encontrado" >&2
  exit 1
fi

PLAN_FILTER="${1:-}"
PROJECT="${2:-${PROJECT:-$(pwd)}}"
[ -d "$PROJECT" ] || PROJECT="$(pwd)"

DB="$(teamdb_project_path "$PROJECT")"
[ -f "$DB" ] || { echo "ERROR: DB no existe: $DB (corré bash scripts/teamdb-init.sh $PROJECT)" >&2; exit 1; }

python3 - "$DB" "$PLAN_FILTER" <<'PYEOF'
import datetime
import sqlite3
import sys

db, plan_filter = sys.argv[1], sys.argv[2] or None
TERMINAL = ('approved', 'resolved', 'rejected', 'blocked')
today = datetime.date.today().isoformat()

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row

plan_sql = "SELECT id, slug, title, status FROM plans WHERE 1=1"
params = []
if plan_filter:
    plan_sql += " AND slug = ?"
    params.append(plan_filter)

plans = conn.execute(plan_sql + " ORDER BY id", params).fetchall()
if not plans:
    print(f"status: no plans{' matching ' + plan_filter if plan_filter else ''}")
    sys.exit(0)

# Single query: JOIN plans + tasks to eliminate N+1
plan_ids = [p['id'] for p in plans]
all_tasks = conn.execute(f"""
    SELECT t.plan_id, t.slug, t.title, t.status, t.owner, t.due_date, t.order_index
    FROM tasks t
    WHERE t.plan_id IN ({','.join('?' * len(plan_ids))})
    ORDER BY t.plan_id,
        CASE WHEN t.due_date IS NULL THEN 1 ELSE 0 END,
        t.due_date,
        t.order_index
""", plan_ids).fetchall()

# Index tasks by plan_id
tasks_by_plan = {}
for t in all_tasks:
    tasks_by_plan.setdefault(t['plan_id'], []).append(t)

total_by_status = {}

for plan in plans:
    tasks = tasks_by_plan.get(plan['id'], [])
    if not tasks:
        continue

    print(f"━━━ {plan['slug']} — {plan['title']} [{plan['status']}]")

    counts = {}
    active = []
    for t in tasks:
        counts[t['status']] = counts.get(t['status'], 0) + 1
        total_by_status[t['status']] = total_by_status.get(t['status'], 0) + 1
        if t['status'] not in TERMINAL:
            active.append(t)

    if not active:
        print("  (sin tasks activas)")
    for t in active:
        overdue = ""
        if t['due_date'] and t['due_date'] < today:
            overdue = " [OVERDUE]"
        due = t['due_date'] or "-"
        owner = t['owner'] or "-"
        print(f"  {t['status']:<12} {owner:<8} due {due:<12} {t['slug']}{overdue}")

    summary = "  " + "  ".join(f"{s}:{c}" for s, c in sorted(counts.items()))
    print(summary)
    print()

if not plan_filter:
    print("Resumen global:", "  ".join(f"{s}:{c}" for s, c in sorted(total_by_status.items())))
PYEOF
exit 0
