import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { SkallingGoal } from '../plugins/skalling-goal.js';

test('plugin: explicit authority, one continuation, pause, child scope and publication guards', async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'skalling-goal-plugin-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: directory });
  git('init', '-q'); git('config', 'user.email', 'fixture@example.test'); git('config', 'user.name', 'Fixture');
  writeFileSync(join(directory, '.gitignore'), '.opencode/\n');
  git('add', '.'); git('commit', '-qm', 'base');
  const prompts = [];
  const client = { session: { get: async () => ({ data: { parentID: 'root' } }),
    promptAsync: async (request) => { prompts.push(request); return {}; } }, tui: { showToast: async () => ({}) } };
  const hooks = await SkallingGoal({ client, directory });
  assert.deepEqual(await SkallingGoal({ client, directory }), {});
  const command = async (arguments_) => {
    const output = { parts: [] };
    await hooks['command.execute.before']({ command: 'skalling-goal', sessionID: 'root', arguments: arguments_ }, output);
    return output;
  };
  await hooks.event({ event: { type: 'session.idle', properties: { sessionID: 'root' } } });
  assert.equal(prompts.length, 0);
  assert.match(JSON.stringify(await command('Implementar fixture')), /active/);
  const env = { env: {} };
  await hooks['shell.env']({ sessionID: 'child' }, env);
  assert.equal(env.env.SKALLING_GOAL_SESSION, 'root');
  for (const command of ['git push origin main', 'git commit -m nope', 'gh pr merge 1', 'npm publish']) {
    await assert.rejects(hooks['tool.execute.before']({ sessionID: 'child', tool: 'bash' }, { args: { command } }));
  }
  await hooks['tool.execute.before']({ sessionID: 'root', tool: 'bash' }, { args: { command: 'git diff' } });
  const idle = () => hooks.event({ event: { type: 'session.idle', properties: { sessionID: 'root' } } });
  await Promise.all([idle(), idle()]);
  assert.equal(prompts.length, 1);
  await command('pause'); await idle();
  assert.equal(prompts.length, 1);
  await command('resume'); await idle();
  assert.equal(prompts.length, 2);
  await hooks.event({ event: { type: 'session.error', properties: { sessionID: 'root' } } });
  await idle(); assert.equal(prompts.length, 2);
  assert.match(JSON.stringify(await command('status')), /paused/);
  await command('resume');
  await hooks.event({ event: { type: 'server.instance.disposed', properties: { directory } } });
  const restarted = await SkallingGoal({ client, directory });
  await restarted['command.execute.before']({ command: 'skalling-goal', sessionID: 'root', arguments: 'status' }, { parts: [] });
  await restarted.event({ event: { type: 'session.idle', properties: { sessionID: 'root' } } });
  assert.equal(prompts.length, 2, 'status after restart must not resume automatically');
  await restarted['command.execute.before']({ command: 'skalling-goal', sessionID: 'root', arguments: 'cancel' }, { parts: [] });
  await restarted.event({ event: { type: 'session.idle', properties: { sessionID: 'root' } } });
  assert.equal(prompts.length, 2);
});
