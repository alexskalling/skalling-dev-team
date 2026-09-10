#!/usr/bin/env python3
"""Session-bound goal state and guarded local commit; never pushes."""
import hashlib
import json
import sqlite3
import subprocess
import sys
from pathlib import Path


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], input=b'', stderr=subprocess.PIPE)


def fingerprint(root):
    digest = hashlib.sha256(git(root, 'diff', 'HEAD', '--', '.', ':(exclude)db/teamdb/team.dump.sql'))
    for name in git(root, 'ls-files', '--others', '--exclude-standard', '-z').split(b'\0'):
        if name and not name.startswith(b'.opencode/'):
            path = root / name.decode()
            if path.is_file() and not path.is_symlink():
                digest.update(name)
                digest.update(path.read_bytes())
    return digest.hexdigest()


def operate(root, session, action, payload):
    root = Path(root).resolve()
    actual = Path(git(root, 'rev-parse', '--show-toplevel').decode().strip()).resolve()
    if root != actual or not session:
        raise ValueError('Goal requiere la raíz Git real y una sesión de OpenCode.')
    path = root / '.opencode/context/team.db'
    if not path.exists():
        if action != 'start':
            return None
        path.parent.mkdir(parents=True, exist_ok=True)
        schema = Path(__file__).resolve().parents[1] / 'sql/project-schema.sql'
        with sqlite3.connect(path) as initial:
            initial.executescript(schema.read_text())
    db = sqlite3.connect(path, timeout=5)
    db.row_factory = sqlite3.Row
    try:
        exists = db.execute("SELECT 1 FROM sqlite_master WHERE name='session_goals'").fetchone()
        if not exists and action != 'start':
            return None
        if action == 'start':
            db.execute('''CREATE TABLE IF NOT EXISTS session_goal_history(
                id INTEGER PRIMARY KEY, session TEXT NOT NULL, goal_json TEXT NOT NULL,
                archived_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''')
            db.execute('''CREATE TABLE IF NOT EXISTS session_goals(
                session TEXT PRIMARY KEY, objective TEXT NOT NULL, status TEXT NOT NULL,
                base_head TEXT NOT NULL, protected TEXT NOT NULL, branch TEXT NOT NULL,
                turns INTEGER NOT NULL DEFAULT 0, stagnant INTEGER NOT NULL DEFAULT 0,
                fingerprint TEXT NOT NULL, checkpoint TEXT NOT NULL DEFAULT '',
                reason TEXT NOT NULL DEFAULT '', commit_sha TEXT,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''')
        if action == 'status':
            result = db.execute('SELECT * FROM session_goals WHERE session=?', (session,)).fetchone()
            return dict(result) if result else None
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT * FROM session_goals WHERE session=?', (session,)).fetchone()
        if action == 'start':
            objective = payload.get('objective', '').strip()
            if not objective:
                raise ValueError('Escribe el objetivo después de /skalling-goal.')
            if db.execute("SELECT 1 FROM session_goals WHERE status IN ('active','paused','blocked','committing')").fetchone():
                raise ValueError('Ya hay un objetivo pendiente. Usa status, resume o cancel; no iniciar objetivos concurrentes.')
            if git(root, 'diff', '--cached', '--name-only').strip():
                raise ValueError('Hay archivos previamente preparados para commit. Resolver ese índice antes de iniciar el objetivo.')
            protected = set(git(root, 'diff', 'HEAD', '--name-only', '-z').decode().split('\0'))
            protected.update(git(root, 'ls-files', '--others', '--exclude-standard', '-z').decode().split('\0'))
            protected.discard('')
            if row:
                db.execute('INSERT INTO session_goal_history(session,goal_json) VALUES(?,?)',
                           (session, json.dumps(dict(row))))
            db.execute('''INSERT INTO session_goals
                (session,objective,status,base_head,protected,branch,fingerprint)
                VALUES(?,?,'active',?,?,?,?) ON CONFLICT(session) DO UPDATE SET
                objective=excluded.objective,status='active',base_head=excluded.base_head,
                protected=excluded.protected,branch=excluded.branch,fingerprint=excluded.fingerprint,
                checkpoint='',reason='',commit_sha=NULL,turns=0,stagnant=0''', (session, objective, git(root, 'rev-parse', 'HEAD').decode().strip(),
                        json.dumps(sorted(protected)), git(root, 'symbolic-ref', '--short', 'HEAD').decode().strip(),
                        hashlib.sha256(fingerprint(root).encode()).hexdigest()))
        elif action == 'status':
            pass
        elif not row:
            raise ValueError('No hay objetivo en esta sesión. Inícialo con /skalling-goal.')
        elif action in ('pause', 'block', 'cancel'):
            if row['status'] not in ('active', 'paused', 'blocked'):
                raise ValueError('El objetivo ya terminó o está creando su commit.')
            status = {'pause': 'paused', 'block': 'blocked', 'cancel': 'cancelled'}[action]
            db.execute('UPDATE session_goals SET status=?,reason=? WHERE session=?',
                       (status, payload.get('reason', action), session))
        elif action == 'resume':
            if row['status'] not in ('active', 'paused', 'blocked'):
                raise ValueError('Solo se puede retomar un objetivo pendiente.')
            db.execute("UPDATE session_goals SET status='active',reason='',turns=0,stagnant=0 WHERE session=?", (session,))
        elif action == 'checkpoint':
            if row['status'] != 'active':
                raise ValueError('El objetivo no está activo.')
            db.execute('UPDATE session_goals SET checkpoint=? WHERE session=?', (payload.get('summary', ''), session))
        elif action == 'tick' and row['status'] == 'active':
            current = hashlib.sha256((fingerprint(root) + row['checkpoint']).encode()).hexdigest()
            stagnant = row['stagnant'] + 1 if current == row['fingerprint'] else 0
            turns = row['turns'] + 1
            blocked = stagnant >= 3 or turns >= 20
            db.execute('UPDATE session_goals SET fingerprint=?,stagnant=?,turns=?,status=?,reason=? WHERE session=?',
                       (current, stagnant, turns, 'blocked' if blocked else 'active',
                        'Sin avance de archivos/checkpoint en 3 continuaciones o límite de 20 continuaciones alcanzado.' if blocked else '', session))
        elif action == 'commit':
            if row['status'] != 'active' or not row['checkpoint'].strip():
                raise ValueError('Commit requiere objetivo activo y checkpoint con aceptación, pruebas y revisión reales.')
            if git(root, 'rev-parse', 'HEAD').decode().strip() != row['base_head']:
                raise ValueError('HEAD cambió durante el objetivo; no crear otro commit ni reescribir historia.')
            if git(root, 'symbolic-ref', '--short', 'HEAD').decode().strip() != row['branch']:
                raise ValueError('La rama cambió durante el objetivo.')
            files = payload.get('files', [])
            if not files or not payload.get('message', '').strip():
                raise ValueError('Commit requiere mensaje y lista explícita de archivos.')
            protected = set(json.loads(row['protected']))
            staged = set(filter(None, git(root, 'diff', '--cached', '--name-only', '-z').decode().split('\0')))
            if not staged.issubset(set(files)):
                raise ValueError('Hay archivos preparados ajenos al commit solicitado.')
            for name in files:
                candidate = Path(name)
                if candidate.is_absolute() or '..' in candidate.parts or not candidate.parts or candidate.parts[0] == '.git':
                    raise ValueError('Ruta de commit inválida: ' + name)
                if name in protected or not (root / name).resolve().is_relative_to(root):
                    raise ValueError('Archivo previo o externo protegido: ' + name)
                if (root / name).is_dir():
                    raise ValueError('Usa archivos concretos, no directorios.')
            git(root, 'add', '--', *files)
            patch = git(root, 'diff', '--cached', '--', '.', ':(exclude)db/teamdb/team.dump.sql').rstrip(b'\n')
            if not patch:
                raise ValueError('No hay cambios de código/documentación para este commit.')
            digest = hashlib.sha256(patch).hexdigest()[:16]
            receipt = db.execute('SELECT exit_code FROM receipts WHERE tree_hash=? ORDER BY ts DESC,rowid DESC LIMIT 1', (digest,)).fetchone()
            if not receipt or receipt[0] != 0:
                raise ValueError('Revisar los archivos staged con skalling-review antes de crear el commit.')
            db.execute("UPDATE session_goals SET status='committing' WHERE session=?", (session,))
            db.commit()  # Never hold a SQLite writer lock while Git hooks read it.
            gate = Path(__file__).resolve().parents[1] / 'hooks/git-gate.py'
            if not gate.exists():
                gate = Path(__file__).resolve().parent / 'hooks/git-gate.py'
            try:
                subprocess.run([sys.executable, str(gate), 'pre-commit'], cwd=root, check=True, capture_output=True)
                git(root, 'commit', '-m', payload['message'])
            except subprocess.CalledProcessError as error:
                db.execute("UPDATE session_goals SET status='blocked',reason=? WHERE session=?",
                           ('Fallo de commit: ' + (error.stderr or b'').decode(errors='replace')[-2000:], session))
                db.commit()
                raise
            sha = git(root, 'rev-parse', 'HEAD').decode().strip()
            db.execute("UPDATE session_goals SET status='completed',commit_sha=?,reason='' WHERE session=?", (sha, session))
        elif action != 'tick':
            raise ValueError('Acción desconocida: ' + action)
        if action != 'status':
            db.execute('UPDATE session_goals SET updated_at=CURRENT_TIMESTAMP WHERE session=?', (session,))
        db.commit()
        result = db.execute('SELECT * FROM session_goals WHERE session=?', (session,)).fetchone()
        return dict(result) if result else None
    finally:
        db.close()


if __name__ == '__main__':
    try:
        request = json.load(sys.stdin)
        print(json.dumps(operate(request['project'], request['session'], request['action'], request.get('payload', {})), ensure_ascii=False))
    except (ValueError, sqlite3.Error, subprocess.CalledProcessError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
