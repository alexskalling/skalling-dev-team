"""Explicit per-request limits on verification work, not a model-token quota."""
import time


def validate_budget(value):
    if not isinstance(value, dict) or not value or set(value) - {'max_checks', 'max_elapsed_seconds'}:
        raise ValueError('resource_budget requiere max_checks y/o max_elapsed_seconds')
    for key, limit in value.items():
        if type(limit) is not int or limit <= 0:
            raise ValueError(f'{key} debe ser un entero positivo explícito')
    return dict(value)


def budget_status(db, state):
    limits = state.get('resource_budget')
    if not limits:
        return None
    # Include ancestors: reclassification must not renew the same request's budget.
    count = db.execute("""WITH RECURSIVE family(id) AS (
        SELECT ? UNION SELECT json_extract(w.body,'$.supersedes') FROM agent_workflows w
        JOIN family f ON w.id=f.id WHERE json_extract(w.body,'$.supersedes') IS NOT NULL)
        SELECT count(*) FROM agent_workflow_events WHERE request_id IN (SELECT id FROM family)
        AND action IN ('check-started','probe-started','auto-verify-started')""", (state['id'],)).fetchone()[0]
    elapsed = max(0, (state.get('completed_at') or time.time()) - state.get('budget_started_at', state['started_at']))
    exhausted = []
    if 'max_checks' in limits and count >= limits['max_checks']:
        exhausted.append('max_checks')
    if 'max_elapsed_seconds' in limits and elapsed >= limits['max_elapsed_seconds']:
        exhausted.append('max_elapsed_seconds')
    return {'limits': limits, 'checks_started': count, 'elapsed_seconds': round(elapsed, 3),
            'exhausted': exhausted, 'scope': 'new verification processes; completion and recorded evidence remain available'}


def require_budget(db, state):
    status = budget_status(db, state)
    if status and status['exhausted']:
        raise ValueError('Presupuesto explícito agotado: ' + ', '.join(status['exhausted']) +
                         '; no iniciar otra prueba. Usar evidencia vigente o registrar una revisión explícita del usuario')
