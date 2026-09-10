#!/usr/bin/env python3
"""Read-only Git gates: exact staged/published diffs, never memory maintenance."""
import hashlib
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

DUMP = 'db/teamdb/team.dump.sql'
PATHSPEC = ['--', '.', ':(exclude)' + DUMP]
CODE = re.compile(r'\.(ts|tsx|js|jsx|py|rs|go|java|cpp|c|sh|bash)$')
SECRET = re.compile(r'(ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|AKIA[0-9A-Z]{16}|Bearer [A-Za-z0-9._-]{20,}|BEGIN [A-Z ]*PRIVATE KEY)', re.I)


def git(*args):
    return subprocess.check_output(['git', *args], input=b'')


def check(diff_args, db, label):
    # Inspect the actual candidate, not mutable live memory. No git add/export.
    full_patch = git('diff', *diff_args, '--', '.')
    for line in full_patch.splitlines():
        if line.startswith(b'+') and not line.startswith(b'+++') and SECRET.search(line.decode('utf-8', 'replace')):
            raise ValueError(f'{label}: posible secreto en el contenido a publicar; revisar el diff. No se modificó la DB.')
    names = git('diff', *diff_args, '--name-only', '-z', *PATHSPEC).decode().split('\0')
    if db:
        for name in names:
            if '/archive/' in name or not name.endswith('.md'):
                continue
            table = None
            slug = Path(name).stem
            if name.startswith('.opencode/changes/'):
                table, slug = 'plans', name.split('/')[2]
            for folder, target in [('decisiones', 'decisions'), ('problemas-conocidos', 'known_problems'),
                                   ('followups', 'work_in_progress')]:
                if name.startswith('.opencode/context/' + folder + '/'):
                    table = target
            if table and not db.execute(f'SELECT 1 FROM {table} WHERE slug=? LIMIT 1', (slug,)).fetchone():
                raise ValueError(f'{label}: {name} no tiene registro en TeamDB; no crear memoria paralela.')
    if not db or not any(CODE.search(name) for name in names):
        return
    patch = git('diff', *diff_args, *PATHSPEC).rstrip(b'\n')
    digest = hashlib.sha256(patch).hexdigest()[:16]
    row = db.execute('SELECT exit_code FROM receipts WHERE tree_hash=? ORDER BY ts DESC, rowid DESC LIMIT 1', (digest,)).fetchone()
    if not row or row[0] != 0:
        raise ValueError(f'{label}: falta revisión aprobada para estos cambios ({digest}). '
                         'Revisar el candidato exacto; no fabricar comprobantes ni limpiar memoria para desbloquear Git.')
    print(f'OK: {label} coincide con el receipt sellado ({digest})')


def main():
    root = Path(git('rev-parse', '--show-toplevel').decode().strip())
    path = root / '.opencode/context/team.db'
    db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=5) if path.exists() else None
    try:
        if sys.argv[1] == 'pre-commit':
            check(['--cached'], db, 'commit preparado')
        elif sys.argv[1] == 'pre-push':
            for line in sys.stdin:
                fields = line.split()
                if len(fields) != 4:
                    raise ValueError('Entrada pre-push inválida')
                _, local, _, remote = fields
                if not re.fullmatch(r'[a-fA-F0-9]{40,64}', local) or not re.fullmatch(r'[a-fA-F0-9]{40,64}', remote):
                    raise ValueError('Referencia Git inválida')
                if not local.strip('0'):
                    continue
                revision = local + '^{commit}'
                args = ['rev-list', '--reverse', '--first-parent', revision]
                if remote.strip('0'):
                    args += ['^' + remote]
                else:
                    args += ['--not', '--remotes']
                for commit in git(*args).decode().splitlines():
                    parents = git('rev-list', '--parents', '-n', '1', commit).decode().split()
                    parent = parents[1] if len(parents) > 1 else git('hash-object', '-t', 'tree', '--stdin').decode().strip()
                    check([parent, commit], db, 'commit ' + commit[:12])
        else:
            raise ValueError('Modo de hook inválido')
    finally:
        if db:
            db.close()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, sqlite3.Error, subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
