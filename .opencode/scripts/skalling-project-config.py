#!/usr/bin/env python3
"""Config de OpenCode del proyecto (.opencode/opencode.json) que Skalling exige.

- default_agent: Alex (el punto de entrada, no el `build` nativo).
- build, plan y general deshabilitados: editan sin clasificación, sin Teo y
  sin verificación (auditoría v0.12.0). explore queda: es de solo lectura.
- permission: la política de proyecto (data/permission-policy.json). Antes
  solo existía como config GLOBAL y se instalaba únicamente si no había una:
  los cambios de permisos no llegaban a instalaciones existentes.

- comandos de tests del proyecto: los disponibles en testing de
  .opencode/project.yaml quedan permitidos para Teo, Jhon y Luz del proyecto.
  En OpenCode las reglas se aplican global → proyecto → agente y gana la
  última: un allow en la config del proyecto lo pisaba el `"python3 *": ask`
  del agente, y cada corrida de tests pedía permiso. Solo comandos simples
  (sin encadenar, redirigir ni sustituir): project.yaml viaja por git.
- commits locales: repone la política canónica de Teo/Jhon/Luz también en
  cabeceras locales mínimas, que reemplazan las globales. No habilita push.

Mezcla sin pisar el resto de la config del usuario.

Uso: skalling-project-config.py <proyecto> [--check | --remove | --sync-agents]
  --sync-agents actualiza los prompts locales con backup; conserva sus cabeceras.
  --remove devuelve build/plan/general y el agente por defecto de OpenCode;
           retira los bloques de permisos propios de las cabeceras locales.
"""
import json
import hashlib
import datetime
import os
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from skalling_config import TESTING_KINDS, testing_config  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
DISABLED = ('build', 'plan', 'general')
TEST_AGENTS = ('Teo', 'Jhon', 'Luz')
ALL_AGENTS = ('Alex', 'Pol', 'Jes', 'Sol', 'Teo', 'Jhon', 'Luz', 'Pau')
COMMAND_BEGIN = '    # skalling: comandos de mantenimiento del rol (inicio)'
COMMAND_END = '    # skalling: comandos de mantenimiento del rol (fin)'
BEGIN = '    # skalling: comandos de tests del proyecto (inicio)'
END = '    # skalling: comandos de tests del proyecto (fin)'
COMMIT_BEGIN = '    # skalling: commits locales del rol (inicio)'
COMMIT_END = '    # skalling: commits locales del rol (fin)'
UNSAFE = re.compile(r'[;&|<>`$\n\r\\]|\b(?:rm|sudo|curl|wget|ssh|scp|chmod|chown|dd|mkfs|eval|git\s+push)\b')


def agent_body(text):
    if text.startswith('---\n') and '\n---\n' in text[4:]:
        return text[4:].split('\n---\n', 1)[1]
    return text


def agent_sources():
    directory = ROOT / ('.opencode/agents' if (ROOT / 'agents-base').is_dir() else 'agents')
    return [directory / (name + '.md') for name in ('Alex', 'Pol', 'Sol', 'Teo', 'Jhon', 'Luz', 'Pau', 'Jes')]


def sync_agents(project, force=False, check=False):
    """Update managed bodies; preserve headers/models and back up every change.

    A custom body is reported, never silently replaced during normal updates.
    --sync-agents explicitly adopts the installed protocol after backing it up.
    """
    if (project / 'agents-base').is_dir():
        return []
    target = project / '.opencode/agents'
    manifest = target / '.skalling-sync.json'
    hashes = json.loads(manifest.read_text(encoding='utf-8')) if manifest.is_file() else {}
    drift = []
    for source in agent_sources():
        path = target / source.name
        if not source.is_file() or not path.is_file():
            continue  # Projects without a local override inherit the global agent.
        old = path.read_text(encoding='utf-8')
        body = agent_body(old)
        wanted = agent_body(source.read_text(encoding='utf-8'))
        digest = hashlib.sha256(body.encode()).hexdigest()
        if body == wanted:
            if not check:
                hashes[source.name] = digest
            continue
        if check or not (force or hashes.get(source.name) == digest):
            drift.append(source.stem)
            continue
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup = project / '.opencode/.skalling-backups/agents' / stamp / source.name
        backup.parent.mkdir(parents=True, exist_ok=True)
        backup.write_text(old, encoding='utf-8')
        header = old[:-len(body)] if body else old
        if not header:
            rendered = source.read_text(encoding='utf-8')
            header = rendered[:-len(wanted)] if wanted else rendered
        # Refuse to overwrite an editor's concurrent change.
        if path.read_text(encoding='utf-8') != old:
            raise SystemExit(f'ERROR: {path} cambió durante la sincronización; reintentar')
        temporary = path.with_suffix('.md.skalling-tmp')
        temporary.write_text(header + wanted, encoding='utf-8')
        os.replace(temporary, path)
        hashes[source.name] = hashlib.sha256(wanted.encode()).hexdigest()
    if not check and target.is_dir():
        manifest.write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')
    return drift


