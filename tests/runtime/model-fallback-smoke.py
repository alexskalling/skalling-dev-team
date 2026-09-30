"""Opt-in OpenCode 2.0.18 smoke test. Only a synthetic localhost provider is used."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[2]
BINARY = shutil.which('opencode')
assert BINARY, 'OpenCode is required for this opt-in smoke test'
calls = []
mode = os.environ.get('SKALLING_SMOKE_FAILURE', 'error')
backup_messages = []

class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        model = payload['model']
        calls.append(model)
        if model == 'backup':
            backup_messages.extend(payload.get('messages', []))
        tool_response = mode == 'tools' and len(calls) == 1
        if model == 'broken' and not tool_response:
            if mode == 'timeout':
                time.sleep(4)
                return
            if mode in ('error','tools'):
                self.send_response(503)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"error":{"message":"synthetic failure","type":"server_error"}}')
                return
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        content = '' if model == 'broken' else 'FALLBACK_OK'
        delta = {'role':'assistant','content':content}
        if tool_response:
            delta = {'role':'assistant','tool_calls':[{'index':0,'id':'checkpoint-1','type':'function','function':{'name':'checkpoint','arguments':'{}'}}]}
        for data in [
            {'id':'test','object':'chat.completion.chunk','model':model,'choices':[{'index':0,'delta':delta,'finish_reason':None}]},
            {'id':'test','object':'chat.completion.chunk','model':model,'choices':[{'index':0,'delta':{},'finish_reason':'tool_calls' if tool_response else 'stop'}]},
        ]:
            self.wfile.write(('data: '+json.dumps(data)+'\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n')

server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='skalling-fallback-runtime-') as tmp:
        base = Path(tmp)
        config = base/'config'
        (config/'agents').mkdir(parents=True)
        (config/'plugins/lib').mkdir(parents=True)
        shutil.copy(ROOT/'plugins/skalling-model-fallback.js', config/'plugins/skalling-model-fallback.js')
        shutil.copy(ROOT/'plugins/lib/model-fallback.mjs', config/'plugins/lib/model-fallback.mjs')
        (config/'agents/Teo.md').write_text('---\nmode: primary\ndescription: Synthetic failover test\n---\nReturn the synthetic result. Do not use tools.\n')
        (config/'plugins/checkpoint.js').write_text('''import { appendFileSync } from 'node:fs';
export default {id:'fixture-checkpoint',setup:async ctx=>ctx.tool.transform(tools=>tools.add({name:'checkpoint',options:{codemode:false},description:'Record checkpoint',input:{type:'object',properties:{}},execute:async()=>{appendFileSync(process.env.HOME+'/counter','1');return {content:'CHECKPOINT_RECORDED'};}}))};''')
        (config/'model-fallbacks.json').write_text(json.dumps({'Teo':{'models':['standby/backup'],'timeoutMs':2000,'chunkTimeoutMs':1000}}))
        (config/'opencode.json').write_text(json.dumps({
            'plugins':[str(config/'plugins/skalling-model-fallback.js')],
            'providers':{'fixture':{'package':'@opencode/ai/providers/openai-compatible',
                'settings':{'baseURL':f'http://127.0.0.1:{server.server_port}/v1','apiKey':'synthetic'},
                'models':{model:{'limit':{'context':100000,'output':1000}} for model in ['broken']}},'standby':{'package':'@opencode/ai/providers/openai-compatible','settings':{'baseURL':f'http://127.0.0.1:{server.server_port}/v1','apiKey':'synthetic-backup'},'models':{'backup':{'limit':{'context':100000,'output':1000}}}}},
        }))
        env = dict(os.environ, HOME=tmp, PWD=tmp, XDG_CONFIG_HOME=str(base/'xdg-config'),
                   XDG_DATA_HOME=str(base/'data'), XDG_CACHE_HOME=str(base/'cache'),
                   OPENCODE_CONFIG_DIR=str(config),SKALLING_OPENCODE_DIR=str(config),
                   OPENCODE_DISABLE_MODELS_FETCH='1')
        try:
            result = subprocess.run([BINARY,'run','--standalone','--agent','Teo','--model','fixture/broken',
                                 '--print-logs','--log-level','debug','--format','json','--title','Synthetic failover','Return FALLBACK_OK'],
                                cwd=tmp,env=env,capture_output=True,text=True,timeout=35)
        except subprocess.TimeoutExpired as error:
            logs = (error.stderr or b'').decode(errors='replace')
            relevant = '\n'.join(line for line in logs.splitlines() if any(k in line.lower() for k in ['plugin','fallback','error','failed']))
            raise AssertionError(f'calls={calls} logs={relevant}') from error
        assert result.returncode == 0, '\n'.join(line for line in result.stderr.splitlines() if any(k in line.lower() for k in ['fallback]', 'error', 'failed'])) + result.stdout[-3000:]
        assert 'FALLBACK_OK' in result.stdout, result.stdout[-3000:]+result.stderr[-3000:]
        assert calls == (['broken','broken','backup'] if mode == 'tools' else ['broken','backup']), calls
        if mode == 'tools':
            assert (base/'counter').read_text() == '1', 'tool replayed'
            assert 'CHECKPOINT_RECORDED' in json.dumps(backup_messages), 'tool result lost'
        print(f'PASS native OpenCode {mode}: broken -> backup, same execution, calls={calls}')
finally:
    server.shutdown()
    server.server_close()
