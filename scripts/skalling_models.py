"""Validate and stage model assignments before replacing any managed file."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time

ROLES = ('Alex', 'Jes', 'Jhon', 'Luz', 'Pau', 'Pol', 'Sol', 'Teo')
MODEL_ID = re.compile(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_./:-]+(?:#[A-Za-z0-9_.-]+)?')
HEADER = re.compile(r'\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)', re.S)


def project_root(value):
    path = Path(value).resolve(strict=True)
    if not path.is_dir():
        raise ValueError(f'El proyecto no es un directorio: {path}')
    result = subprocess.run(['git', '-C', str(path), 'rev-parse', '--show-toplevel'],
                            capture_output=True, text=True)
    if result.returncode == 0:
        return Path(result.stdout.strip()).resolve()
    # Non-Git projects can also be configured from a nested working directory.
    return next((p for p in (path, *path.parents) if (p/'.opencode/agents').is_dir()), path)


def validate_model(model):
    if not isinstance(model, str) or not MODEL_ID.fullmatch(model):
        raise ValueError('Modelo inválido: usa proveedor/modelo obtenido de opencode models')


def read_overrides(path):
    data = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    if not isinstance(data, dict):
        raise ValueError('model-overrides.json debe ser un objeto')
    return data


def render_agent(raw, model, path):
    text = raw.decode('utf-8')
    header = HEADER.match(text)
    if not header:
        if text.startswith('---'):
            raise ValueError(f'Frontmatter sin cierre válido: {path}')
        return (f'---\nmodel: {model}\n---\n' + text).encode('utf-8') if model else raw
    # Validate YAML when the optional parser is available, as in skill auditing.
    try:
        import yaml
    except ImportError:
        yaml = None
    if yaml:
        try:
            metadata = yaml.safe_load(header[1])
        except yaml.YAMLError as error:
            raise ValueError(f'Frontmatter inválido: {path}: {error}') from error
        if metadata is not None and not isinstance(metadata, dict):
            raise ValueError(f'Frontmatter no es un mapa: {path}')
    newline = '\r\n' if text.startswith('---\r\n') else '\n'
    lines = [line for line in header[1].splitlines() if not re.match(r'^model:', line)]
    if model:
        lines.append(f'model: {model}')
    return ('---' + newline + newline.join(lines) + newline + '---' + newline + text[header.end():]).encode('utf-8')


@contextmanager
def assignment_lock(config):
    """Serialize CLI writers, including read-modify-write of the shared JSON."""
    with (config/'.model-overrides.lock').open('a+b') as lock:
        if os.name == 'nt':
            import msvcrt
            if lock.tell() == 0:
                lock.write(b'0'); lock.flush()
            lock.seek(0)
            acquire = lambda: msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            release = lambda: msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            acquire = lambda: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            release = lambda: fcntl.flock(lock, fcntl.LOCK_UN)
        deadline = time.monotonic() + 10
        while True:
            try:
                acquire()
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise ValueError('Hay otra configuración de modelos en curso; no se modificó la asignación')
                time.sleep(.05)
        try:
            yield
        finally:
            release()


def staged_file(path, contents, mode):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.models-')
    temporary = Path(name)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        temporary.chmod(mode)
        return temporary
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def commit_files(changes):
    """Stage all bytes and rollback copies before publication; JSON is last.

    Revert completed replacements on an I/O error. This is not a multi-file
    filesystem transaction against power loss or SIGKILL.
    """
    staged, backups, published = {}, {}, []
    try:
        for path, (before, after, mode) in changes.items():
            staged[path] = staged_file(path, after, mode)
            if before is not None:
                backups[path] = staged_file(path, before, mode)
        try:
            for path, temporary in staged.items():
                os.replace(temporary, path)
                published.append(path)
        except BaseException as error:
            failures = []
            for path in reversed(published):
                try:
                    if path in backups:
                        os.replace(backups[path], path)
                    else:
                        path.unlink()
                except OSError:
                    failures.append(f'{path} (respaldo: {backups.get(path)})')
            if failures:
                # Preserve recovery bytes if the OS also rejects rollback.
                for path in published:
                    backups.pop(path, None)
                raise OSError('No se pudo revertir: ' + ', '.join(failures)) from error
            raise
    finally:
        for temporary in (*staged.values(), *backups.values()):
            temporary.unlink(missing_ok=True)


def change(config, project, action, args):
    if action == 'set' and len(args) == 2:
        name, model = args
        validate_model(model)
        targets = (name,)
    elif action == 'reset' and len(args) <= 1:
        targets = tuple(args) or ROLES
    elif action == 'apply' and not args:
        targets = ROLES
    else:
        raise ValueError('Uso: set Agente proveedor/modelo | reset [Agente] | apply [--project ruta]')
    if any(name not in ROLES for name in targets):
        raise ValueError('Agente desconocido; usa: ' + ', '.join(ROLES))
    if not (config/'agents').is_dir():
        raise ValueError(f'No hay agentes instalados en {config}')
    overrides = (config/'model-overrides.json').resolve()
    with assignment_lock(config):
        data = read_overrides(overrides)
        if action == 'set':
            data[args[0]] = args[1]
        elif action == 'reset':
            for name in targets:
                data.pop(name, None)
        for name, model in data.items():
            if name not in ROLES:
                raise ValueError(f'Agente desconocido en model-overrides.json: {name}')
            validate_model(model)
        directories = [config/'agents']
        local = project/'.opencode/agents'
        if local.is_dir() and not (project/'agents-base').is_dir() and local.resolve() != directories[0].resolve():
            directories.append(local)
        changes = {}
        for directory in directories:
            for name in targets:
                path = (directory/f'{name}.md').resolve()
                if not path.is_file():
                    if directory == directories[0] and (name in data or len(targets) == 1):
                        raise ValueError(f'Agente no instalado: {path}')
                    continue
                before = path.read_bytes()
                after = render_agent(before, data.get(name), path)
                if after != before:
                    changes[path] = (before, after, stat.S_IMODE(path.stat().st_mode))
        if action != 'apply':
            before = overrides.read_bytes() if overrides.exists() else None
            after = (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
            if before != after:
                changes[overrides] = (before, after, stat.S_IMODE(overrides.stat().st_mode) if overrides.exists() else 0o600)
        commit_files(changes)
    print('Configuración aplicada. Reinicia OpenCode para cargarla.')


def show(config, project):
    data = read_overrides(config/'model-overrides.json')
    def model_at(path):
        if not path.is_file():
            return None
        header = HEADER.match(path.read_text(encoding='utf-8'))
        match = re.search(r'(?m)^model:\s*(.+)$', header[1]) if header else None
        return match[1].strip() if match else '(default de la sesión)'
    for name in ROLES:
        current = model_at(config/'agents'/f'{name}.md')
        if current is None:
            print(f'{name:<6} (no instalado)')
            continue
        desired = data.get(name)
        drift = ' [JSON; archivo global desactualizado: ejecutar apply]' if desired and desired != current else ''
        local = model_at(project/'.opencode/agents'/f'{name}.md')
        note = f' | proyecto={local}' if local is not None else ' | sin override local'
        print(f'{name:<6} {desired or current}{drift}{note}')
    print('Configuración en disco; disponibilidad del proveedor y modelo de la sesión activa no verificados.')


def main(argv):
    config, project, action, *args = argv
    if action == 'apply' and len(args) == 2 and args[0] == '--project':
        project, args = args[1], []
    project = project_root(project)
    config = Path(config).resolve()
    if action == 'show' and not args:
        show(config, project)
    else:
        change(config, project, action, args)


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (OSError, ValueError) as error:
        sys.exit(f'ERROR: {error}')
