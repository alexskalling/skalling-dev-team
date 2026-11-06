import json, os, subprocess, tempfile, threading, shutil
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
root=Path(__file__).resolve().parents[2]
seen=[]
class Provider(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        seen.append(body)
        self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.end_headers()
        for delta,finish in [({'role':'assistant','content':'EFFICIENCY_OK'},None),({},'stop')]:
            data={'id':'fixture','object':'chat.completion.chunk','model':'fixture','choices':[{'index':0,'delta':delta,'finish_reason':finish}]}
            self.wfile.write(('data: '+json.dumps(data)+'\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n')
server=ThreadingHTTPServer(('127.0.0.1',0),Provider)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='efficiency-smoke-') as tmp:
        base=Path(tmp); config=base/'config'; config.mkdir()
        plugin_override = os.environ.get('SKALLING_EFFICIENCY_PLUGIN')
        # Exercise the same automatic discovery as the global installer.
        # Loading only an explicit package path used to hide a second .js entry.
        if not plugin_override:
            shutil.copytree(root/'plugins', config/'plugins')
        (config/'agents').mkdir()
        (config/'agents/Teo.md').write_text('---\nmode: primary\ndescription: Synthetic Skalling fixture\n---\nReturn EFFICIENCY_OK. Do not use tools.\n')
        settings = {'providers':{'fixture':{'package':'@opencode/ai/providers/openai-compatible','settings':{'baseURL':f'http://127.0.0.1:{server.server_port}/v1','apiKey':'synthetic'},'models':{'fixture':{'limit':{'context':100000,'output':1000}}}}}}
        if plugin_override:
            settings['plugins'] = [plugin_override]
        (config/'opencode.json').write_text(json.dumps(settings))
        env=dict(os.environ, HOME=tmp, PWD=tmp, XDG_CONFIG_HOME=str(base/'xdg'), XDG_DATA_HOME=str(base/'data'),XDG_CACHE_HOME=str(base/'cache'),OPENCODE_CONFIG_DIR=str(config),OPENCODE_DISABLE_MODELS_FETCH='1')
        for agent in ('build', 'plan', 'Teo'):
            seen.clear()
            run=subprocess.run([os.environ.get('OPENCODE_BINARY') or shutil.which('opencode'),'run','--standalone','--agent',agent,'--model','fixture/fixture','--print-logs','--log-level','debug','--format','json','Return EFFICIENCY_OK'],cwd=tmp,env=env,capture_output=True,text=True,timeout=40)
            assert run.returncode==0,run.stderr[-2000:]
            loads = [line for line in run.stderr.splitlines()
                     if 'loading plugin' in line and 'skalling-execution-efficiency' in line]
            assert len(loads) == 1, 'Expected one plugin load, found: ' + repr(loads)
            assert seen,run.stdout[-2000:]
            combined=json.dumps(seen,ensure_ascii=False)
            assert ('SKALLING_EXECUTION_EFFICIENCY' in combined) == (agent == 'Teo'), 'Wrong policy scope for '+agent
            assert combined.count('SKALLING_EXECUTION_EFFICIENCY') == int(agent == 'Teo'), 'Duplicate policy capsule'
            assert 'EFFICIENCY_OK' in run.stdout,run.stdout[-2000:]
            print('PASS: real OpenCode v2 / '+agent+': one plugin load; policy '+('present once' if agent == 'Teo' else 'absent')+'; local synthetic provider only.')
finally:
    server.shutdown(); server.server_close()
