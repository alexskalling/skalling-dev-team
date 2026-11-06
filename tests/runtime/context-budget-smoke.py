"""Native OpenCode compaction, isolated session and synthetic localhost provider."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[2]
calls = []
primary_calls = 0

class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        global primary_calls
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        kind = self.headers.get('x-fixture-kind', 'unknown')
        calls.append((kind, payload))
        if kind == 'primary':
            primary_calls += 1
        use_tool = kind == 'primary' and primary_calls <= 5
        if use_tool:
            delta = {'role': 'assistant', 'tool_calls': [{'index': 0, 'id': 'check-' + str(primary_calls), 'type': 'function',
                'function': {'name': 'checkpoint', 'arguments': '{}'}}]}
        else:
            summary = ('## Objective\n- Finish WORKFLOW_DEMO.\n\n## Requirements\n- Preserve user constraints.\n\n'
                       '## Decisions\n- Use existing workflow.\n\n## Work State\n### Completed\n- Evidence collected.\n'
                       '### Active\n- Finish current task.\n### Blocked\n- (none)\n\n## Next Move\n1. Finish task.\n\n'
                       '## Relevant Files\n- (none)\n\n## Important Context\n- WORKFLOW_DEMO remains active.\n')
            delta = {'role': 'assistant', 'content': summary if kind == 'compaction' else 'WORKFLOW_DEMO CONTEXT_OK'}
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        for item, finish in [(delta, None), ({}, 'tool_calls' if use_tool else 'stop')]:
            data = {'id': 'fixture', 'object': 'chat.completion.chunk', 'model': 'fixture',
                    'choices': [{'index': 0, 'delta': item, 'finish_reason': finish}]}
            self.wfile.write(('data: ' + json.dumps(data) + '\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n')

server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='skalling-context-smoke-') as tmp:
        base = Path(tmp)
        config = base/'config'
        (config/'agents').mkdir(parents=True)
        (config/'plugins/lib').mkdir(parents=True)
        for name in ('execution-efficiency.mjs', 'context-budget.mjs'):
            shutil.copy(ROOT/'plugins/lib'/name, config/'plugins/lib'/name)
        (config/'agents/Teo.md').write_text('---\nmode: primary\ndescription: Synthetic compaction test\n---\nPreserve WORKFLOW_DEMO and finish.\n')
        (config/'plugins/fixture.js').write_text('''import { appendFileSync } from 'node:fs';
import { setupEfficiency } from './lib/execution-efficiency.mjs';
export default { id:'context-fixture', setup:async ctx => {
  if (typeof ctx.session.compact !== 'function') throw Error('Native compact missing');
  await ctx.session.hook('http.request', e => e.request.headers.set('x-fixture-kind',e.kind));
  await ctx.tool.transform(tools => tools.add({name:'checkpoint',options:{codemode:false},description:'Synthetic evidence',input:{type:'object',properties:{}},execute:async()=>({content:'evidence '.repeat(2500)})}));
  return setupEfficiency({...ctx, session:{...ctx.session, compact:async input=>{appendFileSync(process.env.HOME+'/compact-count','1'); return ctx.session.compact(input);}}, options:{contextTokens:16000}});
}};''')
        (config/'opencode.json').write_text(json.dumps({'compaction': {'auto': False, 'keep': {'tokens': 1000}},
            'providers': {'fixture': {'package': '@opencode/ai/providers/openai-compatible',
                'settings': {'baseURL': f'http://127.0.0.1:{server.server_port}/v1', 'apiKey': 'synthetic'},
                'models': {'fixture': {'limit': {'context': 1000000, 'output': 1000}}}}}}))
        env = dict(os.environ, HOME=tmp, PWD=tmp, XDG_CONFIG_HOME=str(base/'xdg'), XDG_DATA_HOME=str(base/'data'),
                   XDG_CACHE_HOME=str(base/'cache'), OPENCODE_CONFIG_DIR=str(config), OPENCODE_DISABLE_MODELS_FETCH='1')
        run = subprocess.run([shutil.which('opencode'), 'run', '--standalone', '--agent', 'Teo', '--model', 'fixture/fixture',
                              '--title', 'Context fixture', '--print-logs', '--format', 'json',
                              'WORKFLOW_DEMO: finish without changing user constraints'],
                             cwd=tmp, env=env, capture_output=True, text=True, timeout=50)
        assert run.returncode == 0, run.stderr[-4000:] + run.stdout[-2000:]
        compact = [body for kind, body in calls if kind == 'compaction']
        assert (base/'compact-count').read_text() == '1', 'Plugin queued compaction repeatedly'
        assert compact, ([kind for kind, _ in calls], run.stderr[-3000:])
        assert 'TeamDB' in json.dumps(compact), 'Workflow recovery instructions missing'
        assert 'CONTEXT_OK' in run.stdout, run.stdout[-2000:]
        primary = [body for kind, body in calls if kind == 'primary']
        sizes = [len(json.dumps(body)) for body in primary]
        if sizes[-1] >= max(sizes) / 2:
            Path('/tmp/skalling-context-fixture.json').write_text(json.dumps({'calls': calls, 'stdout': run.stdout, 'stderr': run.stderr}))
        assert sizes[-1] < max(sizes) / 2, sizes
        assert 'WORKFLOW_DEMO' in json.dumps(primary[-1]), 'Goal lost'
        print('PASS: native compact queued once, task preserved, synthetic request bytes:', sizes)
finally:
    server.shutdown()
    server.server_close()
