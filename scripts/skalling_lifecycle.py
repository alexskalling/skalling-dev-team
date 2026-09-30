"""Transactional links between workflow outcomes and project work records.

Callers own the transaction. A plan id is never evidence that all its tasks ran.
"""
import json
import time

TERMINAL = {'completed', 'superseded', 'cancelled', 'failed', 'abandoned'}
TASK_DONE = {'approved', 'resolved'}


def expire_claims(db, now=None):
    now = int(time.time() if now is None else now)
    return db.execute("UPDATE task_claims SET status='expired', released_at=? "
                      "WHERE status='active' AND CAST(lease_until AS INTEGER)<=?", (now, now)).rowcount


def bind_tasks(db, state, task_ids=None):
    plan_id = state.get('plan_id')
    if state.get('task'):
        plan, task = state['task'].split('/', 1)
        row = db.execute('SELECT t.id,t.plan_id FROM tasks t JOIN plans p ON p.id=t.plan_id '
                         'WHERE p.slug=? AND t.slug=?', (plan, task)).fetchone()
        if not row or (plan_id is not None and row[1] != plan_id):
            raise ValueError('task must exist and belong to the approved plan')
        if task_ids is not None and task_ids != [row[0]]:
            raise ValueError('task_ids contradicts the named task')
        task_ids, plan_id = [row[0]], row[1]
        state['plan_id'] = plan_id
    if plan_id is None:
        if task_ids:
            raise ValueError('task_ids requires an approved plan')
        return
    tasks = db.execute('SELECT id,title,acceptance_md,status FROM tasks WHERE plan_id=?', (plan_id,)).fetchall()
    if tasks and (not isinstance(task_ids, list) or not task_ids):
        raise ValueError('ready requires explicit task_ids for the work covered by this workflow')
    task_ids = task_ids or []
    if any(type(i) is not int for i in task_ids) or len(set(task_ids)) != len(task_ids):
        raise ValueError('task_ids must contain unique integer task ids')
    selected = {row[0]: row for row in tasks if row[0] in task_ids}
    if len(selected) != len(task_ids):
        raise ValueError('Every task_id must belong to the approved plan')
    if any(row[3] in TASK_DONE for row in selected.values()):
        raise ValueError('Completed tasks require a new task for new work')
    # Prevent two live workflows from claiming the same work unit.
    for key, body in db.execute('SELECT id,body FROM agent_workflows WHERE id!=?', (state['id'],)):
        other = json.loads(body)
        if other.get('state') not in TERMINAL and set(task_ids).intersection(other.get('task_ids', [])):
            raise ValueError(f'task already assigned to workflow {key}')
    state['task_ids'] = task_ids
    for identifier, title, acceptance, _ in selected.values():
        outcome = 'task-' + str(identifier)
        if not any(o['id'] == outcome for o in state['outcomes']):
            state['outcomes'].append({'id': outcome, 'expected': acceptance or title})
        db.execute("UPDATE tasks SET status='in_progress',started_at=COALESCE(started_at,datetime('now')), "
                   "updated_at=datetime('now'),owner='teo' WHERE id=?", (identifier,))
    if task_ids:
        db.execute("UPDATE plans SET status='in_progress',updated_at=datetime('now'),updated_by='workflow' "
                   "WHERE id=? AND status='approved'", (plan_id,))


def finish(db, state, now=None):
    """Only a verified terminal transition may resolve bound work."""
    now = time.time() if now is None else now
    terminal = state['state']
    if terminal not in TERMINAL:
        return
    success = terminal == 'completed'
    routing_id = state.get('routing_id')
    if routing_id is not None:
        db.execute("UPDATE routing_decisions SET outcome=?,completed_at=datetime(?,'unixepoch') WHERE id=?",
                   ('SUCCESS' if success else 'FAIL', now, routing_id))
    db.execute("UPDATE workflow_metrics SET outcome=?,completed_at=COALESCE(completed_at,datetime(?,'unixepoch')) "
               "WHERE request_id=?", ('success' if success else terminal, now, state['id']))
    ids = state.get('task_ids', [])
    for task_id in ids:
        if success:
            # Task acceptance becomes an outcome at binding time. Legacy rows
            # lacking that link must be reviewed, never mass-approved.
            if not any(c['outcome_id'] == f'task-{task_id}' for c in (state.get('coverage') or [])):
                raise ValueError(f'Missing verified outcome for task {task_id}')
            db.execute("UPDATE tasks SET status='resolved',resolved_at=datetime(?,'unixepoch'),"
                       "updated_at=datetime(?,'unixepoch'),resolution_md=? WHERE id=? AND plan_id=?",
                       (now, now, 'Verified workflow: ' + state['id'], task_id, state['plan_id']))
        else:
            db.execute("UPDATE tasks SET status='pending',owner=NULL,updated_at=datetime(?,'unixepoch') "
                       "WHERE id=? AND status IN ('in_progress','in_review')", (now, task_id))
        db.execute("UPDATE task_claims SET status=?,released_at=? WHERE task_id=? AND status='active'",
                   ('done' if success else 'failed', int(now), task_id))
    if state.get('plan_id'):
        finish_plan(db, state['plan_id'])
    expire_claims(db, now)


def finish_plan(db, plan_id):
    states = [r[0] for r in db.execute('SELECT status FROM tasks WHERE plan_id=?', (plan_id,))]
    if states and all(s in TASK_DONE for s in states):
        db.execute("UPDATE plans SET status='completed',completed_at=COALESCE(completed_at,datetime('now')),"
                   "updated_at=datetime('now'),updated_by='workflow' WHERE id=? AND status IN ('approved','in_progress')", (plan_id,))


def approve_proposal(db, plan_id, actor='sol'):
    # Approval helper has already checked explicit scope approval. Preserve a
    # rejected proposal: that contradiction requires a new user decision.
    row = db.execute('SELECT pr.id,pr.status FROM plans p JOIN proposals pr ON pr.id=p.proposal_id WHERE p.id=?', (plan_id,)).fetchone()
    if row and row[1] == 'rejected':
        raise ValueError('Plan refers to a rejected proposal; resolve scope approval first')
    if row and row[1] == 'draft':
        db.execute("UPDATE proposals SET status='approved',decided_by=?,decided_at=datetime('now'),updated_at=datetime('now') WHERE id=?", (actor, row[0]))


def progress(db, state):
    status = {'implementation_ready': 'in_progress', 'verification_ready': 'in_review',
              'verified': 'in_review', 'quality_reviewed': 'in_review', 'blocked': 'blocked'}.get(state['state'])
    if status:
        for task_id in state.get('task_ids', []):
            db.execute("UPDATE tasks SET status=?,updated_at=datetime('now') WHERE id=? AND status NOT IN ('approved','resolved')",
                       (status, task_id))
