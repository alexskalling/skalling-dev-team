"""Record and compare managed runtime bytes without reading project memory."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

REQUIRED = ('plugins/lib/context-budget.mjs', 'plugins/lib/execution-efficiency.mjs',
            'plugins/skalling-execution-efficiency/index.js', 'plugins/skalling-execution-efficiency/package.json',
            'scripts/skalling-workflow.py', 'scripts/skalling_skills.py', 'scripts/skalling_db.py', 'scripts/skalling_budget.py', 'scripts/skalling_memory_relations.py',
            'scripts/skalling-refresh.sh', 'scripts/skalling-project-root.py',
            'scripts/skalling-codegraph.sh', 'scripts/skalling-coverage-run.py',
            'scripts/skalling_process.py', 'scripts/skalling_models.py', 'scripts/skalling_privacy.py', 'plugins/skalling-workflow.js',
            'plugins/skalling-git-guard.js', 'plugins/skalling-query-memory.js',
            'plugins/lib/query-memory.mjs', 'scripts/skalling_review_cycle.py', 'scripts/skalling-node-diagnostic.py', 'hooks/git-gate.py')


def version(path):
    match = re.search(r'\d+\.\d+\.\d+', path.read_text()) if path.is_file() else None
    return match[0] if match else None


def files(target):
    return {str(p.relative_to(target)): hashlib.sha256(p.read_bytes()).hexdigest()
            for folder in ('scripts', 'plugins', 'hooks', 'command')
            for p in (target/folder).rglob('*')
            if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc'}


def source_fingerprint(root):
    """Identify the build inputs, even when VERSION has not been bumped."""
    if not (root/'agents-base').is_dir():
        manifest = root/'runtime-manifest.json'
        if not manifest.is_file():
            return None
        saved = json.loads(manifest.read_text())
        actual = files(root)
        if any(actual.get(name) != sha for name, sha in saved.get('files', {}).items()):
            return None
        return saved.get('source_fingerprint')
    inputs = [p for folder in ('scripts', 'plugins', 'command', 'agents-base', 'templates', 'skills-base', 'data', 'sql')
              for p in (root/folder).rglob('*')
              if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc']
    inputs += [root/name for name in ('VERSION', 'install-global.sh', 'setup.sh', 'bootstrap-context.sh', 'constitucion.md')
               if (root/name).is_file()]
    digest = hashlib.sha256()
    for path in sorted(inputs):
        digest.update(str(path.relative_to(root)).encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def check(root, target):
    path = target/'runtime-manifest.json'
    if not path.is_file():
        return {'ready': False, 'reason': 'runtime local sin inventario; ejecutar setup.sh --target <proyecto>'}
    saved = json.loads(path.read_text())
    actual = files(target)
    changed = [name for name, sha in saved['files'].items() if actual.get(name) != sha]
    required = (*REQUIRED, *(str(p.relative_to(root)) for p in (root/'command').glob('skalling-*.md')))
    missing = [name for name in required if name not in actual or name not in saved['files']]
    # A recorded inventory must not certify the old duplicate entrypoint.
    retired = [name for name in ('plugins/skalling-execution-efficiency.js',) if name in actual]
    expected, installed = version(root/'VERSION'), version(target/'VERSION')
    source = source_fingerprint(root)
    source_matches = bool(source and saved.get('source_fingerprint') == source)
    return {'ready': bool(expected and installed == expected and saved.get('version') == expected and not changed and not missing and not retired and source_matches),
            'expected': expected, 'installed': installed, 'changed_or_missing': changed,
            'source_matches': source_matches, 'expected_source': source,
            'installed_source': saved.get('source_fingerprint'),
            'missing_required': missing, 'retired_plugins': retired,
            'scope': 'scripts, plugins, hooks y comandos; modelos/personalizaciones se verifican por separado'}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['record','check'])
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--target', type=Path, required=True)
    a = p.parse_args()
    if a.action == 'record':
        (a.target/'VERSION').write_bytes((a.root/'VERSION').read_bytes())
        result = {'version': version(a.root/'VERSION'), 'source_fingerprint': source_fingerprint(a.root),
                  'files': files(a.target)}
        (a.target/'runtime-manifest.json').write_text(json.dumps(result, indent=2)+'\n')
    else:
        result = check(a.root, a.target)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result['ready'] else 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as exc:
        sys.exit('ERROR: runtime sin verificar: ' + str(exc))
