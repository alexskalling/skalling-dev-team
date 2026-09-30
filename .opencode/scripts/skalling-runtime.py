"""Record and compare managed runtime bytes without reading project memory."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

REQUIRED = ('scripts/skalling-workflow.py', 'scripts/skalling_skills.py',
            'scripts/skalling-refresh.sh', 'plugins/skalling-workflow.js',
            'plugins/skalling-git-guard.js', 'hooks/git-gate.py')


def version(path):
    match = re.search(r'\d+\.\d+\.\d+', path.read_text()) if path.is_file() else None
    return match[0] if match else None


def files(target):
    return {str(p.relative_to(target)): hashlib.sha256(p.read_bytes()).hexdigest()
            for folder in ('scripts', 'plugins', 'hooks', 'command')
            for p in (target/folder).rglob('*')
            if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc'}


def check(root, target):
    path = target/'runtime-manifest.json'
    if not path.is_file():
        return {'ready': False, 'reason': 'runtime local sin inventario; ejecutar setup.sh --target <proyecto>'}
    saved = json.loads(path.read_text())
    actual = files(target)
    changed = [name for name, sha in saved['files'].items() if actual.get(name) != sha]
    required = (*REQUIRED, *(str(p.relative_to(root)) for p in (root/'command').glob('skalling-*.md')))
    missing = [name for name in required if name not in actual or name not in saved['files']]
    expected, installed = version(root/'VERSION'), version(target/'VERSION')
    return {'ready': bool(expected and installed == expected and saved.get('version') == expected and not changed and not missing),
            'expected': expected, 'installed': installed, 'changed_or_missing': changed,
            'missing_required': missing,
            'scope': 'scripts, plugins, hooks y comandos; modelos/personalizaciones se verifican por separado'}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['record','check'])
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--target', type=Path, required=True)
    a = p.parse_args()
    if a.action == 'record':
        (a.target/'VERSION').write_bytes((a.root/'VERSION').read_bytes())
        result = {'version': version(a.root/'VERSION'), 'files': files(a.target)}
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
