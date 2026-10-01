"""Opt-in: real Alex/model, real TeamDB, simulated read-only Cloudflare MCP.

Runs in an isolated repo without remote. No real Cloudflare data or deployment.
Checks memory-first retrieval, current evidence, no delegation/workflow/edit,
memory delivered before any tool, maximum three tool calls and a bounded run. Provider usage is real.
"""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sqlite3
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[2]
GLOBAL = Path.home() / '.config/opencode'
root = Path(tempfile.mkdtemp(prefix='skalling-query-'))
print('Fixture:', root, flush=True)
runtime = root / '.opencode'
runtime.mkdir()
for name, origin in [('agents', GLOBAL / 'agents'), ('scripts', SOURCE / '.opencode/scripts'),
                     ('plugins', SOURCE / 'plugins')]:
    shutil.copytree(origin, runtime / name, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
(root / '.gitignore').write_text('.opencode/\n', encoding='utf-8')
(root / 'README.md').write_text('# Fixture de consulta de estado\n', encoding='utf-8')
for args in (['init', '-q'], ['config', 'user.name', 'Query fixture'],
             ['config', 'user.email', 'fixture@example.invalid'], ['add', '.'], ['commit', '-qm', 'fixture']):
    subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)
subprocess.run(['bash', str(SOURCE / 'scripts/teamdb-init.sh'), str(root)], check=True, capture_output=True)
with sqlite3.connect(runtime / 'context/team.db') as db:
    db.execute("INSERT INTO concepts(slug,title,body_md,updated_at) VALUES(?,?,?,?)",
               ('cloudflare-deployment', 'Cloudflare despliegue', 'Worker helios-prod en account fixture-account. '
                'Se despliega con Wrangler. Última versión registrada legacy-7. Para estado ACTUAL, '
                'consultar cloudflare_fixture_worker_status con account_id y script_name. Registro histórico, '
                'no confirma despliegue actual ni integración con Git.', '2025-09-01'))
    db.commit()
    before = db.iterdump()
    baseline = '\n'.join(before)
shutil.copy2(SOURCE / 'templates/opencode.json', runtime / 'opencode.json')
subprocess.run(['python3', str(SOURCE / 'scripts/skalling-project-config.py'), str(root)], check=True, capture_output=True)
(runtime / 'plugins/query-fixture.js').write_text('''import {appendFileSync} from 'node:fs';
export default {id:'query-fixture',setup:async ctx=>{
  await ctx.tool.transform(tools=>tools.add({
    name:'cloudflare_fixture_worker_status', options:{codemode:false},
    description:'MCP Cloudflare simulado de esta prueba: consultar estado ACTUAL del Worker identificado en TeamDB. Solo lectura.',
    input:{type:'object',properties:{account_id:{type:'string'},script_name:{type:'string'}},
           required:['account_id','script_name'],additionalProperties:false},
    execute:async input=>{
      if(input.account_id!=='fixture-account'||input.script_name!=='helios-prod') throw new Error('Wrong resource');
      appendFileSync(LOG,JSON.stringify(input)+'\\n');
      return {content:JSON.stringify({worker:'helios-prod',platform:'Cloudflare Workers',
        deployment:{version:'live-42',source:'wrangler'},url:'https://helios.example.invalid',
        git_integration:'not inspected'})};
    }
  }));
}};
'''.replace('LOG', json.dumps(str(runtime / 'live-calls.jsonl'))), encoding='utf-8')
header = (GLOBAL / 'agents/Alex.md').read_text(encoding='utf-8').split('---', 2)[1]
model = re.search(r'^model:\s*(\S+)\s*$', header, re.MULTILINE).group(1).strip('"\'')
request = ('Usa el MCP Cloudflare simulado disponible en esta prueba y dime cómo está desplegado '
           'este proyecto ahora. Sólo quiero la explicación de estado, sin modificar ni desplegar nada.')
started = time.monotonic()
with (runtime / 'events.jsonl').open('w') as out, (runtime / 'stderr.log').open('w') as err:
    process = subprocess.Popen(['opencode', 'run', '--standalone', '--agent', 'Alex', '--model', model,
                                '--format', 'json', '--title', 'Consulta de estado con memoria', request],
                               cwd=root, env={**os.environ, 'PWD': str(root)}, stdout=out, stderr=err,
                               start_new_session=True)
    try:
        code = process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGINT)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise AssertionError('Query exceeded 90s: ' + str(runtime)) from None
assert code == 0, (code, runtime)
events = [json.loads(line) for line in (runtime / 'events.jsonl').read_text().splitlines()]
calls = [e['part'] for e in events if e['type'] == 'tool_use']
assert 1 <= len(calls) <= 3, [(p.get('tool'), p.get('state', {}).get('input')) for p in calls]
# Resource identifiers exist only in TeamDB: using them on the FIRST tool proves
# the runtime supplied memory before inference, without a model-driven lookup.
assert calls[0]['tool'] == 'cloudflare_fixture_worker_status', 'Memory must precede exploration'
assert calls[0]['state']['input'] == {'account_id': 'fixture-account', 'script_name': 'helios-prod'}
assert sum(p['tool'] == 'cloudflare_fixture_worker_status' for p in calls) == 1
assert all(p['tool'] not in ('subagent', 'skalling_workflow', 'patch', 'edit', 'write', 'question') for p in calls)
answer = '\n'.join(e['part']['text'] for e in events if e['type'] == 'text')
assert 'live-42' in answer and 'helios-prod' in answer, answer
assert len((runtime / 'live-calls.jsonl').read_text().splitlines()) == 1
with sqlite3.connect(runtime / 'context/team.db') as db:
    assert '\n'.join(db.iterdump()) == baseline, 'Query changed memory/workflow state'
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=root), 'Query modified project'
print(json.dumps({'elapsed_seconds': round(time.monotonic() - started, 1), 'tools': len(calls),
                  'model': model, 'cloudflare': 'simulated read-only MCP', 'answer': answer}, ensure_ascii=False))
