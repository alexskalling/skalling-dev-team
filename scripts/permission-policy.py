#!/usr/bin/env python3
"""Compose ordered OpenCode permissions from the canonical role policy (stdlib)."""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

# En Windows, stdout por defecto usa el codec del locale (cp1252), no UTF-8;
# render() puede imprimir tildes/emoji de los .md y rompe con UnicodeEncodeError.
# reconfigure() está disponible desde Python 3.7.
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')


def permissions(name):
    policy = json.loads((ROOT / 'data/permission-policy.json').read_text(encoding='utf-8'))
    profile = policy['profiles'][name]
    result = dict(profile['permissions'])
    result['bash'] = {p: profile['overrides'].get(p, policy['rules'][p])
                      for p in profile['bash_patterns']}
    return result


def yaml_mapping(mapping, depth=0):
    lines = []
    for key, value in mapping.items():
        label = key if re.fullmatch(r'[a-z_]+', key) else json.dumps(key, ensure_ascii=False)
        prefix = '  ' * depth + label + ':'
        if isinstance(value, dict):
            lines.append(prefix)
            lines.extend(yaml_mapping(value, depth + 1))
        else:
            lines.append(prefix + ' ' + str(value))
    return lines


def render(path):
    source = path.read_text(encoding='utf-8')
    if path.stem not in json.loads((ROOT / 'data/permission-policy.json').read_text(encoding='utf-8'))['profiles']:
        return source
    parts = source.split('---', 2)
    block = '\n'.join(yaml_mapping({'permission': permissions(path.stem)})) + '\n'
    parts[1], count = re.subn(r'(?m)^permission:\n(?:[ \t].*\n|\n)*', block, parts[1])
    if count != 1:
        raise ValueError('El agente debe tener un bloque permission: único')
    return '---'.join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    if args.render:
        print(render(args.render), end='')
        return
    failures = []
    for folder in ('agents-base', '.opencode/agents'):
        for path in sorted((ROOT / folder).glob('*.md')):
            expected = render(path)
            if expected != path.read_text(encoding='utf-8'):
                if args.write:
                    path.write_text(expected, encoding='utf-8')
                else:
                    failures.append(str(path.relative_to(ROOT)))
    for filename in ('templates/opencode.json', '.opencode/opencode.json'):
        path = ROOT / filename
        config = json.loads(path.read_text(encoding='utf-8'))
        if config['permission'] != permissions('project'):
            if args.write:
                config['permission'] = permissions('project')
                path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            else:
                failures.append(filename)
    if failures:
        sys.exit('Permisos divergentes; ejecutar permission-policy.py --write: ' + ', '.join(failures))


if __name__ == '__main__':
    main()
