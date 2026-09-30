"""Real OpenCode merge of minimal project agents and managed commit permissions.

Stops before inference; does not call a provider or modify the user's Git repo.
The workflow-engine suite separately exercises Git commits with active hooks.
"""
import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = shutil.which('opencode')
assert BINARY, 'This opt-in test requires OpenCode'
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('project_config', ROOT / 'scripts/skalling-project-config.py')
config_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config_module)

with tempfile.TemporaryDirectory(prefix='skalling-local-commit-') as temporary:
    base = Path(temporary)
    config = base / 'config'
    (config / 'plugins').mkdir(parents=True)
    (base / '.git').mkdir()
    agents = base / '.opencode/agents'
    agents.mkdir(parents=True)
    installed = os.environ.get('SKALLING_INSTALLED_AGENTS')
    for name in ('Alex', 'Teo', 'Jhon', 'Luz', 'Pau'):
        if installed:
            shutil.copyfile(Path(installed) / f'{name}.md', agents / f'{name}.md')
        else:
            (agents / f'{name}.md').write_text('---\nmode: subagent\n---\nFixture prompt\n', encoding='utf-8')
    if not installed:
        config_module.apply_test_commands(base)
    (base / '.opencode/opencode.json').write_text(json.dumps({'permission': config_module.policy_permissions()}))
    entry = config / 'plugins/regression.js'
    entry.write_text('''import {writeFileSync} from 'node:fs';
export default {id:'local-commit-regression',setup:async ctx=>{
  await ctx.session.hook('context',async()=>{
    const result={};
    for(const agentID of ['Alex','Teo','Jhon','Luz','Pau']) result[agentID]=(await ctx.agent.get({agentID})).data;
    writeFileSync(OUTPUT,JSON.stringify(result));
    throw new Error('SYNTHETIC_STOP_BEFORE_INFERENCE');
  });
}};'''.replace('OUTPUT', json.dumps(str(base / 'result.json'))))
    (config / 'opencode.json').write_text(json.dumps({'plugins': [str(entry)], 'providers': {'fixture': {
        'package': '@opencode/ai/providers/openai-compatible',
        'settings': {'baseURL': 'http://127.0.0.1:1/v1', 'apiKey': 'synthetic'},
        'models': {'missing': {'limit': {'context': 100000, 'output': 1000}}}}}}))
    env = dict(os.environ, HOME=temporary, PWD=temporary, OPENCODE_CONFIG_DIR=str(config),
               SKALLING_OPENCODE_DIR=str(config), XDG_CONFIG_HOME=str(base / 'xdg'),
               XDG_DATA_HOME=str(base / 'data'), XDG_CACHE_HOME=str(base / 'cache'),
               OPENCODE_DISABLE_MODELS_FETCH='1')
    run = subprocess.run([BINARY, 'run', '--standalone', '--agent', 'Teo', '--model', 'fixture/missing', 'probe'],
                         cwd=temporary, env=env, capture_output=True, text=True, timeout=30)
    assert (base / 'result.json').exists(), run.stderr[-2000:]
    result = json.loads((base / 'result.json').read_text())
    def decision(agent, command):
        effect = 'ask'
        for rule in agent['permissions']:
            pattern = '.*'.join(re.escape(part) for part in rule['resource'].split('*'))
            if rule['action'] in ('shell', '*') and re.fullmatch(pattern, command):
                effect = rule['effect']
        return effect
    for name in ('Teo', 'Jhon', 'Luz'):
        for command in ('git add app.py', 'git commit -m fix', 'git commit --no-edit', 'git -C . commit -m fix'):
            assert decision(result[name], command) == 'allow', (name, command)
        for command in ('git push origin main', 'git commit --amend -m fix'):
            assert decision(result[name], command) == 'ask', (name, command)
    assert decision(result['Pau'], 'git commit -m fix') == 'ask'
    for name in ('Alex', 'Teo', 'Jhon', 'Luz', 'Pau'):
        command = 'bash /Users/example/.config/opencode/scripts/skalling-refresh.sh --check /work'
        assert decision(result[name], command) == 'allow', (name, command)
        command = command.replace('--check', '--apply')
        assert decision(result[name], command) == ('allow' if name == 'Alex' else 'ask'), (name, command)
    print('PASS OpenCode native: Teo/Jhon/Luz local commits allowed; push and amend ask; Pau not promoted')
    print('PASS OpenCode native: all roles can inspect refresh; only Alex can apply maintenance')
