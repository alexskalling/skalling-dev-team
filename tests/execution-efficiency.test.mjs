import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setupEfficiency, marker } from '../plugins/lib/execution-efficiency.mjs';

let sequence = 0;
async function fixture() {
  const hooks = {};
  const ctx = { location: { directory: '/efficiency/' + sequence++ },
    session: { hook: async (name, fn) => { hooks[name] = fn; } },
    tool: { hook: async (name, fn) => { hooks[name] = fn; } } };
  const cleanup = await setupEfficiency(ctx);
  const event = (agent = 'Alex', sessionID = 's1') => ({ agent, sessionID, system: [{ type: 'text', text: 'original' }] });
  return { ctx, hooks, cleanup, event };
}

test('only Skalling agents receive policy once, without changing original instructions', async () => {
  const f = await fixture();
  try {
    for (const agent of ['Alex', 'Pol', 'Sol', 'Teo', 'Jhon', 'Luz', 'Jes', 'Pau']) {
      const e = f.event(agent);
      const system = e.system;
      await f.hooks.context(e); await f.hooks.context(e);
      assert.equal(e.system, system);
      assert.equal(e.system.length, 2);
      assert.equal(e.system[0].text, 'original');
      assert.equal(e.system[1].metadata.skalling, marker);
      assert.match(e.system[1].text, /autorización aplicable/);
    }
    assert.equal(await setupEfficiency(f.ctx), undefined);
  } finally { f.cleanup(); }
});

test('observes repeated commands and lossy output without executing, rewriting or declaring success', async () => {
  const f = await fixture();
  try {
    const call = { agent: 'Teo', sessionID: 's1', tool: 'shell', status: 'completed',
      input: { command: 'SECRET=private npm test | tail -8' }, result: { exit: 0 } };
    const before = structuredClone(call);
    await f.hooks['execute.after'](call); await f.hooks['execute.after'](call);
    assert.deepEqual(call, before);
    const e = f.event(); await f.hooks.context(e);
    assert.match(e.system[1].text, /1 repeticiones/);
    assert.match(e.system[1].text, /última salida shell fue filtrada/);
    assert.doesNotMatch(e.system[1].text, /SECRET|private npm/);
    const other = f.event('Teo', 'other'); await f.hooks.context(other);
    assert.doesNotMatch(other.system[1].text, /Se observaron/);
  } finally { f.cleanup(); }
});

test('long waits are advisory; next command clears transient hints and permissions remain untouched', async () => {
  const f = await fixture();
  try {
    const call = { agent: 'Teo', sessionID: 's1', tool: 'shell', input: { command: 'sleep 150; gh pr view 8' } };
    await f.hooks['execute.after'](call);
    const e = f.event(); await f.hooks.context(e);
    assert.match(e.system[1].text, /último comando incluía espera/);
    assert.equal(call.input.command, 'sleep 150; gh pr view 8');
    await f.hooks['execute.after']({ ...call, input: { command: 'git status --short' } });
    await f.hooks.context(e);
    assert.doesNotMatch(e.system[1].text, /último comando incluía espera/);
    assert.deepEqual(Object.keys(f.hooks).sort(), ['compaction', 'context', 'execute.after']);
  } finally { f.cleanup(); }
});

test('bounded session history, cleanup and unsupported runtimes do not retain state', async () => {
  assert.equal(await setupEfficiency({}), undefined);
  const f = await fixture();
  for (let i = 0; i < 65; i++) {
    for (let j = 0; j < 2; j++) await f.hooks['execute.after']({ agent: 'Teo', sessionID: 's' + i, tool: 'shell', input: { command: 'true' } });
  }
  const e = f.event('Teo', 's0'); await f.hooks.context(e);
  assert.doesNotMatch(e.system[1].text, /Se observaron/);
  f.cleanup();
  const cleanup = await setupEfficiency(f.ctx);
  assert.equal(typeof cleanup, 'function'); cleanup();
});

test('Build, Plan, General and unknown agents are untouched and unobserved', async () => {
  const f = await fixture();
  try {
    for (const agent of ['build', 'plan', 'Build', 'Plan', 'general', 'custom', undefined]) {
      const e = { ...f.event(), agent };
      const before = structuredClone(e);
      const call = { agent, sessionID: 's1', tool: 'shell', input: { command: 'sleep 150; npm test | tail -8' } };
      await f.hooks['execute.after'](call); await f.hooks['execute.after'](call);
      await f.hooks.context(e);
      assert.deepEqual(e, before);
    }
    const skalling = f.event(); await f.hooks.context(skalling);
    assert.doesNotMatch(skalling.system[1].text, /Se observaron|última salida shell fue filtrada|último comando incluía espera/);
    skalling.agent = 'build'; await f.hooks.context(skalling);
    assert.deepEqual(skalling.system, [{ type: 'text', text: 'original' }]);
  } finally { f.cleanup(); }
});
