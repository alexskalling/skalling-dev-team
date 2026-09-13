import test from 'node:test';
import assert from 'node:assert/strict';
import { workflowTool } from '../plugins/lib/workflow.mjs';

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
