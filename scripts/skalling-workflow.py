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
DUMP_PATHSPEC = ':(exclude)db/teamdb/team.dump.sql'
SCOPE_EXCLUDES = [DUMP_PATHSPEC, ':(exclude).opencode', ':(exclude).git']


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


def changed_paths(root):
    """Every path git sees as touched (tracked or not), regardless of stage."""
    out = subprocess.run(['git', 'status', '--porcelain=v1', '--untracked-files=all', '-z', '--', '.', *SCOPE_EXCLUDES],
                          cwd=root, capture_output=True, timeout=30)
    if out.returncode != 0:
        return set()
    tokens = out.stdout.decode('utf-8', 'replace').split('\0')
    paths, i = set(), 0
    while i < len(tokens) and tokens[i]:
        entry = tokens[i]
        paths.add(entry[3:])
        if entry[:2].strip('?').upper() in {'R', 'C'} or entry[0] in 'RC' or entry[1] in 'RC':
            i += 1  # rename/copy carries an extra NUL-separated "from" path
        i += 1
    return paths


def require_scope(root, files):
    extra = changed_paths(root) - set(files)
    require(not extra, f'Scope creep: {sorted(extra)} changed but not declared; use rescope')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def seal_receipt(db, root, identifier, files, verifier):
    """Bridge to the Git-facing approval: stage exactly the reviewed files and
    seal a receipt with the same tree_hash algorithm scripts/hooks/git-gate.py
    checks at commit time. Best-effort: any Git failure here just means the
    receipt is not sealed, git-gate.py still requires manual evidence."""
    try:
        if subprocess.run(['git', 'add', '--'] + list(files), cwd=root, capture_output=True, timeout=30).returncode != 0:
            return
        diff = subprocess.run(['git', 'diff', '--cached', '--', '.', DUMP_PATHSPEC],
                               cwd=root, capture_output=True, timeout=30)
        patch = diff.stdout.rstrip(b'\n')  # git-gate.py hashes the patch with the same rstrip
        if diff.returncode != 0 or not patch.strip():
            return
    except (OSError, subprocess.SubprocessError):
        return
    if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='receipts'").fetchone():
        return
    if not db.execute("SELECT 1 FROM pragma_table_info('receipts') WHERE name='tree_hash'").fetchone():
        return
    tree_hash = hashlib.sha256(patch).hexdigest()[:16]
    db.execute("INSERT INTO receipts (id, task_id, agent, command, exit_code, output_summary, ts, tree_hash) "
               "VALUES (?,?,?,?,?,?,datetime('now'),?)",
               (f'rcpt_wf_{identifier}_{int(time.time())}', identifier, verifier, 'skalling_workflow:complete',
                0, json.dumps({'source': 'skalling_workflow'}), tree_hash))


def apply_pending_migrations(root):
    init_script = Path(__file__).resolve().parent / 'teamdb-init.sh'
    subprocess.run(['bash', str(init_script), str(root)], capture_output=True)


def ensure_tables(root, path):
    """agent_workflows/agent_workflow_events are versioned schema
    (sql/migrations/031_*), not something this script fabricates at runtime.
    Never connect() before checking existence: sqlite3.connect() creates an
    empty file as a side effect, and teamdb-init.sh treats an existing-but-
    schemaless file as a corrupt DB rather than a fresh one. Check first,
    then self-heal by applying pending migrations (same pattern
    teamdb-seal-receipt.sh uses for tree_hash) instead of silently creating
    undeclared tables."""
    if not path.exists():
        apply_pending_migrations(root)
    db = sqlite3.connect(path, timeout=10)
    if not db.execute("SELECT 1 FROM sqlite_master WHERE name='agent_workflows'").fetchone():
        db.close()
        apply_pending_migrations(root)
        db = sqlite3.connect(path, timeout=10)
        if not db.execute("SELECT 1 FROM sqlite_master WHERE name='agent_workflows'").fetchone():
            raise ValueError('agent_workflows falta y teamdb-init.sh no pudo migrarla; correr bash scripts/teamdb-init.sh manualmente')
    return db


def save(db, identifier, actor, session, action, state, evidence, now):
    state['handoffs'] += int(state.get('actor', actor) != actor)
    state['actor'] = actor
    state['updated_at'] = now
    db.execute('INSERT INTO agent_workflows(id,body) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body',
               (identifier, json.dumps(state)))
    db.execute('INSERT INTO agent_workflow_events(request_id,actor,session,action,state,evidence,ts) VALUES(?,?,?,?,?,?,?)',
               (identifier, actor, session, action, state['state'], json.dumps(evidence), now))
    return state


def read(db, identifier):
    row = db.execute('SELECT body FROM agent_workflows WHERE id=?', (identifier,)).fetchone()
    return json.loads(row[0]) if row else None


