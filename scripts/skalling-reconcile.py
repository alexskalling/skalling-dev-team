#!/usr/bin/env python3
"""Audit lifecycle consistency; --apply repairs only evidence-backed relations.

Never infer successful work from a release, a receipt count, or elapsed time.
"""
import argparse
from contextlib import closing
import datetime
import json
from pathlib import Path
import sqlite3
import time

from skalling_lifecycle import TERMINAL, TASK_DONE, expire_claims, finish_plan, approve_proposal
from teamdb_guard import connect


def inspect(db):
    now = time.time()
    workflows = [json.loads(r[0]) for r in db.execute('SELECT body FROM agent_workflows')]
    routes = list(db.execute("SELECT id,user_intent,CAST(strftime('%s',ts) AS INTEGER),outcome,chosen_route,route_reason FROM routing_decisions"))
    changes, unresolved = [], []
    linked = {s.get('routing_id') for s in workflows}
    for state in workflows:
        key = state['id']
        if not state.get('routing_id'):
            matches = [r[0] for r in routes if r[2] is not None
                       and abs(r[2] - state.get('started_at', 0)) < 1 and r[0] not in linked
                       and (r[1] == (state.get('intent') or key) or
                            (not state.get('intent') and r[4] == state.get('route') and r[5] == 'skalling_workflow start'))]
            if len(matches) == 1:
                changes.append({'kind': 'link_route', 'workflow': key, 'route': matches[0]})
                state['routing_id'] = matches[0]
                linked.add(matches[0])
            else:
                unresolved.append({'kind': 'unlinked_workflow', 'workflow': key})
        if state.get('routing_id') and state['state'] in TERMINAL:
            expected = 'SUCCESS' if state['state'] == 'completed' else 'FAIL'
            if any(r[0] == state['routing_id'] and r[3] != expected for r in routes):
                changes.append({'kind': 'finish_route', 'workflow': key, 'route': state['routing_id'], 'outcome': expected})
        if state['state'] in TERMINAL:
            expected = 'success' if state['state'] == 'completed' else state['state']
            row = db.execute('SELECT outcome FROM workflow_metrics WHERE request_id=?', (key,)).fetchone()
            if row and row[0] != expected:
                changes.append({'kind': 'finish_metrics', 'workflow': key, 'outcome': expected})
        if state.get('plan_id') and state['state'] == 'completed':
            pending = [r[0] for r in db.execute("SELECT id FROM tasks WHERE plan_id=? AND status NOT IN ('approved','resolved')", (state['plan_id'],))]
            if pending:
                unresolved.append({'kind': 'completed_workflow_pending_tasks', 'workflow': key, 'task_ids': pending,
                                   'reason': 'Revisar evidencia por tarea; complete legacy no demuestra todo el plan'})
        if state['state'] not in TERMINAL and now - state.get('updated_at', state.get('started_at', now)) > 86400:
            unresolved.append({'kind': 'stale_workflow', 'workflow': key, 'state': state['state'],
                               'reason': 'Actividad desconocida; retomar por id o cancelar con evidencia, nunca aprobar por antigüedad'})
    for route, _, _, outcome, _, _ in routes:
        if route not in linked and outcome == 'PENDING':
            unresolved.append({'kind': 'unlinked_route', 'route': route, 'reason': 'Sin evidencia de resultado'})
    expired = db.execute("SELECT count(*) FROM task_claims WHERE status='active' AND CAST(lease_until AS INTEGER)<=?", (int(now),)).fetchone()[0]
    if expired:
        changes.append({'kind': 'expire_claims', 'count': expired})
    for identifier, proposal, status in db.execute("SELECT id,proposal_id,status FROM plans WHERE status IN ('approved','in_progress','completed')"):
        if proposal:
            row = db.execute('SELECT status FROM proposals WHERE id=?', (proposal,)).fetchone()
            if row and row[0] == 'draft':
                changes.append({'kind': 'approve_proposal', 'plan': identifier})
            elif row and row[0] == 'rejected':
                unresolved.append({'kind': 'rejected_proposal_in_active_plan', 'plan': identifier})
        statuses = [r[0] for r in db.execute('SELECT status FROM tasks WHERE plan_id=?', (identifier,))]
        if status != 'completed' and statuses and all(s in TASK_DONE for s in statuses):
            changes.append({'kind': 'finish_plan', 'plan': identifier})
    return {'repairs': changes, 'needs_review': unresolved, 'ready': not changes and not unresolved}


def repair(db, report):
    for change in report['repairs']:
        kind = change['kind']
        if kind == 'expire_claims':
            expire_claims(db)
        elif kind == 'approve_proposal':
            approve_proposal(db, change['plan'], 'reconcile: approved plan')
        elif kind == 'finish_plan':
            finish_plan(db, change['plan'])
        else:
            state = json.loads(db.execute('SELECT body FROM agent_workflows WHERE id=?', (change['workflow'],)).fetchone()[0])
            if kind == 'link_route':
                state['routing_id'] = change['route']
                db.execute('UPDATE agent_workflows SET body=? WHERE id=?', (json.dumps(state), state['id']))
            elif kind == 'finish_route':
                db.execute("UPDATE routing_decisions SET outcome=?,completed_at=datetime(?,'unixepoch') WHERE id=?",
                           (change['outcome'], state.get('completed_at', state.get('updated_at')), change['route']))
            elif kind == 'finish_metrics':
                db.execute("UPDATE workflow_metrics SET outcome=?,completed_at=datetime(?,'unixepoch') WHERE request_id=?",
                           (change['outcome'], state.get('completed_at', state.get('updated_at')), state['id']))
        db.execute("INSERT INTO audit_log(ts,agent,action,table_name,details) VALUES(datetime('now'),'system','reconcile','lifecycle',?)", (json.dumps(change),))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    project = args.project.resolve()
    path = project / '.opencode/context/team.db'
    if not path.is_file():
        raise ValueError('No TeamDB; ejecutar /skalling-init')
    backup = None
    if args.apply:
        backup = project / '.skalling-backups' / ('reconcile-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.db')
        backup.parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(path.as_uri()+'?mode=ro', uri=True)) as source, closing(sqlite3.connect(backup)) as target:
            source.backup(target)
    with closing(connect(path, readonly=not args.apply)) as db:
        if args.apply:
            db.execute('BEGIN IMMEDIATE')
        before = inspect(db)
        if args.apply:
            repair(db, before)
            db.commit()
        after = inspect(db) if args.apply else before
    print(json.dumps({**after, 'applied': before['repairs'] if args.apply else [], 'backup': str(backup) if backup else None}, ensure_ascii=False, indent=2))
    return 0 if after['ready'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, sqlite3.Error) as exc:
        raise SystemExit('Reconciliación incompleta: ' + str(exc))
