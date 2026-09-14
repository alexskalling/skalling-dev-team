"""Keeps workflow_state (the singleton row dashboard/resume/merge-helper read)
in sync with the tasks/plans tables that actually change. Nothing wrote to
this table from 2026-08-17 (its creation) until now: every consumer had a
fallback to plans/tasks, so it never broke loudly, it just always showed
"sin actor actual" / no phase. Call sync_workflow_state() right after any
UPDATE tasks/task_claims in the same transaction that changes what should
be reflected as "current work".
"""

PHASE_BY_STATUS = {
    'pending': 'plan', 'in_progress': 'build', 'in_review': 'review',
    'approved': 'verificación', 'resolved': 'entrega',
    'blocked': 'build', 'rejected': 'build',
}


def sync_workflow_state(conn, plan_id, actor=None):
    """Derive phase/actor from the most relevant task of `plan_id` -- the
    same query dashboard-server.py and teamdb-resume.sh already fall back to
    -- and upsert the singleton row. `actor` overrides the task owner when
    the caller (e.g. Jhon advancing a review) is not the task's owner."""
    plan = conn.execute("SELECT slug FROM plans WHERE id=?", (plan_id,)).fetchone()
    if not plan:
        return
    task = conn.execute("""
        SELECT status, owner FROM tasks WHERE plan_id=?
        ORDER BY CASE status
            WHEN 'in_progress' THEN 0 WHEN 'in_review' THEN 1 WHEN 'approved' THEN 2
            WHEN 'pending' THEN 3 WHEN 'blocked' THEN 4 ELSE 5 END,
        updated_at DESC LIMIT 1
    """, (plan_id,)).fetchone()
    phase = PHASE_BY_STATUS.get(task['status'] if task else None, 'plan')
    resolved_actor = actor or (task['owner'] if task else None)
    conn.execute("""
        INSERT INTO workflow_state (id, active_cycle_slug, phase, actor, started_at, updated_at)
        VALUES (1, ?, ?, ?, COALESCE((SELECT started_at FROM workflow_state WHERE id=1), datetime('now')), datetime('now'))
        ON CONFLICT(id) DO UPDATE SET active_cycle_slug=excluded.active_cycle_slug,
            phase=excluded.phase, actor=excluded.actor, updated_at=excluded.updated_at
    """, (plan['slug'], phase, resolved_actor))
