"""Commit one verified unit without consuming another task's staging area."""
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def path_identity(root, name):
    path = root / name
    if not path.parent.resolve().is_relative_to(root):
        return None
    if path.is_symlink():
        return 'link:' + os.readlink(path)
    if not path.exists():
        return 'absent'
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return f'{path.stat().st_mode & 0o111}:{digest.hexdigest()}'


def git(root, *args, env=None):
    result = subprocess.run(['git', *args], cwd=root, env=env, capture_output=True, timeout=180)
    if result.returncode:
        raise ValueError(f'git {args[0]} falló: ' + result.stderr.decode('utf-8', 'replace')[-2000:])
    return result.stdout


def head_revision(root):
    result = subprocess.run(['git', 'rev-parse', '--verify', 'HEAD'], cwd=root, capture_output=True, timeout=10)
    return result.stdout.decode().strip() if result.returncode == 0 else None


@contextmanager
def isolated_index(root, files):
    # The real index remains untouched. Git hooks inherit this index and inspect
    # precisely the candidate whose receipt the workflow seals.
    with tempfile.TemporaryDirectory(prefix='skalling-commit-') as temporary:
        index = Path(temporary) / 'candidate'
        env = {**os.environ, 'GIT_INDEX_FILE': str(index)}
        head = head_revision(root)
        git(root, 'read-tree', head or '--empty', env=env)
        tracked = set(git(root, 'ls-files', '-z', env=env).decode().split('\0'))
        selected = [name for name in files if (root/name).exists() or name in tracked]
        if selected:
            git(root, 'add', '-A', '--', *[':(literal)' + name for name in selected], env=env)
        yield env, head, Path(temporary)


def commit_unit(root, files, message, validate, seal):
    if not isinstance(message, str) or not message.strip() or '\0' in message:
        raise ValueError('Commit requires a nonempty message')
    index_path = Path(git(root, 'rev-parse', '--git-path', 'index').decode().strip())
    if not index_path.is_absolute():
        index_path = root / index_path
    lock = Path(str(index_path) + '.lock')
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise ValueError('Git index ocupado; reintentar cuando termine la otra operación. No borrar el lock') from None
    os.close(descriptor)
    try:
        with isolated_index(root, files) as (env, head, temporary):
            validate()
            tree = git(root, 'write-tree', env=env).decode().strip()
            if not git(root, 'diff', '--cached', '--name-only', env=env).strip():
                return {'sha': head, 'created': False}
            # The hook opens its own DB connection: commit the genuine receipt
            # before invoking Git, never hold a TeamDB write lock across a hook.
            seal(env)
            validate()
            if head_revision(root) != head:
                raise ValueError('HEAD cambió al preparar el commit; reintentar sobre el estado vigente')
            git(root, 'commit', '-m', message, env=env)
            sha = git(root, 'rev-parse', 'HEAD').decode().strip()
            if git(root, 'rev-parse', 'HEAD^{tree}').decode().strip() != tree:
                raise ValueError(f'Un hook cambió el candidato; commit {sha} requiere revisión. No repetir ni publicar')
            # Preserve every foreign index entry, including partially staged
            # bytes. Only the committed files advance to the new HEAD.
            restored = temporary / 'restored'
            if index_path.exists():
                shutil.copyfile(index_path, restored)
            restore_env = {**os.environ, 'GIT_INDEX_FILE': str(restored)}
            if not restored.exists():
                git(root, 'read-tree', head or '--empty', env=restore_env)
            git(root, 'reset', '-q', sha, '--', *[':(literal)' + name for name in files], env=restore_env)
            # Same-filesystem replacement also works for linked worktrees.
            shutil.copyfile(restored, lock)
            os.replace(lock, index_path)
            return {'sha': sha, 'created': True}
    finally:
        lock.unlink(missing_ok=True)
