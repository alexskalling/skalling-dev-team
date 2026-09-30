"""Skill inventory, conservative metadata validation, and replaceable registry cache."""
from contextlib import closing
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import sys
from skalling_config import scalar


def metadata(path):
    text = Path(path).read_text(encoding='utf-8')
    match = re.match(r'^---\s*\n(.*?)\n---(?:\s*\n|$)', text, re.S)
    if not match:
        raise ValueError(f'{path}: falta frontmatter')
    try:
        import yaml
    except ImportError:
        yaml = None
    if yaml:
        try:
            data = yaml.safe_load(match[1])
        except yaml.YAMLError as exc:
            raise ValueError(f'{path}: YAML inválido: {exc}') from exc
    else:
        # The installed runtime has no PyYAML dependency. Accept only metadata
        # scalars we can validate; do not silently accept ambiguous plain ': '.
        data = {}
        lines = match[1].splitlines()
        for index, line in enumerate(lines):
            field = re.match(r'^([\w-]+):\s*(.*)$', line)
            if not field:
                continue
            key, raw = field.groups()
            if key not in {'name', 'description', 'version'}:
                continue
            if raw in {'|', '>', '|-', '>-'}:
                body = []
                for follow in lines[index + 1:]:
                    if follow and not follow.startswith((' ', '\t')):
                        break
                    body.append(follow.strip())
                value = ' '.join(body).strip()
            else:
                if not raw.startswith(('"', "'")) and re.search(r':\s|[\[\]{}]|^[&*!]', raw):
                    raise ValueError(f'{path}: escalar YAML ambiguo en {key}; usar comillas')
                value = scalar(raw)
            data[key] = value
    if not isinstance(data, dict) or any(not isinstance(data.get(k), str) or not data[k].strip() for k in ('name', 'description')):
        raise ValueError(f'{path}: name y description deben ser texto no vacío')
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', data['name']):
        raise ValueError(f'{path}: nombre de skill inválido')
    return {k: data.get(k, '') for k in ('name', 'description', 'version')}


def inventory(directory):
    rows = []
    for path in sorted(Path(directory).glob('*/SKILL.md')):
        rows.append({**metadata(path), 'load_path': str(path.resolve()), 'source': 'project'})
    names = [row['name'] for row in rows]
    if len(names) != len(set(names)):
        raise ValueError(f'{directory}: nombres de skill duplicados')
    return rows


def sync_registry(db, rows, global_db=False):
    table, key = ('skills_active', 'skill_name') if global_db else ('skills_registry', 'name')
    # This table is an inventory cache, not durable memory. Replace atomically so
    # removed files/lock-only entries can never remain advertised as loadable.
    with closing(sqlite3.connect(db, timeout=10)) as conn:
        conn.execute('BEGIN IMMEDIATE')
        conn.execute(f'DELETE FROM {table}')
        conn.executemany(f'INSERT INTO {table}({key},description,version,source,load_path) VALUES(?,?,?,?,?)',
                         [(r['name'], r['description'], str(r['version']), r['source'], r['load_path']) for r in rows])
        conn.commit()


def catalog(root):
    path = next((p for p in (root/'data/skills-by-stack.yaml', root/'skalling-data/skills-by-stack.yaml') if p.is_file()), None)
    if path is None:
        raise ValueError('Falta catálogo skills-by-stack.yaml')
    sections, section, entry = {}, None, None
    for line in path.read_text(encoding='utf-8').splitlines():
        top = re.match(r'^([a-z_-]+):', line)
        item = re.match(r'^  - name:\s*(\S+)\s*$', line)
        field = re.match(r'^    (reason|install|optional):\s*(.*)$', line)
        if top:
            section = top[1]; sections[section] = []; entry = None
        elif item and section:
            entry = {'name': item[1]}; sections[section].append(entry)
        elif field and entry is not None:
            entry[field[1]] = scalar(field[2])
    if not sections.get('core'):
        raise ValueError('Catálogo sin core: no se puede verificar preparación')
    return sections


def digest(directory):
    h = hashlib.sha256()
    for p in sorted(Path(directory).rglob('*')):
        if p.is_file():
            h.update(str(p.relative_to(directory)).encode()); h.update(p.read_bytes())
    return h.hexdigest()


