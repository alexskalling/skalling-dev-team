#!/usr/bin/env python3
"""Read-only Git gates: exact staged/published diffs, never memory maintenance.

SCOPE: este hook corre cosas RÁPIDAS contra el candidato exacto (staged en
pre-commit, commits publicados en pre-push):
  - Detección de secretos hardcodeados (regex SECRET).
  - Coherencia memoria ↔ repo (.md en .opencode/context/ ↔ fila en TeamDB).
  - Receipt sellado por un verificador (Jhon o Luz) para el candidato exacto
    (tree_hash en receipts con exit_code=0).

FUERA DE SCOPE: el linter SQLi (`scripts/skalling-review.sh --lens risk`) NO se
corre aquí. Es un escaneo completo de `scripts/**` que tarda segundos y mira
más allá del candidato exacto. Vive en CI → `.github/workflows/lint-sqli.yml`.
Justificación en AGENTS.md § "Hooks (separación de scopes)".
"""
import hashlib
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

DUMP = 'db/teamdb/team.dump.sql'
PATHSPEC = ['--', '.', ':(exclude)' + DUMP]
CODE = re.compile(r'\.(ts|tsx|js|jsx|py|rs|go|java|cpp|c|sh|bash)$')
# Solo quien verifica puede habilitar un commit de código. Un receipt de
# Alex o de Teo (el que orquesta o el que implementó) no prueba nada: así un
# cambio que se saltó a Jhon no llega al repositorio aunque exista evidencia.
VERIFIERS = ('jhon', 'luz')
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
    if not any(CODE.search(name) for name in names):
        return
    if not db:
        raise ValueError(f'{label}: team.db no existe; no se puede validar la revisión aprobada '
                          'de este código. Correr /skalling-init (o restaurar la base desde '
                          'db/teamdb/team.dump.sql) antes de commitear código. Bloqueado por '
                          'diseño: sin base no hay forma de saber si esto ya se revisó.')
    patch = git('diff', *diff_args, *PATHSPEC).rstrip(b'\n')
    digest = hashlib.sha256(patch).hexdigest()[:16]
    row = db.execute('SELECT exit_code FROM receipts WHERE tree_hash=? AND lower(agent) IN (?, ?) '
                     'ORDER BY ts DESC, rowid DESC LIMIT 1', (digest, *VERIFIERS)).fetchone()
    if not row or row[0] != 0:
        raise ValueError(f'{label}: falta revisión aprobada para estos cambios ({digest}). '
                         'La aprobación tiene que ser de Jhon (verificación) o Luz (revisión) sobre el '
                         'candidato exacto staged; un comprobante de Alex o Teo no cuenta. '
                         'No fabricar comprobantes ni limpiar memoria para desbloquear Git.')
    print(f'OK: {label} coincide con el receipt sellado ({digest})')


def project_root():
    # --show-toplevel da la raiz del WORKTREE actual, no la del repo
    # principal. team.db esta gitignored y solo existe en el checkout
    # original -- un git worktree nuevo nunca lo trae, asi que resolver por
    # show-toplevel hacia fail-closed bloqueaba TODO commit en TODO worktree,
    # justo el flujo que el propio proyecto promueve. --git-common-dir
    # siempre apunta al .git compartido (en el repo principal o en
    # cualquiera de sus worktrees); su padre es la raiz real del proyecto.
    common_dir = Path(git('rev-parse', '--git-common-dir').decode().strip())
    if not common_dir.is_absolute():
        toplevel = Path(git('rev-parse', '--show-toplevel').decode().strip())
        common_dir = toplevel / common_dir
    return common_dir.resolve().parent


def main():
    root = project_root()
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
