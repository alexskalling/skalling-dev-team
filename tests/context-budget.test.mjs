import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createContextBudget } from '../plugins/lib/context-budget.mjs';

function fixture(compact = async () => {}) {
  const requests = [], logs = [];
  const ctx = { options: {}, session: { compact: compact && (async input => { requests.push(input); return compact(input); }) } };
  const budget = createContextBudget(ctx, record => logs.push(record));
  const event = { sessionID: 's', system: [], tools: {},
    messages: Array.from({ length: 8 }, () => ({ role: 'user', content: 'private '.repeat(5000) })) };
  return { ctx, budget, event, requests, logs };
}

test('large history queues once without rewriting messages, and re-arms after reduction', async () => {
  const f = fixture(); const before = structuredClone(f.event);
  await f.budget.observe(f.event); await f.budget.observe(f.event);
  assert.deepEqual(f.event, before);
  assert.deepEqual(f.requests, [{ sessionID: 's' }]);
  assert.equal(f.logs[0].compaction, 'queued');
  assert.equal(f.logs[0].billed_tokens, false);
  assert.ok(!JSON.stringify(f.logs).includes('private'));
  await f.budget.observe({ ...f.event, messages: [{ role: 'user', content: 'summary' }] });
  await f.budget.observe(f.event);
  assert.equal(f.requests.length, 2);
});

test('a large single prompt, fixed system payload or short history cannot cause a compaction loop', async () => {
  const f = fixture();
  await f.budget.observe({ ...f.event, messages: [f.event.messages[0]], system: [{ text: 'x'.repeat(500000) }] });
  assert.equal(f.requests.length, 0);
  assert.ok(f.budget.report('s').system_and_tools_estimated_tokens > 100000);
});

test('unsupported, disabled and failed native compaction remain nonblocking and bounded', async () => {
  for (const [mode, native] of [['unsupported', null], ['disabled', async () => {}], ['request_failed', async () => { throw Error('private provider details'); }]]) {
    const f = fixture(native); if (mode === 'disabled') f.ctx.options.autoCompact = false;
    const b = createContextBudget(f.ctx, r => f.logs.push(r));
    await b.observe(f.event); await b.observe(f.event);
    assert.equal(f.logs.length, 1);
    assert.equal(f.logs[0].compaction, mode);
    assert.ok(!JSON.stringify(f.logs).includes('private'));
  }
});

test('telemetry is isolated and bounded; cleanup drops transient state', async () => {
  const f = fixture();
  for (let i = 0; i < 65; i++) f.budget.tool('s' + i);
  assert.equal(f.budget.report('s0'), undefined);
  assert.equal(f.budget.report('s64').tool_calls, 1);
  f.budget.clear(); assert.equal(f.budget.report('s64'), undefined);
});