def repair(root, target):
    source = root / ('skills-base' if (root/'skills-base').is_dir() else 'skills')
    destination = target/'skills'; destination.mkdir(parents=True, exist_ok=True)
    manifest = destination/'.skalling-managed.json'
    hashes = json.loads(manifest.read_text(encoding='utf-8')) if manifest.exists() else {}
    legacy = root/('data' if (root/'data').is_dir() else 'skalling-data')/'skills-managed-legacy.json'
    allowed = json.loads(legacy.read_text(encoding='utf-8')) if legacy.exists() else {}
    preserved = []
    for entry in catalog(root)['core']:
        name = entry['name']; src, dst = source/name, destination/name
        if not src.is_dir():
            raise ValueError('Core ausente del bundle: ' + name)
        if name != '_shared':
            metadata(src/'SKILL.md')
        if dst.is_symlink() or (dst.exists() and any(p.is_symlink() for p in dst.rglob('*'))):
            raise ValueError('Skill administrada contiene symlink; revisar manualmente: ' + str(dst))
        if dst.is_dir():
            # Repair absent files without replacing any customized bytes.
            for original in src.rglob('*'):
                local = dst/original.relative_to(src)
                if original.is_file() and not local.exists():
                    local.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(original, local)
        current = digest(dst) if dst.exists() else None
        expected = digest(src)
        if current not in (None, expected, hashes.get(name), allowed.get(name)):
            preserved.append(name); continue
        if current != expected:
            if dst.is_symlink():
                raise ValueError('No sobrescribir symlink de skill: ' + str(dst))
            shutil.copytree(src, dst, dirs_exist_ok=True)
        hashes[name] = digest(dst)
    temporary = manifest.with_suffix('.tmp')
    temporary.write_text(json.dumps(hashes, indent=2)+'\n', encoding='utf-8'); temporary.replace(manifest)
    return preserved


