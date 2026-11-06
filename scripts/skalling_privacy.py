"""External projects keep Skalling in local Git metadata, never shared config."""
from contextlib import closing
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile

PATHS = ('.opencode', 'db/teamdb', '.skalling-backups', '.codegraph')
START = '# --- Skalling: modo externo local ---'
END = '# --- fin Skalling local ---'
LEGACY = (
    ('# --- Skalling: artefactos locales (gestionado por setup.sh, no editar a mano) ---', '# --- fin Skalling (setup) ---'),
    ('# --- Skalling: merge de memoria (gestionado por setup.sh, no editar a mano) ---', '# --- fin Skalling (setup) ---'),
    ('# --- Skalling: modo externo (gestionado por /skalling-privacy, no editar a mano) ---', '# --- fin Skalling ---'),
)
AGENT_MARKER = '# AGENTS.md — Índice de Skalling para este proyecto'


def git(project, *args, check=True):
    return subprocess.run(['git', '-C', str(project), *args], capture_output=True, check=check)


def root_path(value):
    path = Path(value).resolve()
    result = git(path, 'rev-parse', '--show-toplevel', check=False)
    return Path(os.fsdecode(result.stdout).strip()) if result.returncode == 0 else path


def git_path(project, *args):
    value = Path(os.fsdecode(git(project, 'rev-parse', *args).stdout).strip())
    return (project/value).resolve() if not value.is_absolute() else value


def database(project):
    result = git(project, 'rev-parse', '--git-common-dir', check=False)
    if result.returncode == 0:
        return git_path(project, '--git-common-dir').parent/'.opencode/context/team.db'
    return project/'.opencode/context/team.db'


def mode(project):
    local = git(project, 'config', '--local', '--get', 'skalling.privacyMode', check=False)
    if local.returncode == 0 and local.stdout.strip() in (b'external', b'internal'):
        return local.stdout.decode().strip()
    db = database(project)
    if db.is_file():
        with closing(sqlite3.connect(db.as_uri()+'?mode=ro', uri=True)) as conn:
            if not conn.execute("SELECT 1 FROM sqlite_master WHERE name='schema_meta'").fetchone():
                return 'sin-configurar'
            row = conn.execute("SELECT value FROM schema_meta WHERE key='privacy_mode'").fetchone()
            if row and row[0] in ('external', 'internal'):
                return row[0]
    return 'sin-configurar'


def candidate_problems(project, tree=None):
    args = ('ls-tree', '-r', '--name-only', '-z', tree, '--', *PATHS) if tree else ('ls-files', '-z', '--', *PATHS)
    problems = [os.fsdecode(p) for p in git(project, *args).stdout.split(b'\0') if p]
    for name in ('.gitignore', '.gitattributes', 'AGENTS.md'):
        blob = git(project, 'show', f'{tree}:{name}' if tree else f':{name}', check=False)
        if blob.returncode == 0 and any(marker.encode() in blob.stdout for marker in (*[s for s, _ in LEGACY], START, AGENT_MARKER)):
            problems.append(name + ' (contenido de Skalling)')
    return problems


def preflight(project):
    git(project, 'rev-parse', '--git-dir')  # External installation requires Git.
    problems = candidate_problems(project)
    if problems:
        raise ValueError('Privacidad externa incompleta: archivos rastreados; no se sobrescriben ni se retiran del índice: '+', '.join(problems))
    local = project/'.opencode'
    if local.exists() and any(local.iterdir()) and not (local/'context/team.db').is_file() and not (local/'runtime-manifest.json').is_file():
        raise ValueError('.opencode ya contiene configuración ajena; se conserva. Usa la instalación global o una copia separada del proyecto.')
    # Do not replace a repository's custom hooks directory with Skalling files.
    hooks = git(project, 'config', '--get', 'core.hooksPath', check=False)
    if hooks.returncode == 0 and hooks.stdout.strip():
        raise ValueError('core.hooksPath personalizado: no se instala encima; integrar primero la protección local sin modificar hooks compartidos.')


