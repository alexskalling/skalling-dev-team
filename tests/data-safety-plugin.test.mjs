import test from 'node:test';
import assert from 'node:assert/strict';
import { destructiveTool } from '../plugins/lib/data-safety.mjs';

const tool = definition => definition;
tool.schema = { string: () => ({ optional() { return this; } }) };
const args = { database: '.opencode/context/team.db', sql: "DELETE FROM concepts WHERE slug=?", params: '["obsolete"]' };
const preview = { database: '/project/.opencode/context/team.db', state_hash: 'exact-state', sql: args.sql, params: ['obsolete'] };

test('denied or aborted approval never executes the destructive operation', async () => {
  for (const aborted of [false, true]) {
    const calls = [];
    const controller = new AbortController();
    if (aborted) controller.abort();
    const definition = destructiveTool(tool, async request => { calls.push(request); return preview; });
    await assert.rejects(definition.execute(args, { directory: '/project', abort: controller.signal,
      ask: async () => { throw new Error('User denied'); } }));
    assert.deepEqual(calls.map(x => x.action), ['preview']);
  }
});

test('approval is exact, requested every time, and precedes apply', async () => {
  const events = [], approvals = [];
  const definition = destructiveTool(tool, async request => { events.push(request.action); return preview; });
  for (let i = 0; i < 2; i++) await definition.execute(args, { directory: '/project', abort: new AbortController().signal,
    ask: async request => { approvals.push(request); events.push('ask'); } });
  assert.deepEqual(events, ['preview', 'ask', 'apply', 'preview', 'ask', 'apply']);
  assert.equal(approvals[0].permission, 'teamdb_destructive');
  assert.deepEqual(approvals[0].always, []);
  assert.notDeepEqual(approvals[0].patterns, approvals[1].patterns);
  assert.equal(approvals[0].metadata.sql, args.sql);
  assert.deepEqual(approvals[0].metadata.params, ['obsolete']);
});
