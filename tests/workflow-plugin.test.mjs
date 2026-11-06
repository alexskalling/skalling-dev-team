import test from 'node:test';
import assert from 'node:assert/strict';

test('typed inspection reaches the engine without granting arbitrary shell access', async () => {
  let received;
  const definition = await workflowDefinition(async request => { received = request; return {state:'verification_ready'}; });
  const context = {agent:'Jhon', sessionID:'jhon', signal:new AbortController().signal};
  const payload = {id:'review', inspection:{kind:'diff',files:['src/page.tsx']}, method:'diff', criterion:'only order changes',
    replacement_of:0, failure_kind:'invalid_check', evidence:'Use native inspection instead of forbidden child_process'};
  await definition.execute({action:'check',payload}, context);
  assert.deepEqual(received.payload, payload);
  for (const extra of [{argv:['touch','unexpected']}, {configured:true}]) {
    await assert.rejects(definition.execute({action:'check',payload:{...payload,...extra}},context), /no acepta/);
  }
  assert.ok(definition.input.properties.payload.anyOf || definition.input.properties.payload);
});

async function workflowDefinition(execute) {
  let definition;
  await setupWorkflowV2({location:{directory:'/project'}, tool:{transform: async cb => cb({add: t => {definition=t;}})}},
    execute, '/missing-agents/', '/missing-config');
  return definition;
}

test('read-only audits and missing request classification never start the implementation engine', async () => {
  const received = [];
  const definition = await workflowDefinition(async request => { received.push(request); return {state:'implementation_ready'}; });
  const context = {agent:'Alex', sessionID:'audit', signal:new AbortController().signal};
  for (const request_kind of [undefined, 'audit', 'research', 'query']) {
    const payload = {id:'audit-report', intent:'Auditar rendimiento sin modificar código', request_kind};
    for (const encoded of [payload, JSON.stringify(payload)]) {
      await assert.rejects(definition.execute({action:'start', payload:encoded},context), error => {
        assert.match(error.message, /request_kind:"code"/);
        assert.match(error.message, /Alex → Luz/);
        assert.match(error.message, /--kind audit --record/);
        return true;
      });
    }
  }
  assert.equal(received.length,0, 'classification failures cannot create or mutate a workflow');
  assert.deepEqual(definition.input.properties.payload.properties.request_kind.enum, ['code','audit','research','query']);
  assert.ok(definition.input.properties.payload.properties.kind.enum.includes('correction'), 'feedback kind retains its own contract');
});

test('explicit implementation after an audit is not blocked by audit wording or prior classification', async () => {
  const received = [];
  const definition = await workflowDefinition(async request => { received.push(request); return {state:'implementation_ready'}; });
  const context = {agent:'Alex', sessionID:'audit-then-fix', signal:new AbortController().signal};
  await assert.rejects(definition.execute({action:'start', payload:{id:'audit',request_kind:'audit'}},context));
  const payload = {id:'fix-audit',request_kind:'code',intent:'Corrige los hallazgos de la auditoría de rendimiento'};
  await definition.execute({action:'start',payload},context);
  assert.equal(received.length,1);
  assert.deepEqual(received[0].payload,payload);
  assert.equal(received[0].actor,'alex');
  assert.equal(received[0].session,context.sessionID);
  await definition.execute({action:'status',payload:{id:'legacy-workflow'}},context);
  await definition.execute({action:'feedback',payload:{id:'legacy-workflow',kind:'correction'}},context);
  assert.equal(received.length,3, 'existing workflows and feedback require no start classification');
});

test('recover is exposed to OpenCode with runtime identity and concrete repair payload', async () => {
  let received;
  const definition = await workflowDefinition(async request => { received = request; return {state:'implementation_ready'}; });
  assert.ok(definition.input.properties.action.enum.includes('recover'));
  const payload = {id:'blocked', feedback_id:'user-fix', evidence:'Observed blocker', recovery_plan:'Persist and verify row'};
  await definition.execute({action:'recover', payload},
    {agent:'Alex', sessionID:'alex-session', signal:new AbortController().signal});
  assert.equal(received.actor, 'alex');
  assert.deepEqual(received.payload, payload);
});

