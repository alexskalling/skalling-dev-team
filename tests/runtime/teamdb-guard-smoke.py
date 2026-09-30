"""Read a clean WAL TeamDB from the actual OpenCode runtime; no inference."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BINARY = shutil.which('opencode')
assert BINARY, 'This opt-in smoke test requires OpenCode'
with tempfile.TemporaryDirectory(prefix='skalling-teamdb-runtime-') as temporary:
    base = Path(temporary)
    config = base / 'config'
    (config / 'plugins').mkdir(parents=True)
    (base / '.git').mkdir()
    context = base / '.opencode/context'
    context.mkdir(parents=True)
    db_path = context / 'team.db'
    db = sqlite3.connect(db_path)
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('CREATE TABLE agent_workflows(id TEXT PRIMARY KEY, body TEXT)')
    for state in ('implementation_ready', 'rejected'):
        db.execute('INSERT INTO agent_workflows VALUES(?,?)', (state, json.dumps({'state': state})))
    db.commit()
    db.close()
    assert not Path(str(db_path) + '-wal').exists()
    before = hashlib.sha256(db_path.read_bytes()).hexdigest()
    plugin = '''import {writeFileSync} from 'node:fs';
import {teamdbWorkflowState,createCore} from MODULE;
export default {id:'teamdb-regression',setup:async()=>{
  const results={};
  const roles=createCore();
  results.pau_check=roles.decide({tool:'shell',agent:'Pau',input:{command:'pnpm vitest run --coverage'}});
  results.pau_commit=roles.decide({tool:'shell',agent:'Pau',input:{command:'git commit -m fix'}});
  results.alex_commit=roles.decide({tool:'shell',agent:'Alex',input:{command:'git commit -m fix'}});
  results.jhon_check=roles.decide({tool:'shell',agent:'Jhon',input:{command:'pnpm exec eslint modules/campanasModule'}});
  results.pau_dispatch=roles.decide({tool:'subagent',agent:'Alex',input:{agent:'Pau',description:'Pau corre checks pendientes'}});
  for(const id of ['implementation_ready','rejected']) {
    results[id]=teamdbWorkflowState(id,ROOT);
    const core=createCore();
    results[id+'_before_status']=core.decide({tool:'subagent',agent:'Alex',sessionID:id,directory:ROOT,input:{agent:'Teo',prompt:id}});
    core.observe({tool:'skalling_workflow',agent:'Alex',sessionID:id,output:JSON.stringify({id,state:'implementation_ready'})});
    results[id+'_gate']=core.decide({tool:'subagent',agent:'Alex',sessionID:id,directory:ROOT,input:{agent:'Teo',prompt:id}});
  }
  writeFileSync(OUTPUT,JSON.stringify(results));
}};'''.replace('MODULE', json.dumps(os.environ.get('SKALLING_GUARD_MODULE', str(ROOT/'plugins/lib/git-guard.mjs')))).replace('ROOT', json.dumps(temporary)).replace('OUTPUT', json.dumps(str(base/'result.json')))
    entry = config/'plugins/regression.js'
    entry.write_text(plugin)
    (config/'opencode.json').write_text(json.dumps({'plugins':[str(entry)]}))
    env = dict(os.environ, HOME=temporary, PWD=temporary, OPENCODE_CONFIG_DIR=str(config),
               XDG_CONFIG_HOME=str(base/'xdg'), XDG_DATA_HOME=str(base/'data'), XDG_CACHE_HOME=str(base/'cache'))
    # An unavailable synthetic model triggers plugin setup, then exits without a provider call.
    result = subprocess.run([BINARY,'run','--standalone','--model','fixture/missing','synthetic probe'],
                            cwd=temporary, env=env, capture_output=True, text=True, timeout=30)
    assert (base/'result.json').exists(), result.stderr[-2000:]
    results = json.loads((base/'result.json').read_text())
    assert results['implementation_ready'] == {'ok':True,'state':'implementation_ready'}, results
    assert 'skalling_workflow status' in results['implementation_ready_before_status'], results
    assert results['implementation_ready_gate'] is None, results
    assert results['rejected'] == {'ok':True,'state':'rejected'}, results
    for key in ('pau_check', 'pau_commit', 'pau_dispatch'):
        assert 'Pau documenta' in results[key] and 'Jhon' in results[key], results
    assert results['jhon_check'] is None, results
    assert 'se delega a Jhon o Luz' in results['alex_commit'], results
    assert 'rejected' in results['rejected_gate'], results
    assert hashlib.sha256(db_path.read_bytes()).hexdigest() == before, 'Guard modified database contents'
    print('PASS OpenCode: WAL intact; valid delegation and Jhon check allowed; rejected workflow and Pau engineering blocked')