def strip_block(data, start, end):
    pattern = rb'(?m)^' + re.escape(start.encode()) + rb'\r?\n.*?^' + re.escape(end.encode()) + rb'(?:\r?\n|$)'
    return re.sub(pattern, b'', data, flags=re.S)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.skalling-privacy-')
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(data)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def clean_legacy(project):
    changes = []
    for name in ('.gitignore', '.gitattributes'):
        path = project/name
        if not path.is_file():
            continue
        before = path.read_bytes()
        after = before
        for start, end in LEGACY:
            after = strip_block(after, start, end)
        if after == before:
            continue
        head = git(project, 'show', f'HEAD:{name}', check=False)
        if head.returncode == 0 and after.strip() == head.stdout.strip():
            after = head.stdout  # Recover original newlines, including the old appended blank line.
        changes.append((path, before, after, head.returncode == 0))
    if not changes:
        return
    backup = Path(tempfile.mkdtemp(prefix='skalling-privacy-backup-', dir=git_path(project, '--git-common-dir')))
    for path, before, after, tracked in changes:
        (backup/path.name).write_bytes(before)
        if not after.strip() and not tracked:
            path.unlink()
        else:
            write(path, after)
    print(f'Bloques antiguos retirados; respaldo local: {backup}', file=sys.stderr)


def record(project, selected):
    db = database(project)
    if db.is_file():
        import json
        subprocess.run([sys.executable, str(Path(__file__).with_name('teamdb_exec.py')), '--db', str(db),
                        '--mode', 'write', '--sql', "INSERT INTO schema_meta(key,value) VALUES('privacy_mode',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                        '--params', json.dumps([selected])], check=True, stdout=subprocess.DEVNULL)


def configure(project, selected):
    exclude = git_path(project, '--git-path', 'info/exclude')
    data = exclude.read_bytes() if exclude.exists() else b''
    clean = strip_block(data, START, END)
    if selected == 'external':
        block = (START+'\n'+'\n'.join('/'+p+'/' for p in PATHS)+'\n'+END+'\n').encode()
        clean = clean + (b'\n' if clean and not clean.endswith(b'\n') else b'') + block
    if clean != data:
        write(exclude, clean)
    git(project, 'config', '--local', 'skalling.privacyMode', selected)
    if selected == 'external':
        clean_legacy(project)
    record(project, selected)


def status(project):
    selected = mode(project)
    print('privacy_mode: '+selected)
    if selected != 'external':
        return 0
    problems = candidate_problems(project)
    for name in PATHS:
        if git(project, 'check-ignore', '--no-index', '-q', '--', name+'/skalling-probe', check=False).returncode != 0:
            problems.append(name+' (sin exclusión local efectiva)')
    for name in ('.gitignore', '.gitattributes', 'AGENTS.md'):
        path = project/name
        if path.is_file() and any(marker.encode() in path.read_bytes() for marker in (*[s for s, _ in LEGACY], AGENT_MARKER)):
            problems.append(name+' (restos locales de Skalling)')
    if problems:
        print('AVISO IMPORTANTE: Privacidad externa incompleta: '+', '.join(problems), file=sys.stderr)
        return 3
    print('protection: exclusiones locales verificadas; índice sin artefactos de Skalling. Historial remoto no verificado.')
    return 0


def main():
    action, value, *args = sys.argv[1:]
    project = root_path(value)
    if action == 'mode':
        print(mode(project))
    elif action == 'preflight':
        preflight(project)
    elif action == 'record':
        selected = mode(project)
        if selected in ('external', 'internal'):
            record(project, selected)
    elif action in ('external', 'internal'):
        configure(project, action)
        return status(project)
    elif action == 'status':
        return status(project)
    else:
        raise ValueError('Acción de privacidad desconocida')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, sqlite3.Error, subprocess.CalledProcessError) as error:
        sys.exit('ERROR: '+str(error))