test('a running plugin reports its loaded bytes and detects an on-disk update', async () => {
  const { rmSync } = await import('node:fs');
  const { pathToFileURL } = await import('node:url');
  const temp = mkdtempSync(join(tmpdir(), 'skalling-plugin-identity-'));
  try {
    const path = join(temp, 'workflow.mjs');
    writeFileSync(path, readFileSync(new URL('../plugins/lib/workflow.mjs', import.meta.url)));
    const loaded = await import(pathToFileURL(path).href);
    let definition;
    await loaded.setupWorkflowV2({location:{directory:temp},tool:{transform:async cb=>cb({add:t=>{definition=t;}})}},
      async()=>({state:'implementation_ready',runtime:{backend_path:'/installed/scripts/skalling-workflow.py'}}));
    const context = {agent:'Alex',sessionID:'active',signal:new AbortController().signal};
    const first = JSON.parse((await definition.execute({action:'status',payload:{id:'x'}},context)).content);
    assert.equal(first.runtime.reload_required,false);
    assert.equal(first.runtime.backend_path,'/installed/scripts/skalling-workflow.py');
    writeFileSync(path, readFileSync(path,'utf8')+'\n// newer disk version\n');
    const second = JSON.parse((await definition.execute({action:'status',payload:{id:'x'}},context)).content);
    assert.equal(second.runtime.plugin_loaded_sha256,first.runtime.plugin_loaded_sha256);
    assert.notEqual(second.runtime.plugin_disk_sha256,second.runtime.plugin_loaded_sha256);
    assert.equal(second.runtime.reload_required,true);
    assert.equal(second.runtime.agent_prompt_loaded,'not_observable');
  } finally { rmSync(temp,{recursive:true,force:true}); }
});

test('resume needs no remembered id and uses only runtime session and project', async () => {
  let received;
  const definition = await workflowDefinition( async request => { received = request; return { recovery: 'no_active_workflow' }; });
  const result = await definition.execute({ action: 'resume', payload: '{}' },
    { agent: 'Alex', sessionID: 'resumed-session', directory: '/project', signal: new AbortController().signal,
      ask: async () => { throw new Error('Reading memory needs no shell approval'); } });
  assert.deepEqual(received.payload, {});
  assert.equal(received.session, 'resumed-session');
  assert.equal(received.project, '/project');
  assert.equal(JSON.parse(result.content).recovery, 'no_active_workflow');
});

test('actor, session and workspace are supplied by runtime, never model payload', async () => {
  let received;
  const definition = await workflowDefinition( async request => { received = request; return {}; });
  await assert.rejects(definition.execute({ action: 'complete', payload: JSON.stringify({id:'x', actor:'jhon'}) },
    {agent:'Teo', sessionID:'teo-session', directory:'/project', signal:new AbortController().signal}), /actor/);
  await definition.execute({ action: 'status', payload: '{"id":"x"}' },
    {agent:'Teo', sessionID:'teo-session', directory:'/project', signal:new AbortController().signal});
  assert.equal(received.actor, 'teo');
  assert.equal(received.session, 'teo-session');
  assert.equal(received.project, '/project');
});

test('verification refuses commands without an allowed policy before executing', async () => {
  let executed = false;
  const definition = await workflowDefinition(async () => { executed=true; return {}; });
  await assert.rejects(definition.execute({action:'check', payload:{id:'x', argv:['bash','tests/a.test.sh']}},
    {agent:'Jhon',sessionID:'jhon',signal:new AbortController().signal}), /permiso|aprobación/i);
  assert.equal(executed,false);
});

