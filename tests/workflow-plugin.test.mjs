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
