"""Bounded source inventory and explicit freshness for retrieved project memory."""
import hashlib
import json
from pathlib import Path

IGNORED = {'node_modules', 'dist', 'build', 'coverage', 'vendor', '__pycache__', 'venv'}
SOURCES = ('README.md', 'package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml',
           'Gemfile', 'composer.json', 'VERSION', '.opencode/project.yaml')


def modules(project):
    return sorted(p.name for p in Path(project).iterdir()
                  if p.is_dir() and not p.is_symlink() and not p.name.startswith('.')
                  and p.name not in IGNORED)


def source_fingerprint(project):
    project = Path(project)
    digest = hashlib.sha256(json.dumps(modules(project)).encode())
    for name in SOURCES:
        path = project / name
        digest.update(name.encode())
        if path.is_file() and not path.is_symlink():
            digest.update(path.read_bytes())
    return digest.hexdigest()


def freshness(conn, project):
    rows = dict(conn.execute("SELECT key,value FROM schema_meta WHERE key='bootstrap.sources' "
                             "OR key LIKE 'bootstrap.pending.%'"))
    recorded = rows.get('bootstrap.sources')
    pending = sorted(k.removeprefix('bootstrap.pending.') for k in rows if k.startswith('bootstrap.pending.'))
    return {'status': ('unknown' if not recorded else
                       'current' if recorded == source_fingerprint(project) else 'stale'),
            'pending_review': pending}


def memory_item(table, item, body_key, seen=()):
    """A caller may omit a body only when it already holds this exact revision."""
    identity = hashlib.sha256(json.dumps(item, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    token = f"{table}:{item['slug']}:{identity}"
    item['read_key'] = token
    if token in seen:
        item.pop(body_key, None)
        item['already_read'] = True
    return item