def configured_commands(project):
    """Comandos de testing disponibles de project.yaml (parser único:
    skalling_config). {files} se convierte en comodín."""
    # El repo fuente de Skalling genera sus .opencode/agents desde
    # agents-base (render-agent.sh): tocarlos rompería la paridad.
    if (project / 'agents-base').is_dir():
        return []
    config = testing_config(project / '.opencode/project.yaml')
    commands = []
    for name in TESTING_KINDS:
        value = config.get(name, '').replace('{files}', '*').strip()
        if value and not UNSAFE.search(value) and value not in commands:
            commands.append(value)
            # pnpm permite omitir `run` para scripts test:*; ambos nombres
            # deben tener el mismo permiso, sin autorizar `pnpm run *`.
            alias = re.fullmatch(r'pnpm (?:run )?(test:[\w:.-]+)(.*)', value)
            if alias and (not alias[2] or alias[2].startswith(' ')):
                for prefix in ('pnpm ', 'pnpm run '):
                    equivalent = prefix + alias[1] + alias[2]
                    if equivalent not in commands:
                        commands.append(equivalent)
    return commands + local_verification_commands(project, commands)


def local_verification_commands(project, commands):
    """Allow local binaries, never package downloads or arbitrary exec.

    pnpm's shorthand prefers package scripts over binaries: only grant it
    when there is no colliding script. Other managers keep explicit commands
    from project.yaml until their local-only invocation is supported.
    """
    if not any(command.startswith('pnpm ') for command in commands):
        return []
    try:
        package = json.loads((project / 'package.json').read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return []
    if not isinstance(package, dict):
        return []
    dependencies = set()
    for field in ('dependencies', 'devDependencies'):
        if isinstance(package.get(field), dict):
            dependencies.update(package[field])
    scripts = package.get('scripts') or {}
    result = []
    for tool, suffix in (('vitest', ' run'), ('eslint', '')):
        if tool not in dependencies:
            continue
        result.append(f'pnpm exec {tool}{suffix}')
        if isinstance(scripts, dict) and tool not in scripts:
            result.append(f'pnpm {tool}{suffix}')
    return result


def rules_for(commands, readonly=False):
    rules = []
    for command in commands:
        for pattern in (command, command.rstrip(' *') + ' *'):
            line = f'    {json.dumps(pattern, ensure_ascii=False)}: allow'
            if line not in rules:
                rules.append(line)
    if readonly:
        for command in commands:
            options = ('--fix', '--output-file', '-o') if command.endswith(' eslint') else (
                ('--update', '-u') if command.endswith(' vitest run') else ())
            for option in options:
                rules.append(f'    {json.dumps(command + " *" + option + "*")}: deny')
    # Líneas propias de comentario (no al final de una regla: el parser de
    # permisos del plugin v2 ignoraría la regla entera).
    return [BEGIN, *rules, END] if rules else []


def patched_agent(text, rules, begin=BEGIN, end_marker=END):
    """Reemplaza las líneas marcadas por las vigentes, al FINAL del bloque bash
    del frontmatter (gana la última regla que coincide)."""
    if not text.startswith('---\n'):
        # Instalaciones antiguas tienen solo el cuerpo del prompt. Antes se
        # omitían silenciosamente, incluso en --check: nunca recibían permisos.
        if not rules:
            return text
        return '---\npermission:\n  bash:\n' + '\n'.join(rules) + '\n---\n' + text
    head, sep, rest = text[4:].partition('\n---\n')
    if not sep:
        return text
    shadow = '    # skalling: shadowed rule '
    lines = [json.loads(line[len(shadow):]) if line.startswith(shadow) else line
             for line in head.split('\n')]
    if begin in lines and end_marker in lines and lines.index(begin) < lines.index(end_marker):
        del lines[lines.index(begin):lines.index(end_marker) + 1]
        if not rules and lines == ['permission:', '  bash:']:
            return rest
    if '  bash:' not in lines:
        if not rules:
            return text
        scalar = next((i for i, line in enumerate(lines) if re.fullmatch(r'  bash: (allow|ask|deny)', line)), None)
        if scalar is not None:
            effect = lines[scalar].split(': ')[1]
            lines[scalar:scalar + 1] = ['  bash:', f'    "*": {effect}']
        elif 'permission:' in lines:
            lines[lines.index('permission:') + 1:lines.index('permission:') + 1] = ['  bash:']
        elif any(line.startswith('permission:') for line in lines):
            return text  # Preserve an explicit scalar permission policy.
        else:
            lines += ['permission:', '  bash:']
    end = lines.index('  bash:') + 1
    while end < len(lines) and lines[end].startswith('    '):
        end += 1
    lines[end:end] = rules
    # YAML mappings cannot repeat keys. OpenCode otherwise treats the entire
    # frontmatter as prompt text and silently loses role permissions/models.
    # Keep the LAST occurrence in its original position (permission precedence).
    start = lines.index('  bash:') + 1
    end = start
    while end < len(lines) and lines[end].startswith('    '):
        end += 1
    seen = set()
    kept = []
    for line in reversed(lines[start:end]):
        match = re.fullmatch(r'    ("(?:[^"\\]|\\.)*"|[^:#][^:]*):\s*(allow|ask|deny)\s*', line)
        if match:
            key = json.loads(match[1]) if match[1].startswith('"') else match[1].strip()
            if key in seen:
                kept.append(shadow + json.dumps(line))
                continue
            seen.add(key)
        kept.append(line)
    lines[start:end] = reversed(kept)
    return '---\n' + '\n'.join(lines) + sep + rest


def local_commit_rules(name):
    policy = permission_policy()
    profile = policy['profiles'][name]
    patterns = [p for p in profile['bash_patterns'] if re.match(r'^git (?:-C \* )?(?:add|commit)(?: |$)', p)]
    return [COMMIT_BEGIN, *[f'    {json.dumps(p)}: {profile["overrides"].get(p, policy["rules"][p])}'
                           for p in patterns], COMMIT_END]


def patched_project_agent(text, commands, name, project, remove=False):
    if name in TEST_AGENTS:
        text = patched_agent(text, [] if remove else rules_for(commands, readonly=name != 'Teo'))
        rules = [] if remove or (project / 'agents-base').is_dir() else local_commit_rules(name)
        text = patched_agent(text, rules, COMMIT_BEGIN, COMMIT_END)
    policy = permission_policy()
    profile = policy['profiles'][name]
    helpers = ('skalling-refresh.sh', 'teamdb-status.sh', 'teamdb-resume.sh', 'mem-review.sh',
               'merge-helper.sh', 'skalling-metrics.sh', 'skalling-models.sh', 'skalling-privacy.sh',
               'setup-team-doctor.sh', 'bootstrap-context.sh')
    patterns = [p for p in profile['bash_patterns'] if p.startswith('bash ') and any(h in p for h in helpers)]
    # Cabeceras antiguas pueden anular las lecturas permitidas globalmente.
    # Son conteos exactos, nunca xargs * ni find -exec arbitrario.
    patterns.extend(policy.get('audit_read_patterns', []))
    rules = [] if remove or (project / 'agents-base').is_dir() else [COMMAND_BEGIN, *[
        f'    {json.dumps(p)}: {profile["overrides"].get(p, policy["rules"][p])}' for p in patterns], COMMAND_END]
    return patched_agent(text, rules, COMMAND_BEGIN, COMMAND_END)


def test_command_drift(project):
    commands = configured_commands(project)
    drift = []
    for name in ALL_AGENTS:
        path = project / '.opencode/agents' / f'{name}.md'
        if path.is_file():
            text = path.read_text(encoding='utf-8')
            if patched_project_agent(text, commands, name, project) != text:
                drift.append(name)
    return drift


def apply_test_commands(project, remove=False):
    commands = [] if remove else configured_commands(project)
    for name in ALL_AGENTS:
        path = project / '.opencode/agents' / f'{name}.md'
        if path.is_file():
            text = path.read_text(encoding='utf-8')
            patched = patched_project_agent(text, commands, name, project, remove)
            if patched != text:
                path.write_text(patched, encoding='utf-8')


def permission_policy():
    # Repo: data/. Instalación global: ~/.config/opencode/skalling-data/.
    for candidate in (ROOT / 'data/permission-policy.json', ROOT / 'skalling-data/permission-policy.json'):
        if candidate.is_file():
            return json.loads(candidate.read_text(encoding='utf-8'))
    raise SystemExit('ERROR: no se encontró data/permission-policy.json')


def policy_permissions():
    policy = permission_policy()
    profile = policy['profiles']['project']
    return {**profile['permissions'], 'bash': {
        p: profile['overrides'].get(p, policy['rules'][p]) for p in profile['bash_patterns']}}


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
            missing.append('permisos de verificación/commit en ' + ', '.join(test_command_drift(project)))
        drift = sync_agents(project, check=True)
        if drift:
            missing.append('protocolo de agentes: ' + ', '.join(drift) + ' (usar --sync-agents; conserva backup)')
        if missing:
            print('DRIFT: ' + ', '.join(missing))
            sys.exit(1)
        print('OK')
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(wanted, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    drift = sync_agents(project, force='--sync-agents' in sys.argv[2:])
    if drift:
        print('DRIFT: prompts locales preservados: ' + ', '.join(drift) + '; --sync-agents los actualiza con backup')
    apply_test_commands(project)
    print(f'OK: {path}')


if __name__ == '__main__':
    main()
