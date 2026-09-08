#!/usr/bin/env bash
# Completa y aprueba un plan existente después de validar alcance y aceptación.
set -euo pipefail
PROJECT="${1:?Falta proyecto}"; PLAN_ID="${2:?Falta plan_id}"
DESIGN="${3:?Falta diseño concreto}"; ACCEPTANCE="${4:?Falta aceptación}"
APPROVAL="${5:?Falta referencia a la aprobación/alcance del usuario}"
DB="$PROJECT/.opencode/context/team.db"
[[ -f "$DB" ]] || { echo 'TeamDB no existe' >&2; exit 1; }
python3 - "$DB" "$PLAN_ID" "$DESIGN" "$ACCEPTANCE" "$APPROVAL" <<'PY'
import sqlite3, sys
db, plan_id, design, acceptance, approval = sys.argv[1:]
if any(len(value.strip()) < 10 for value in (design, acceptance, approval)):
    raise SystemExit('Se requiere diseño, aceptación y referencia de aprobación concretos')
conn = sqlite3.connect(db, timeout=10)
try:
    conn.execute('BEGIN IMMEDIATE')
    plan = conn.execute('SELECT status FROM plans WHERE id=?', (plan_id,)).fetchone()
    if not plan or plan[0] != 'draft':
        raise ValueError('Solo se aprueba un plan draft; no se reemplaza un plan activo')
    tasks = conn.execute('SELECT purpose,acceptance_md FROM tasks WHERE plan_id=?', (plan_id,)).fetchall()
    if not tasks or any(not (purpose or '').strip() or not (criteria or '').strip() for purpose, criteria in tasks):
        raise ValueError('Cada tarea debe tener propósito y aceptación')
    conn.execute("UPDATE plans SET design_md=?,acceptance_md=?,status='approved',updated_by='sol',updated_at=datetime('now') WHERE id=?",
                 (design, acceptance + '\n\nReferencia de alcance/aprobación: ' + approval, plan_id))
    conn.commit()
    print('plan approved: ' + plan_id)
except Exception:
    conn.rollback()
    raise
finally:
    conn.close()
PY
