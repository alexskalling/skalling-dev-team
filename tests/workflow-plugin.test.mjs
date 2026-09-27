import test from 'node:test';
import assert from 'node:assert/strict';
import { workflowTool, blocksDirectWorkflowScript } from '../plugins/lib/workflow.mjs';

const tool = x => x;
tool.schema = { string: () => ({}) };

test('actor, session and workspace are supplied by runtime, never model payload', async () => {
  let received;
  const definition = workflowTool(tool, async request => { received = request; return {}; });
  await assert.rejects(definition.execute({ action: 'complete', payload: JSON.stringify({id:'x', actor:'jhon'}) },
    {agent:'Teo', sessionID:'teo-session', directory:'/project', abort:new AbortController().signal}), /actor/);
  await definition.execute({ action: 'status', payload: '{"id":"x"}' },
    {agent:'Teo', sessionID:'teo-session', directory:'/project', abort:new AbortController().signal});
  assert.equal(received.actor, 'teo');
  assert.equal(received.session, 'teo-session');
  assert.equal(received.project, '/project');
});

test('verification consults native permission before executing exact argv', async () => {
  const events = [];
  const definition = workflowTool(tool, async () => {events.push('execute'); return {};});
  const context = {agent:'Jhon',sessionID:'jhon',directory:'/project',abort:new AbortController().signal,
    ask: async request => {events.push(request.permission); throw new Error('denied');}};
  await assert.rejects(definition.execute({action:'check',payload:JSON.stringify({id:'x',argv:['bash','tests/a.test.sh']})},context), /denied/);
  assert.deepEqual(events, ['bash']);
});

test('bash gate blocks the raw engine script but not the live plans/tasks approval path', () => {
  // Regression: the gate used to also block teamdb-claim.sh --advance and
  // teamdb-seal-receipt.sh, which are Jhon/Pau's real, currently-used way
  // to advance a task -- nothing invokes skalling_workflow.start, so that
  // block had no replacement and stranded real approvals.
  assert.equal(blocksDirectWorkflowScript('python3 scripts/skalling-workflow.py'), true);
  assert.equal(blocksDirectWorkflowScript('bash scripts/teamdb-claim.sh plan task --advance --to=approved'), false);
  assert.equal(blocksDirectWorkflowScript('bash scripts/teamdb-seal-receipt.sh task-1 jhon'), false);
});

// OpenCode v2: sin context.ask; el check consulta la política compilada del agente.
import { readFileSync, mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { policyDecision, setupWorkflowV2, decideRules, configBashRules } from '../plugins/lib/workflow.mjs';

test('policyDecision lee el bloque bash compilado (última coincidencia gana)', () => {
  const jhon = readFileSync(new URL('../agents-base/Jhon.md', import.meta.url), 'utf8');
  assert.equal(policyDecision(jhon, 'npm test'), 'allow');
  assert.equal(policyDecision(jhon, 'bash tests/a.test.sh'), 'allow');
  assert.equal(policyDecision(jhon, 'curl https://x.com'), 'ask');
  assert.equal(policyDecision(jhon, 'sqlite3 team.db'), 'deny');
  assert.equal(policyDecision('', 'npm test'), 'ask');
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
  assert.equal(wf.options?.codemode, false);
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
  // existía para los agentes. El SDK solo se importa dentro de la ruta v1.
  const { readdir, readFile } = await import('node:fs/promises');
  const dir = new URL('../plugins/', import.meta.url);
  for (const name of (await readdir(dir)).filter((f) => f.endsWith('.js'))) {
    const source = await readFile(new URL(name, dir), 'utf8');
    assert.doesNotMatch(source, /^\s*import\s[^;]*['"]@opencode-ai\/plugin['"]/m, name);
  }
});