def check(db, root, actor, session, identifier, payload, request):
    """Runs the verification command OUTSIDE any held write lock: the command
    can take up to 120s and every other agent_workflows writer only waits 10s,
    so holding BEGIN IMMEDIATE across subprocess.run would lock them out.

    'check' only executes and records evidence; it never approves anything by
    itself. A command that exits 0 is one recorded observation, not proof the
    declared criteria are covered -- that judgment is a separate 'approve'
    action, so a single lucky/irrelevant green run (e.g. `true`) can't stand
    in for a real review, and Jhon/Luz can record several checks before
    deciding."""
    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None, 'Unknown workflow')
    require(state['state'] != 'completed', 'Completed workflows are immutable')
    expected = 'verification_ready' if actor == 'jhon' else 'verified'
    require(actor in {'jhon', 'luz'} and state['state'] == expected, 'Check role/order invalid')
    require(bool(state['oracle']), 'Jhon must derive an oracle before checks')
    require(session != state['implementation_session'], 'Independent verifier session required')
    digest = state['digest']
    require(fingerprint(root, state['files']) == digest, 'Candidate changed; return to Teo')
    argv = payload.get('argv')
    require(isinstance(argv, list) and argv and all(isinstance(v, str) and '\0' not in v for v in argv), 'Command argv required')
    require(bool(payload.get('method')), 'Verification method required')
    require(bool(str(payload.get('criterion', '')).strip()),
            'Each check must name which declared criterion it exercises, not just run a command')
    db.commit()  # release the write lock before the potentially slow command

    # Native tool wrapper obtains OpenCode permission for this exact command.
    result = subprocess.run(argv, cwd=root, capture_output=True, timeout=120)

    db.execute('BEGIN IMMEDIATE')
    state = read(db, identifier)
    require(state is not None and state['state'] == expected, 'Workflow changed during verification; retry check')
    require(fingerprint(root, state['files']) == digest == state['digest'], 'Verification changed candidate; approval denied')
    verification = {'agent': actor, 'session': session, 'method': payload['method'], 'argv': argv,
                     'criterion': payload['criterion'], 'exit_code': result.returncode, 'digest': digest,
                     'output': (result.stdout + result.stderr)[-16000:].decode('utf-8', 'replace'),
                     'model': request.get('model'), 'independence': 'context-and-method; model diversity unverified'}
    state['checks'].append(verification)
    state['verification'] = verification
    now = time.time()
    state = save(db, identifier, actor, session, 'check', state, payload.get('evidence', ''), now)
    db.commit()
    return state


def operate(request):
    root = Path(request['project']).resolve()
    actor, session = request['actor'].lower(), request['session']
    require(actor in ROLES and bool(session), 'Runtime agent/session required')
    action, payload = request['action'], request.get('payload', {})
    identifier = payload['id']
    require(isinstance(identifier, str) and 0 < len(identifier) <= 200, 'Invalid request id')
    path = root / '.opencode/context/team.db'
    require(path.parent.is_dir(), 'Initialize project context first')
    db = ensure_tables(root, path)
    try:
        if action == 'status':
            state = read(db, identifier)
            require(state is not None, 'Unknown workflow')
            return state
        if action == 'check':
            return check(db, root, actor, session, identifier, payload, request)

        db.execute('BEGIN IMMEDIATE')
        state = read(db, identifier)
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
            require(state['state'] != 'completed', 'Completed workflows are immutable')
            if action in TRANSITIONS:
                owner, previous, target = TRANSITIONS[action]
                require(actor == owner and state['state'] == previous, f'{action} requires {owner} in {previous}')
                require(action == 'deliver' or bool(str(evidence).strip()), 'Transition evidence required')
                if action == 'deliver':
                    require_scope(root, state['files'])
                    state['digest'] = fingerprint(root, state['files'])
                    state['implementation_session'] = session
                    state['oracle'] = None
                    state['checks'] = []
                state['state'] = target
            elif action == 'rescope':
                require(actor == 'teo' and state['state'] in {'implementation_ready', 'verification_ready'},
                        'Only Teo widens scope, and only before an approval is trusted')
                added = payload.get('files', [])
                require(isinstance(added, list) and added and all(isinstance(f, str) for f in added), 'Enumerated files required')
                require(bool(str(evidence).strip()), 'Rescope requires evidence explaining the additional files')
                widened = sorted(set(state['files']) | set(added))
                require(widened != state['files'], 'Rescope must add at least one new file')
                for name in widened:
                    scoped(root, name)
                state['files'] = widened
                state['digest'] = None
                state['oracle'] = None
                state['checks'] = []
                state['state'] = 'implementation_ready'
            elif action == 'oracle':
                require(actor == 'jhon' and state['state'] == 'verification_ready', 'Only Jhon prepares the oracle before verification')
                require(session != state['implementation_session'], 'Independent verifier session required')
                fields = ('expected', 'negative', 'invariant', 'refutation')
                require(all(isinstance(payload.get(f), str) and payload[f].strip() for f in fields), 'Complete independent oracle required')
                require(state['oracle'] is None, 'Oracle is frozen for this delivery')
                state['oracle'] = {f: payload[f] for f in fields}
            elif action == 'approve':
                require(actor in {'jhon', 'luz'}, 'Only Jhon or Luz approve')
                target = {'jhon': 'verified', 'luz': 'quality_reviewed'}[actor]
                source = {'jhon': 'verification_ready', 'luz': 'verified'}[actor]
                require(state['state'] == source, f'{actor} approves from {source}, not {state["state"]}')
                require(bool(str(evidence).strip()),
                        'Approval requires evidence that the declared criteria are covered, not just a green exit code')
                if actor == 'luz':
                    require(isinstance(payload.get('findings'), str) and payload['findings'].strip(),
                            'Luz must record an explicit risk verdict, not just a command exit code')
                relevant = [c for c in state['checks'] if c['agent'] == actor and c['digest'] == state['digest']]
                require(relevant, f'{actor} must record at least one check on the current candidate before approving')
                require(all(c['exit_code'] == 0 for c in relevant),
                        'A failing check is on record for this candidate; a later passing one does not erase it')
                if actor == 'luz':
                    state['quality_findings'] = payload['findings']
                state['state'] = target
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
                require_scope(root, state['files'])
                require(fingerprint(root, state['files']) == state['digest'], 'Candidate changed after verification')
                state['state'] = 'completed'
                state['completed_at'] = now
                state['duration_ms'] = round((now - state['started_at']) * 1000)
                verifier = state.get('verification', {}).get('agent', 'jhon')
                seal_receipt(db, root, identifier, state['files'], verifier)
            else:
                raise ValueError('Unknown workflow action')
        state = save(db, identifier, actor, session, action, state, evidence, now)
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