def audit(root, project):
    rows, errors = [], []
    directory = project/'.opencode/skills'
    for path in sorted(directory.glob('*/SKILL.md')):
        try:
            rows.append({**metadata(path), 'load_path': str(path.resolve()), 'source': 'project'})
        except ValueError as exc:
            errors.append(str(exc))
    names = {r['name'] for r in rows}
    if len(names) != len(rows):
        errors.append('Nombres de skill duplicados')
    entries = catalog(root)
    # A syntactically valid but old managed skill is still drift. Customized
    # skills remain untouched and are reported separately.
    source = root / ('skills-base' if (root/'skills-base').is_dir() else 'skills')
    manifest = directory/'.skalling-managed.json'
    managed = json.loads(manifest.read_text(encoding='utf-8')) if manifest.is_file() else {}
    legacy_file = root/('data' if (root/'data').is_dir() else 'skalling-data')/'skills-managed-legacy.json'
    legacy = json.loads(legacy_file.read_text(encoding='utf-8')) if legacy_file.is_file() else {}
    drift, customized = [], []
    for entry in entries['core']:
        name = entry['name']
        src, dst = source/name, directory/name
        if src.is_dir() and dst.is_dir() and digest(src) != digest(dst):
            if (root/'skills-base').is_dir() and root.resolve() == project.resolve():
                drift.append(name)
            elif digest(dst) in {managed.get(name), legacy.get(name)}:
                drift.append(name)
            else:
                customized.append(name)
    missing = [e['name'] for e in entries['core'] if e['name'] != '_shared' and e['name'] not in names]
    if not (directory/'_shared').is_dir():
        missing.append('_shared (referencias compartidas)')
    db = project/'.opencode/context/team.db'
    registry = set()
    if db.exists():
        with closing(sqlite3.connect(db.as_uri()+'?mode=ro', uri=True)) as conn:
            registry = {r[0] for r in conn.execute('SELECT name FROM skills_registry')}
    else:
        errors.append('Falta TeamDB: registro sin verificar')
    # Inspect actual manifests, including nested modules, excluding generated trees.
    deps, signals = set(), set()
    excluded = {'.git','.opencode','node_modules','.venv','venv','dist','build','.next','coverage'}
    for base, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in excluded]
        if 'package.json' in files:
            data = json.loads((Path(base)/'package.json').read_text(encoding='utf-8'))
            deps.update(data.get('dependencies', {})); deps.update(data.get('devDependencies', {}))
        for file in ('pyproject.toml','requirements.txt'):
            if file in files:
                body = (Path(base)/file).read_text(encoding='utf-8')
                if re.search(r'\bpytest\b', body): signals.add('testing-pytest')
                if re.search(r'\bfastapi\b', body): signals.add('python-fastapi')
    for dep, key in [('next','nextjs'),('react','react'),('vue','vue'),('svelte','svelte'),('astro','astro'),('nuxt','nuxt'),('vitest','testing-vitest'),('@playwright/test','testing-e2e'),('playwright','testing-e2e')]:
        if dep in deps: signals.add(key)
    if signals & {'nextjs','react','vue','svelte','astro','nuxt'}: signals.add('frontend')
    available = set(names)
    global_warnings = []
    global_root = Path(os.environ.get('SKALLING_OPENCODE_DIR', str(Path.home()/'.config/opencode')))
    for folder in (global_root/'skills', Path(os.environ.get('AGENTS_SKILLS_DIR', str(Path.home()/'.agents/skills')))):
        for path in folder.glob('*/SKILL.md'):
            try:
                available.add(metadata(path)['name'])
            except ValueError as exc:
                global_warnings.append(str(exc))
    recommendations = {}
    for key in sorted(signals):
        for e in entries.get(key, []):
            if e['name'] not in available and e['name'] not in missing:
                recommendations[e['name']] = {**e, 'detected': key, 'action': 'recomendación; no instalada automáticamente'}
    return {'skills': len(rows), 'missing_core': missing, 'invalid': errors,
            'unregistered': sorted(names-registry), 'stale_registry': sorted(registry-names),
            'recommendations': list(recommendations.values()), 'global_skill_warnings': global_warnings,
            'managed_drift': drift, 'customized': customized,
            'ready': not (missing or errors or names != registry or drift)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['audit','repair','sync','check-core','check-parity'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--project', type=Path)
    parser.add_argument('--target', type=Path)
    args = parser.parse_args()
    if args.action == 'check-parity':
        source = args.root/'skills-base'
        drift = []
        for entry in catalog(args.root)['core']:
            name = entry['name']
            src, dst = source/name, args.target/'skills'/name
            if not src.is_dir() or not dst.is_dir() or digest(src) != digest(dst):
                drift.append(name)
            if dst.is_dir() and name != '_shared':
                metadata(dst/'SKILL.md')
        print(json.dumps({'skill_drift': drift}))
        return 1 if drift else 0
    if args.action == 'check-core':
        rows = inventory(args.target/'skills')
        names = {r['name'] for r in rows}
        missing = [e['name'] for e in catalog(args.root)['core'] if e['name'] != '_shared' and e['name'] not in names]
        if not (args.target/'skills/_shared').is_dir():
            missing.append('_shared')
        print(json.dumps({'missing_core': missing, 'valid_skills': len(rows)}))
        return 1 if missing else 0
    elif args.action == 'repair':
        preserved = repair(args.root.resolve(), args.target.resolve())
        print(json.dumps({'preserved_custom': preserved}, ensure_ascii=False))
    elif args.action == 'audit':
        result = audit(args.root.resolve(), args.project.resolve())
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result['ready'] else 1
    else:
        global_root = Path(os.environ.get('SKALLING_OPENCODE_DIR', str(Path.home()/'.config/opencode')))
        global_db = Path(os.environ.get('SKALLING_DB_GLOBAL', str(global_root/'team.db')))
        if global_db.exists():
            rows = {}
            for folder in (Path(os.environ.get('AGENTS_SKILLS_DIR', str(Path.home()/'.agents/skills'))), Path(os.environ.get('OPENCODE_SKILLS_DIR', str(global_root/'skills')))):
                for row in inventory(folder):
                    row['source'] = 'filesystem'; rows[row['name']] = row
            sync_registry(global_db, list(rows.values()), True)
        if args.project:
            project = args.project.resolve()
            sync_registry(project/'.opencode/context/team.db', inventory(project/'.opencode/skills'))
        print('Registro reconciliado con skills válidas y disponibles en disco.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, sqlite3.Error) as error:
        sys.exit('ERROR: skills sin verificar: ' + str(error))