test('prepare_commit forwards runtime identity without asking for publication permission', async () => {
  let received;
  const definition = await workflowDefinition( async request => { received = request; return {state:'verified'}; });
  await definition.execute({action:'prepare_commit', payload:'{"id":"unit"}'}, {
    agent:'Jhon', sessionID:'jhon-s', directory:'/project', signal:new AbortController().signal,
    ask: async () => { throw new Error('Local commit preparation should not ask for publication permission'); },
  });
  assert.equal(received.action, 'prepare_commit');
  assert.equal(received.actor, 'jhon');
});

// OpenCode v2: sin context.ask; el check consulta la política compilada del agente.
import { readFileSync, mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { agentBashRules, setupWorkflowV2, decideRules, configBashRules } from '../plugins/lib/workflow.mjs';

test('decideRules lee el bloque bash compilado (última coincidencia gana)', () => {
  const jhon = readFileSync(new URL('../agents-base/Jhon.md', import.meta.url), 'utf8');
  assert.equal(decideRules(agentBashRules(jhon), 'npm test'), 'allow');
  assert.equal(decideRules(agentBashRules(jhon), 'bash tests/a.test.sh'), 'allow');
  assert.equal(decideRules(agentBashRules(jhon), 'curl https://x.com'), 'ask');
  assert.equal(decideRules(agentBashRules(jhon), 'sqlite3 team.db'), 'deny');
  assert.equal(decideRules(agentBashRules(''), 'npm test'), 'ask');
});

test('v2: check corre si la política del agente lo permite y se rechaza si pediría aprobación', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'agents-'));
  writeFileSync(join(dir, 'Jhon.md'), readFileSync(new URL('../agents-base/Jhon.md', import.meta.url), 'utf8'));
  const tools = [];
  const calls = [];
  await setupWorkflowV2({ location: { directory: '/project' },
    tool: { transform: async (cb) => { cb({ add: (t) => tools.push(t) }); return { dispose: async () => {} }; } } },
    async (request) => { calls.push(request); return { ok: true }; }, dir + '/', join(dir, 'no-global'));
  const [wf] = tools;
  const context = { agent: 'Jhon', sessionID: 'jhon-s', signal: new AbortController().signal };
  assert.ok(wf.input.properties.action.enum.includes('prepare_commit'));
  await wf.execute({ action: 'prepare_commit', payload: { id: 'unit' } }, context);
  assert.equal(calls.pop().action, 'prepare_commit');
  assert.ok(wf.input.properties.action.enum.includes('commit'));
  assert.ok(wf.input.properties.action.enum.includes('preserve_external'));
  await wf.execute({ action: 'commit', payload: { id: 'unit', message: 'fix: unidad verificada' } }, context);
  const committed = calls.pop();
  assert.equal(committed.actor, 'jhon');
  assert.equal(committed.action, 'commit');
  assert.equal(committed.payload.message, 'fix: unidad verificada');
  const ok = await wf.execute({ action: 'check', payload: JSON.stringify({ id: 'x', argv: ['npm', 'test'] }) }, context);
  assert.match(ok.content, /ok/);
  assert.equal(calls[0].actor, 'jhon');
  assert.equal(calls[0].project, '/project');
  await assert.rejects(wf.execute({ action: 'check', payload: JSON.stringify({ id: 'x', argv: ['curl', 'https://x.com'] }) }, context),
    /solo corre comandos que tu política ya permite/);
  await assert.rejects(wf.execute({ action: 'complete', payload: JSON.stringify({ id: 'x', actor: 'jhon' }) }, context), /actor/);
  // El comando que declara el proyecto (configured) no pide permiso y el
  // modelo no puede colar un argv propio por ese camino. El payload llega
  // como objeto (forma real de 2.0.x) o como string.
  const configured = await wf.execute({ action: 'check', payload: { id: 'x', configured: true, argv: ['curl', 'https://x.com'] } }, context);
  assert.match(configured.content, /ok/);
  assert.equal(calls.at(-1).payload.configured, true);
  assert.equal(calls.at(-1).payload.argv, undefined);
  assert.ok(wf.input.properties.action.enum.includes('probe'));
  const probe = await wf.execute({ action: 'probe', payload: { id: 'x' } }, { ...context, agent: 'Teo' });
  assert.match(probe.content, /ok/);
  assert.equal(calls.at(-1).actor, 'teo');
  assert.equal(calls.at(-1).action, 'probe');
  await assert.rejects(wf.execute({ action: 'probe', payload: { id: 'x', argv: ['curl', 'https://x.com'] } },
    { ...context, agent: 'Teo' }), /no acepta argv/);
  assert.equal(wf.options?.codemode, false);
  const privacy = await wf.execute({ action: 'check', payload: { id: 'x', argv: [
    'bash', '/Users/example/.config/opencode/scripts/skalling-privacy.sh', 'verify-internal', '/project'] } }, context);
  assert.match(privacy.content, /ok/);
  const beforeRejected = calls.length;
  await assert.rejects(wf.execute({ action: 'check', payload: { id: 'x', argv: [
    'python3', '-c', 'import subprocess; # check-ignore ' + 'x'.repeat(5000)] } }, context), error => {
    assert.match(error.message, /verify-internal/);
    assert.match(error.message, /código inline omitido/);
    assert.ok(error.message.length < 1200);
    return true;
  });
  assert.equal(calls.length, beforeRejected, 'Rejected inline code never reaches the engine');
});

