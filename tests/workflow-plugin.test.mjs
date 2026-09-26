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
import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { policyDecision, setupWorkflowV2 } from '../plugins/lib/workflow.mjs';

test('policyDecision lee el bloque bash compilado y gana el patrón más largo', () => {
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
    async (request) => { calls.push(request); return { ok: true }; }, dir + '/');
  const [wf] = tools;
  const context = { agent: 'Jhon', sessionID: 'jhon-s', signal: new AbortController().signal };
  const ok = await wf.execute({ action: 'check', payload: JSON.stringify({ id: 'x', argv: ['npm', 'test'] }) }, context);
  assert.match(ok.content, /ok/);
  assert.equal(calls[0].actor, 'jhon');
  assert.equal(calls[0].project, '/project');
  await assert.rejects(wf.execute({ action: 'check', payload: JSON.stringify({ id: 'x', argv: ['curl', 'https://x.com'] }) }, context),
    /necesita aprobación/);
  await assert.rejects(wf.execute({ action: 'complete', payload: JSON.stringify({ id: 'x', actor: 'jhon' }) }, context), /actor/);
});
