"""Real OpenCode agent merge: JSON overrides stale Markdown; no inference."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = shutil.which('opencode')
assert BINARY, 'OpenCode is required'
with tempfile.TemporaryDirectory(prefix='skalling-model-assignment-') as temporary:
    base = Path(temporary)
    config = base / 'config'
    (config / 'plugins').mkdir(parents=True)
    (config / 'agents').mkdir()
    (base / '.git').mkdir()
    (base / '.opencode/agents').mkdir(parents=True)
    (config / 'agents/Teo.md').write_text('---\nmode: subagent\nmodel: old/global\n---\nGlobal prompt\n')
    (base / '.opencode/agents/Teo.md').write_text('---\nmode: subagent\nmodel: old/project\n---\nProject prompt\n')
    (config / 'model-overrides.json').write_text(json.dumps({'Teo':'configured/chosen#high'}))
    entry = config / 'plugins/regression.js'
    entry.write_text('''import {writeFileSync} from 'node:fs';
export default {id:'model-assignment-regression',setup:async ctx=>{
  await ctx.session.hook('context',async()=>{writeFileSync(OUTPUT,JSON.stringify((await ctx.agent.get({agentID:'Teo'})).data));throw new Error('SYNTHETIC_STOP_BEFORE_INFERENCE');});
}};'''.replace('OUTPUT',json.dumps(str(base/'result.json'))))
    (config / 'opencode.json').write_text(json.dumps({'plugins':[str(entry)],'providers':{'fixture':{'package':'@opencode/ai/providers/openai-compatible','settings':{'baseURL':'http://127.0.0.1:1/v1','apiKey':'synthetic'},'models':{'missing':{'limit':{'context':100000,'output':1000}}}}}}))
    env = dict(os.environ, HOME=temporary, PWD=temporary, OPENCODE_CONFIG_DIR=str(config),
               SKALLING_OPENCODE_DIR=str(config), XDG_CONFIG_HOME=str(base/'xdg'),
               XDG_DATA_HOME=str(base/'data'), XDG_CACHE_HOME=str(base/'cache'),
               OPENCODE_DISABLE_MODELS_FETCH='1')
    subprocess.run(['bash',str(ROOT/'scripts/skalling-models.sh'),'apply','--project',temporary],
                   env=env,cwd=temporary,check=True,capture_output=True,text=True)
    result = subprocess.run([BINARY,'run','--standalone','--agent','Teo','--model','fixture/missing','synthetic probe'],
                            cwd=temporary,env=env,capture_output=True,text=True,timeout=30)
    assert (base/'result.json').exists(), result.stderr[-2500:]
    teo = json.loads((base/'result.json').read_text())
    assert teo.get('model') == {'providerID':'configured','id':'chosen','variant':'high'}, (teo,result.stderr[-2500:])
    assert 'Project prompt' in teo['system'], teo
    assert teo['mode'] == 'subagent', teo
    print('PASS OpenCode: JSON model wins over stale global and project agents; prompt and role preserved')
