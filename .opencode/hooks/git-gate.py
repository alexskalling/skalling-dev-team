#!/usr/bin/env python3
"""Read-only Git gates: exact staged/published diffs, never memory maintenance.

SCOPE: este hook corre cosas RÁPIDAS contra el candidato exacto (staged en
pre-commit, commits publicados en pre-push):
  - Detección de secretos hardcodeados (regex SECRET).
  - Coherencia memoria ↔ repo (.md en .opencode/context/ ↔ fila en TeamDB).
  - Receipt sellado por un verificador (Jhon o Luz) para el candidato exacto
    (tree_hash en receipts con exit_code=0; "not_run" no aprueba) cuando el
    cambio toca algo fuera de las excepciones de documentación (needs_review).

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
# Alcance protegido: TODO cambio necesita revisión aprobada, salvo excepciones
# acotadas que no cambian el comportamiento (documentación, imágenes, fuentes).
# Antes era al revés -- una lista corta de lenguajes -- y quedaban afuera
# migraciones .sql, módulos .mjs, YAML, Dockerfile, package.json, .vue, .php...
# Un .md que define conducta de agentes (prompts, comandos, skills) SÍ es
# código del proceso y no se exime.
EXEMPT_SUFFIX = re.compile(r'\.(md|markdown|txt|rst|adoc|png|jpe?g|gif|webp|ico|bmp|avif|woff2?|ttf|otf|eot)$', re.I)
EXEMPT_NAMES = {'LICENSE', 'LICENSE.txt', 'NOTICE', 'AUTHORS', 'CODEOWNERS', '.gitignore'}
BEHAVIOR_DOCS = ('.opencode/agents/', '.opencode/command/', '.opencode/commands/', '.opencode/skills/',
                 'agents-base/', 'skills-base/', 'command/', 'constitution/')


def needs_review(name):
    if not name:
        return False
    if name.startswith(BEHAVIOR_DOCS):
        return True
    return not (EXEMPT_SUFFIX.search(name) or Path(name).name in EXEMPT_NAMES)


# Solo quien verifica puede habilitar un commit de código. Un receipt de
# Alex o de Teo (el que orquesta o el que implementó) no prueba nada: así un
# cambio que se saltó a Jhon no llega al repositorio aunque exista evidencia.
# auto: verificación configurada que corrió el motor (carril trivial).
# humano: una persona que corrió skalling-approve.sh en su terminal (el test
# real del proyecto sobre lo staged, igual que Jhon).
VERIFIERS = ('jhon', 'luz', 'auto', 'humano')
# Formatos de credenciales de proveedores. El lookbehind evita que "sk-"
# dentro de una palabra ("task-context-...") dispare; los formatos con
# guiones (sk-ant-..., sk-proj-...) se nombran explícitamente. La URL con
# contraseña ignora marcadores obvios (${VAR}, <pass>, password, changeme).
SECRET = re.compile('|'.join((
    r'gh[pousr]_[A-Za-z0-9]{20,}',
    r'github_pat_[A-Za-z0-9_]{22,}',
    r'glpat-[A-Za-z0-9_-]{20,}',
    r'(?<![A-Za-z0-9])sk-(?:ant-[a-z]+\d*-|proj-|svcacct-|admin-)[A-Za-z0-9_-]{20,}',
    r'(?<![A-Za-z0-9_-])sk-[A-Za-z0-9]{20,}',
    r'(?:sk|rk)_live_[A-Za-z0-9]{16,}',
    r'xox[abposr]-[A-Za-z0-9-]{10,}',
    r'hooks\.slack\.com/services/T[A-Za-z0-9_/]{20,}',
    r'npm_[A-Za-z0-9]{36}',
    r'AIza[0-9A-Za-z_-]{20,}',
    r'(?:AKIA|ASIA)[0-9A-Z]{16}',
    r'aws_secret_access_key\s*[=:]\s*["\']?[A-Za-z0-9/+=]{40}',
    r'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    r'Bearer [A-Za-z0-9._-]{20,}',
    r'BEGIN [A-Z ]*PRIVATE KEY',
    r'[a-z][a-z0-9+.-]*://[^/\s:@\'"]+:(?!\$\{|<|password\b|pass\b|changeme\b|secret\b|xxx)[^/\s:@\'"]{6,}@',
)), re.I)


def git(*args):
    return subprocess.check_output(['git', *args], input=b'')


EMPTY_TREE = None


def empty_tree():
    global EMPTY_TREE
    if EMPTY_TREE is None:
        EMPTY_TREE = git('hash-object', '-t', 'tree', '--stdin').decode().strip()
    return EMPTY_TREE


def evidence_backed(agent, command):
    """Un receipt vale solo si lo produjo algo que CALCULÓ el resultado: la
    verificación real de Jhon (skalling-verify.sh), la revisión real de Luz
    (skalling-review.sh), el motor skalling_workflow o una dispensa humana.
    Auditoría externa v0.12.0 #2: un 'review-seal' de Luz con resumen vacío
    (valores por defecto del sellador) abría el commit sin revisión."""
    command = str(command or '')
    if command.startswith('skalling_workflow:'):
        return True
    if agent in ('jhon', 'humano'):
        return command.startswith(('skalling-verify.sh', 'waived:', 'not_run:')) or '+ skalling-verify.sh' in command
    if agent == 'luz':
        return command.startswith('review --')
    return False


def receipt_verdict(db, digest):
    # Decide el receipt más reciente que registra un resultado. Un "not_run"
    # (Jhon sin tests configurados) no es aprobación ni rechazo: no cuenta.
    rows = db.execute('SELECT exit_code, command, lower(agent) FROM receipts WHERE tree_hash=? '
                      'AND lower(agent) IN (%s) ORDER BY ts DESC, rowid DESC' % ','.join('?' * len(VERIFIERS)),
                      (digest, *VERIFIERS)).fetchall()
    rows = [r[:2] for r in rows if evidence_backed(r[2], r[1])]
    not_run = [r for r in rows if str(r[1] or '').startswith('not_run:')]
    decisive = [r for r in rows if not str(r[1] or '').startswith('not_run:')]
    return decisive, not_run


def commit_digest(commit):
    parents = git('rev-list', '--parents', '-n', '1', commit).decode().split()
    parent = parents[1] if len(parents) > 1 else empty_tree()
    return hashlib.sha256(git('diff', parent, commit, *PATHSPEC).rstrip(b'\n')).hexdigest()[:16]


def patch_id(patch):
    out = subprocess.run(['git', 'patch-id', '--verbatim'], input=patch, capture_output=True, check=True).stdout
    return out.split()[0].decode() if out.strip() else None


def equivalent_digests(commit):
    # Un rebase o cherry-pick cambia el contexto del diff (números de línea,
    # blobs de "index"), así que su digest exacto ya no coincide con el
    # receipt aunque el cambio sea el mismo. Se buscan commits locales
    # (ramas y reflog, donde queda el original pre-rebase) con el mismo
    # patch-id --verbatim (no ignora espacios) y se devuelven SUS digests
    # exactos: la aprobación sigue anclada a un receipt real de Jhon/Luz.
    parents = git('rev-list', '--parents', '-n', '1', commit).decode().split()
    parent = parents[1] if len(parents) > 1 else empty_tree()
    target = patch_id(git('diff', parent, commit, *PATHSPEC))
    if not target:
        return []
    log = git('log', '--all', '--reflog', '--no-merges', '--max-count=2000', '-p',
              '--format=commit %H', *PATHSPEC)
    ids = subprocess.run(['git', 'patch-id', '--verbatim'], input=log, capture_output=True, check=True).stdout
    same = [line.split()[1].decode() for line in ids.splitlines()
            if len(line.split()) == 2 and line.split()[0].decode() == target]
    return [commit_digest(other) for other in same if not other.startswith(commit)]


def check(diff_args, db, label, equivalents=None, require_receipt=True):
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
    if not require_receipt or not any(needs_review(name) for name in names):
        return
    if not db:
        raise ValueError(f'{label}: team.db no existe; no se puede validar la revisión aprobada '
                          'de este código. Correr /skalling-init (o restaurar la base desde '
                          'db/teamdb/team.dump.sql) antes de commitear código. Bloqueado por '
                          'diseño: sin base no hay forma de saber si esto ya se revisó.')
    patch = git('diff', *diff_args, *PATHSPEC).rstrip(b'\n')
    digest = hashlib.sha256(patch).hexdigest()[:16]
    decisive, not_run = receipt_verdict(db, digest)
    if (not decisive or decisive[0][0] != 0) and equivalents:
        for alternative in equivalents():
            alt_decisive, _ = receipt_verdict(db, alternative)
            if alt_decisive and alt_decisive[0][0] == 0:
                print(f'OK: {label} es el mismo cambio que un candidato aprobado ({alternative}); '
                      f'reubicado por rebase/cherry-pick ({digest})')
                return
    if not decisive or decisive[0][0] != 0:
        hint = (' Jhon no pudo correr tests (no hay testing.unit.command): configurarlo, pedir revisión de Luz '
                '(skalling-review.sh) o que un humano selle con SKALLING_VERIFY_WAIVER="motivo".') if not_run and not decisive else ''
        raise ValueError(f'{label}: falta revisión aprobada para estos cambios ({digest}). '
                         'La aprobación tiene que ser de Jhon (verificación) o Luz (revisión) sobre el '
                         'candidato exacto staged; un comprobante de Alex o Teo no cuenta. '
                         'No fabricar comprobantes ni limpiar memoria para desbloquear Git.' + hint
                         + ' Si sos una persona commiteando desde tu terminal (fuera de OpenCode): '
                         '`bash .opencode/scripts/skalling-approve.sh` corre los tests del proyecto sobre '
                         'lo staged y, si pasan, habilita este commit.')
    command = str(decisive[0][1] or '')
    if command.startswith('waived:'):
        print(f'AVISO: {label} aprobado SIN tests por decisión humana ({command[7:].strip()}) ({digest})', file=sys.stderr)
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


def clean_automerge(commit, parents):
    # Un merge sin resolución manual no agrega código propio: su árbol es
    # exactamente el que Git calcula al fusionar los dos padres. Si hubo
    # conflictos o ediciones en el merge, merge-tree da otro árbol (o falla)
    # y el merge necesita su propio receipt. Git < 2.38 no tiene
    # --write-tree: se cae al comportamiento estricto.
    if len(parents) != 2:
        return False
    try:
        merged = subprocess.run(['git', 'merge-tree', '--write-tree', *parents],
                                capture_output=True, check=True).stdout.split()[0].decode()
    except (subprocess.CalledProcessError, IndexError):
        return False
    return merged == git('rev-parse', commit + '^{tree}').decode().strip()


def check_commit(commit, db, seen):
    if commit in seen:
        return
    seen.add(commit)
    parents = git('rev-list', '--parents', '-n', '1', commit).decode().split()[1:]
    label = 'commit ' + commit[:12]
    if clean_automerge(commit, parents):
        # Secretos y memoria se revisan igual sobre lo que entra con el merge;
        # la aprobación se exige a cada commit del otro lado, uno por uno.
        check([parents[0], commit], db, label, require_receipt=False)
        side = git('rev-list', '--reverse', parents[1], '^' + parents[0], '--not', '--remotes').decode().split()
        for other in side:
            check_commit(other, db, seen)
        print(f'OK: {label} es un merge automático de cambios verificados')
        return
    parent = parents[0] if parents else empty_tree()
    check([parent, commit], db, label, equivalents=lambda: equivalent_digests(commit))


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
                seen = set()
                for commit in git(*args).decode().splitlines():
                    check_commit(commit, db, seen)
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