test('auditoría A09: gana la ÚLTIMA regla que coincide, como en OpenCode', () => {
  assert.equal(decideRules([['npm test', 'allow'], ['*', 'deny']], 'npm test'), 'deny');
  assert.equal(decideRules([['*', 'deny'], ['npm test', 'allow']], 'npm test'), 'allow');
  assert.equal(decideRules([], 'npm test'), 'ask');
  assert.deepEqual(configBashRules('{"permission":{"bash":"deny"}}'), [['*', 'deny']]);
  assert.deepEqual(configBashRules('no json'), []);
  // opencode.jsonc con comentarios y coma final
  assert.deepEqual(configBashRules('{ // global\n "$schema": "https://opencode.ai/config.json", /* x */ "permission": {"bash": {"rm *": "ask",}}}'),
    [['rm *', 'ask']]);
  // formato nativo v2
  assert.deepEqual(configBashRules(JSON.stringify({ permissions: [
    { action: 'edit', resource: '*', effect: 'deny' },
    { action: 'shell', resource: '*', effect: 'allow' },
    { action: 'shell', resource: 'git push *', effect: 'ask' }] })), [['*', 'allow'], ['git push *', 'ask']]);
});

test('auditoría A09: la política efectiva combina config global, del proyecto y del agente', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'effective-'));
  const project = join(dir, 'project');
  const global = join(dir, 'global');
  mkdirSync(join(project, '.opencode', 'agents'), { recursive: true });
  mkdirSync(global, { recursive: true });
  // El agente permite npm test; la config global lo deniega ANTES: el agente
  // va último y gana. Un agente que termina en "*: deny" gana sobre todo.
  writeFileSync(join(global, 'opencode.json'), JSON.stringify({ permission: { bash: { 'npm test': 'deny' } } }));
  writeFileSync(join(project, '.opencode', 'agents', 'Jhon.md'),
    '---\nmode: subagent\npermission:\n  bash:\n    "npm test": allow\n    "*": deny\n---\nbody\n');
  const tools = [];
  const calls = [];
  await setupWorkflowV2({ location: { directory: project },
    tool: { transform: async (cb) => { cb({ add: (t) => tools.push(t) }); return { dispose: async () => {} }; } } },
  async (request) => { calls.push(request); return { ok: true }; }, join(dir, 'none') + '/', global);
  const [wf] = tools;
  const context = { agent: 'Jhon', sessionID: 's', signal: new AbortController().signal };
  await assert.rejects(wf.execute({ action: 'check', payload: JSON.stringify({ id: 'x', argv: ['npm', 'test'] }) }, context),
    /solo corre comandos que tu política ya permite/);
  assert.equal(calls.length, 0);
});

