#!/usr/bin/env python3
"""Config de OpenCode del proyecto (.opencode/opencode.json) que Skalling exige.

- default_agent: Alex (el punto de entrada, no el `build` nativo).
- build, plan y general deshabilitados: editan sin clasificación, sin Teo y
  sin verificación (auditoría v0.12.0). explore queda: es de solo lectura.
- permission: la política de proyecto (data/permission-policy.json). Antes
  solo existía como config GLOBAL y se instalaba únicamente si no había una:
  los cambios de permisos no llegaban a instalaciones existentes.

- comandos de tests del proyecto: los de testing.unit/testing.fast de
  .opencode/project.yaml quedan permitidos para Teo, Jhon y Luz del proyecto.
  En OpenCode las reglas se aplican global → proyecto → agente y gana la
  última: un allow en la config del proyecto lo pisaba el `"python3 *": ask`
  del agente, y cada corrida de tests pedía permiso. Solo comandos simples
  (sin encadenar, redirigir ni sustituir): project.yaml viaja por git.

Mezcla sin pisar el resto de la config del usuario.

Uso: skalling-project-config.py <proyecto> [--check | --remove]
  --remove  (desinstalación) devuelve build/plan/general y el agente por
            defecto de OpenCode; conserva los permisos, que solo restringen.
"""
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DISABLED = ('build', 'plan', 'general')
TEST_AGENTS = ('Teo', 'Jhon', 'Luz')
BEGIN = '    # skalling: comandos de tests del proyecto (inicio)'
END = '    # skalling: comandos de tests del proyecto (fin)'
UNSAFE = re.compile(r'[;&|<>`$\n\r\\]|\b(?:rm|sudo|curl|wget|ssh|scp|chmod|chown|dd|mkfs|eval|git\s+push)\b')


def configured_commands(project):
    """testing.unit/testing.fast disponibles de project.yaml (mismo parser que
    skalling-verify.sh y el motor). {files} se convierte en comodín."""
    path = project / '.opencode/project.yaml'
    if not path.is_file():
        return []
    text = path.read_text(encoding='utf-8')
    commands = []
    for name in ('unit', 'fast'):
        match = re.search(r'(?m)^[ \t]+' + name + r':[ \t]*\n((?:[ \t]{3,}\S.*\n?)*)', text)
        block = match.group(1) if match else ''
        available = re.search(r'available:\s*(\w+)', block)
        command = re.search(r'command:\s*(.*)', block)
        if available and available.group(1).lower() == 'true' and command:
            value = command.group(1).strip().strip('"\'').replace('{files}', '*').strip()
            if value and not UNSAFE.search(value) and value not in commands:
                commands.append(value)
    return commands


def rules_for(commands):
    rules = []
    for command in commands:
        for pattern in (command, command.rstrip(' *') + ' *'):
            line = f'    {json.dumps(pattern, ensure_ascii=False)}: allow'
            if line not in rules:
                rules.append(line)
    # Líneas propias de comentario (no al final de una regla: el parser de
    # permisos del plugin v2 ignoraría la regla entera).
    return [BEGIN, *rules, END] if rules else []


def patched_agent(text, rules):
    """Reemplaza las líneas marcadas por las vigentes, al FINAL del bloque bash
    del frontmatter (gana la última regla que coincide)."""
    if not text.startswith('---\n'):
        return text
    head, sep, rest = text[4:].partition('\n---\n')
    if not sep:
        return text
    lines = head.split('\n')
    if BEGIN in lines and END in lines and lines.index(BEGIN) < lines.index(END):
        del lines[lines.index(BEGIN):lines.index(END) + 1]
    if '  bash:' not in lines:
        return text
    end = lines.index('  bash:') + 1
    while end < len(lines) and lines[end].startswith('    '):
        end += 1
    lines[end:end] = rules
    return '---\n' + '\n'.join(lines) + sep + rest


def test_command_drift(project):
    rules = rules_for(configured_commands(project))
    drift = []
    for name in TEST_AGENTS:
        path = project / '.opencode/agents' / f'{name}.md'
        if path.is_file():
            text = path.read_text(encoding='utf-8')
            if patched_agent(text, rules) != text:
                drift.append(name)
    return drift


def apply_test_commands(project, remove=False):
    rules = [] if remove else rules_for(configured_commands(project))
    for name in TEST_AGENTS:
        path = project / '.opencode/agents' / f'{name}.md'
        if path.is_file():
            text = path.read_text(encoding='utf-8')
            patched = patched_agent(text, rules)
            if patched != text:
                path.write_text(patched, encoding='utf-8')


def policy_permissions():
    # Repo: data/. Instalación global: ~/.config/opencode/skalling-data/.
    for candidate in (ROOT / 'data/permission-policy.json', ROOT / 'skalling-data/permission-policy.json'):
        if candidate.is_file():
            policy = json.loads(candidate.read_text(encoding='utf-8'))
            profile = policy['profiles']['project']
            result = dict(profile['permissions'])
            result['bash'] = {p: profile['overrides'].get(p, policy['rules'][p]) for p in profile['bash_patterns']}
            return result
    raise SystemExit('ERROR: no se encontró data/permission-policy.json')


def expected(config):
    merged = dict(config)
    merged['default_agent'] = 'Alex'
    agents = dict(merged.get('agent') or {})
    for name in DISABLED:
        agents[name] = {**(agents.get(name) or {}), 'disable': True}
    merged['agent'] = agents
    merged['permission'] = policy_permissions()
    merged.setdefault('$schema', 'https://opencode.ai/config.json')
    return merged


def removed(config):
    cleaned = dict(config)
    if cleaned.get('default_agent') == 'Alex':
        cleaned.pop('default_agent')
    agents = dict(cleaned.get('agent') or {})
    for name in DISABLED:
        entry = dict(agents.get(name) or {})
        if entry.get('disable') is True:
            entry.pop('disable')
        if entry:
            agents[name] = entry
        else:
            agents.pop(name, None)
    if agents:
        cleaned['agent'] = agents
    else:
        cleaned.pop('agent', None)
    return cleaned


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    project, check = Path(sys.argv[1]), '--check' in sys.argv[2:]
    path = project / '.opencode/opencode.json'
    try:
        current = json.loads(path.read_text(encoding='utf-8')) if path.is_file() else {}
    except json.JSONDecodeError as error:
        raise SystemExit(f'ERROR: {path} no es JSON válido ({error}); corregirlo antes de continuar')
    if '--remove' in sys.argv[2:]:
        if path.is_file():
            path.write_text(json.dumps(removed(current), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        apply_test_commands(project, remove=True)
        print(f'OK: {path} sin overrides de agentes de Skalling')
        return
    wanted = expected(current)
    if check:
        missing = [key for key in ('default_agent', 'agent', 'permission') if current.get(key) != wanted[key]]
        if test_command_drift(project):
            missing.append('comandos de tests en ' + ', '.join(test_command_drift(project)))
        if missing:
            print('DRIFT: ' + ', '.join(missing))
            sys.exit(1)
        print('OK')
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(wanted, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    apply_test_commands(project)
    print(f'OK: {path}')


if __name__ == '__main__':
    main()
