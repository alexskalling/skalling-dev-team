#!/usr/bin/env python3
"""Private backend of the runtime-owned skalling_workflow tool, not a shell API.

Actor/session come from ToolContext. This is process discipline, not protection
against the OS user who owns both the interpreter and database.
"""
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import time

ROLES = {'alex', 'pol', 'sol', 'teo', 'jhon', 'luz', 'pau', 'jes'}
TRANSITIONS = {
    'clarify': ('pol', 'requested', 'clarified'),
    'plan': ('sol', 'clarified', 'planned'),
    'ready': ('sol', 'planned', 'implementation_ready'),
    'deliver': ('teo', 'implementation_ready', 'verification_ready'),
    'document': ('pau', 'quality_reviewed', 'documented'),
}


def scoped(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root) or any(p in {'.git', '.opencode'} for p in path.relative_to(root).parts):
        raise ValueError('Scope must stay in product files within the project')
    if path.name.startswith('.env') or path.suffix in {'.pem', '.db', '.sqlite', '.sqlite3'}:
        raise ValueError('Sensitive files require a separate authorized operation')
    return path


def fingerprint(root, files):
    digest = hashlib.sha256()
    for name in sorted(files):
        path = scoped(root, name)
        digest.update(name.encode() + b'\0')
        digest.update(path.read_bytes() if path.is_file() else b'<absent>')
        digest.update(b'\0')
    return digest.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def operate(request):
    root = Path(request['project']).resolve()
    actor, session = request['actor'].lower(), request['session']
    require(actor in ROLES and bool(session), 'Runtime agent/session required')
    action, payload = request['action'], request.get('payload', {})
    identifier = payload['id']
    require(isinstance(identifier, str) and 0 < len(identifier) <= 200, 'Invalid request id')
    path = root / '.opencode/context/team.db'
    require(path.parent.is_dir(), 'Initialize project context first')
    db = sqlite3.connect(path, timeout=10)
    try:
        db.execute('CREATE TABLE IF NOT EXISTS agent_workflows(id TEXT PRIMARY KEY, body TEXT NOT NULL)')
        db.execute('''CREATE TABLE IF NOT EXISTS agent_workflow_events(
            id INTEGER PRIMARY KEY, request_id TEXT NOT NULL, actor TEXT NOT NULL,
            session TEXT NOT NULL, action TEXT NOT NULL, state TEXT NOT NULL,
            evidence TEXT NOT NULL, ts REAL NOT NULL)''')
        db.commit()
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT body FROM agent_workflows WHERE id=?', (identifier,)).fetchone()
        state = json.loads(row[0]) if row else None
        now = time.time()
        evidence = payload.get('evidence', '')
        if action == 'start':
            require(actor == 'alex' and state is None, 'Only Alex creates a new workflow; id cannot be reused')
            risk = payload.get('risk')
            require(risk in {'low', 'medium', 'high'}, 'Risk required')
            require(payload.get('decision') == 'none', 'Pending decisions require explicit user resolution first')
            require(payload.get('scope') in {'local', 'module', 'cross-cutting'}, 'Known scope required')
            if payload.get('sensitive') or payload['scope'] == 'cross-cutting':
                risk = 'high'
            elif payload['scope'] == 'module' and risk == 'low':
                risk = 'medium'
            files = payload.get('files', [])
            require(isinstance(files, list) and files and all(isinstance(f, str) for f in files), 'Enumerated files required')
            require(bool(payload.get('acceptance', '').strip()), 'Observable acceptance required')
            fingerprint(root, files)
            state = {'id': identifier, 'risk': risk, 'files': files, 'acceptance': payload['acceptance'],
                     'state': 'implementation_ready' if risk == 'low' else ('clarified' if risk == 'medium' else 'requested'),
                     'route': {'low': 'FAST-TRACK', 'medium': 'INLINE', 'high': 'SDD'}[risk],
                     'started_at': now, 'handoffs': 0, 'checks': [], 'oracle': None, 'digest': None}
        else:
            require(state is not None, 'Unknown workflow')
            if action == 'status':
                return state
            require(state['state'] != 'completed', 'Completed workflows are immutable')
            if action in TRANSITIONS:
                owner, previous, target = TRANSITIONS[action]
                require(actor == owner and state['state'] == previous, f'{action} requires {owner} in {previous}')
                require(action == 'deliver' or bool(str(evidence).strip()), 'Transition evidence required')
                if action == 'deliver':
                    state['digest'] = fingerprint(root, state['files'])
                    state['implementation_session'] = session
                    state['oracle'] = None
                    state['checks'] = []
                state['state'] = target
            elif action == 'oracle':
                require(actor == 'jhon' and state['state'] == 'verification_ready', 'Only Jhon prepares the oracle before verification')
                require(session != state['implementation_session'], 'Independent verifier session required')
                fields = ('expected', 'negative', 'invariant', 'refutation')
                require(all(isinstance(payload.get(f), str) and payload[f].strip() for f in fields), 'Complete independent oracle required')
                require(state['oracle'] is None, 'Oracle is frozen for this delivery')
                state['oracle'] = {f: payload[f] for f in fields}
            elif action == 'check':
                expected = 'verification_ready' if actor == 'jhon' else 'verified'
                require(actor in {'jhon', 'luz'} and state['state'] == expected, 'Check role/order invalid')
                require(bool(state['oracle']), 'Jhon must derive an oracle before checks')
                require(session != state['implementation_session'], 'Independent verifier session required')
                require(fingerprint(root, state['files']) == state['digest'], 'Candidate changed; return to Teo')
                argv = payload.get('argv')
                require(isinstance(argv, list) and argv and all(isinstance(v, str) and '\0' not in v for v in argv), 'Command argv required')
                require(bool(payload.get('method')), 'Verification method required')
                # Native tool wrapper obtains OpenCode permission for this exact command.
                result = subprocess.run(argv, cwd=root, capture_output=True, timeout=120)
                verification = {'agent': actor, 'session': session, 'method': payload['method'], 'argv': argv,
                                'exit_code': result.returncode, 'digest': state['digest'],
                                'output': (result.stdout + result.stderr)[-16000:].decode('utf-8', 'replace'),
                                'model': request.get('model'), 'independence': 'context-and-method; model diversity unverified'}
                require(fingerprint(root, state['files']) == state['digest'], 'Verification changed candidate; approval denied')
                state['checks'].append(verification)
                state['verification'] = verification
                if result.returncode == 0:
                    state['state'] = 'verified' if actor == 'jhon' else 'quality_reviewed'
            elif action == 'reject':
                require(actor in {'jhon', 'luz'} and state['state'] in {'verification_ready', 'verified', 'quality_reviewed'}, 'Invalid rejection')
                require(bool(str(evidence).strip()), 'Rejection requires diagnostic evidence')
                state['state'] = 'implementation_ready'
                state['oracle'] = None
                state['checks'] = []
            elif action == 'complete':
                require(actor == 'alex', 'Only Alex completes a workflow')
                expected = 'documented' if state['risk'] == 'high' else 'verified'
                require(state['state'] == expected, f'Completion requires {expected}')
                require(fingerprint(root, state['files']) == state['digest'], 'Candidate changed after verification')
                state['state'] = 'completed'
                state['completed_at'] = now
                state['duration_ms'] = round((now - state['started_at']) * 1000)
            else:
                raise ValueError('Unknown workflow action')
        state['handoffs'] += int(state.get('actor', actor) != actor)
        state['actor'] = actor
        state['updated_at'] = now
        db.execute('INSERT INTO agent_workflows(id,body) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body',
                   (identifier, json.dumps(state)))
        db.execute('INSERT INTO agent_workflow_events(request_id,actor,session,action,state,evidence,ts) VALUES(?,?,?,?,?,?,?)',
                   (identifier, actor, session, action, state['state'], json.dumps(evidence), now))
        db.commit()
        return state
    finally:
        db.close()


if __name__ == '__main__':
    try:
        print(json.dumps(operate(json.load(sys.stdin))))
    except (ValueError, KeyError, OSError, sqlite3.Error, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