test('ningún plugin importa el SDK al cargar (OpenCode 2.0.x lo descarta si falta)', async () => {
  // Prueba real con 2.0.18: `import { tool } from '@opencode-ai/plugin'` arriba
  // hacía fallar la carga de skalling-workflow y skalling-data-safety en un
  // proyecto preparado con setup.sh, y la herramienta skalling_workflow no
  // existía para los agentes. Ningún adaptador requiere ese SDK.
  const { readdir, readFile } = await import('node:fs/promises');
  const dir = new URL('../plugins/', import.meta.url);
  for (const name of (await readdir(dir)).filter((f) => f.endsWith('.js'))) {
    const source = await readFile(new URL(name, dir), 'utf8');
    assert.doesNotMatch(source, /@opencode-ai\/plugin/, name);
    const {default: plugin} = await import(new URL(name, dir));
    assert.equal(typeof plugin.setup, 'function', name);
    assert.equal(plugin.server, undefined, name);
  }
});

test('el plugin espera más que el máximo del motor (1 h por verificación)', async () => {
  // Auditoría de c7517ea: el plugin cortaba a los 130 s y una batería de 7 min
  // no podía registrar evidencia.
  const { ENGINE_TIMEOUT_MS } = await import('../plugins/lib/workflow.mjs');
  assert.ok(ENGINE_TIMEOUT_MS > 3600 * 1000);
});

test('restricted runner is allowed only for reviewers; unrestricted eval and push still ask', () => {
  for (const role of ['Jhon','Luz','Teo','Alex','Pau']) {
    const agent = readFileSync(new URL(`../agents-base/${role}.md`,import.meta.url),'utf8');
    assert.equal(decideRules(agentBashRules(agent), 'python3 .opencode/scripts/skalling-node-diagnostic.py --source 0'),
      ['Jhon','Luz'].includes(role) ? 'allow' : 'ask');
    assert.equal(decideRules(agentBashRules(agent), 'node -e 0'), 'ask');
    assert.equal(decideRules(agentBashRules(agent), 'git push origin main'), 'ask');
  }
});

test('v2 installed plugin accepts the same inline check through reviewer policy', async () => {
  const { pathToFileURL } = await import('node:url');
  const project = mkdtempSync(join(tmpdir(),'node-diagnostic-installed-'));
  const local = join(project,'.opencode');
  mkdirSync(join(local,'plugins/lib'),{recursive:true});
  mkdirSync(join(local,'agents'),{recursive:true});
  const plugin = join(local,'plugins/lib/workflow.mjs');
  writeFileSync(plugin,readFileSync(new URL('../plugins/lib/workflow.mjs',import.meta.url)));
  writeFileSync(join(local,'agents/Jhon.md'),readFileSync(new URL('../agents-base/Jhon.md',import.meta.url)));
  const installed = await import(pathToFileURL(plugin).href);
  let wf,received;
  await installed.setupWorkflowV2({location:{directory:project},tool:{transform:async cb=>cb({add:t=>{wf=t;}})}},
    async value=>{received=value;return {ok:true};},join(local,'agents/'),join(project,'no-global'));
  const result = await wf.execute({action:'check',payload:{id:'x',argv:['node','-e',"console.log('fixture')"]}},
    {agent:'Jhon',sessionID:'review',signal:new AbortController().signal});
  assert.match(result.content,/ok/);
  assert.deepEqual(received.payload.argv,['python3','.opencode/scripts/skalling-node-diagnostic.py','--source',"console.log('fixture')"]);
});
