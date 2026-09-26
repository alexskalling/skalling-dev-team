import test from 'node:test';
import assert from 'node:assert/strict';
import { applyCommand, setupDataSafetyV2 } from '../plugins/lib/data-safety.mjs';
import { guardCommand } from '../plugins/lib/git-guard.mjs';

function fakeV2() {
  const state = { tools: [], hooks: {} };
  const ctx = {
    location: { directory: '/p/proyecto' },
    tool: { transform: async (cb) => { cb({ add: (t) => state.tools.push(t) }); return { dispose: async () => {} }; } },
    permission: { hook: async (name, cb) => { state.hooks[name] = cb; return { dispose: async () => {} }; } },
  };
  return { state, ctx };
}

const preview = { database: '/p/proyecto/.opencode/context/team.db', state_hash: 'abc123',
  sql: "DELETE FROM decisions WHERE slug = ?", params: ["it's-old"] };

test('v2: la herramienta solo previsualiza y devuelve el comando exacto de aplicar', async () => {
  const { state, ctx } = fakeV2();
  const calls = [];
  await setupDataSafetyV2(ctx, async (request) => { calls.push(request); return preview; });
  const [tool] = state.tools;
  assert.equal(tool.name, 'teamdb_destructive');
  const result = await tool.execute({ database: '.opencode/context/team.db', sql: preview.sql, params: '["it\'s-old"]' });
  assert.deepEqual(calls.map((c) => c.action), ['preview']);
  assert.equal(calls[0].project, '/p/proyecto');
  assert.match(result.content, /teamdb-destructive\.py apply --project '\/p\/proyecto'/);
  assert.match(result.content, /--state-hash abc123/);
});

test('el comando de aplicar pasa el guard en su forma directa (el permiso pregunta)', () => {
  const command = applyCommand(preview, '/p/proyecto', '/home/u/.config/opencode/scripts/teamdb-destructive.py');
  assert.equal(guardCommand(command), null);
  assert.ok(guardCommand('echo {} | python3 /home/u/.config/opencode/scripts/teamdb-destructive.py'));
});

test('v2: el hook fuerza preguntar aunque exista un "permitir siempre"', async () => {
  const { state, ctx } = fakeV2();
  await setupDataSafetyV2(ctx, async () => preview);
  const event = { action: 'shell', resources: [applyCommand(preview, '/p/proyecto')], effect: 'allow' };
  await state.hooks.evaluate(event);
  assert.equal(event.effect, 'ask');
  const denied = { action: 'shell', resources: [applyCommand(preview, '/p/proyecto')], effect: 'deny' };
  await state.hooks.evaluate(denied);
  assert.equal(denied.effect, 'deny');
  const other = { action: 'shell', resources: ['git status'], effect: 'allow' };
  await state.hooks.evaluate(other);
  assert.equal(other.effect, 'allow');
});
