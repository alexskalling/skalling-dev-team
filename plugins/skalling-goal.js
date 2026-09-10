import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const engine = fileURLToPath(new URL('../scripts/skalling-goal.py', import.meta.url));

// Only explicitly invoked goals are resumed. No goals start from model text.
export const SkallingGoal = async ({ client, directory }) => {
  // OpenCode can discover both the global and project copy. Register once per workspace.
  const registry = globalThis[Symbol.for('skalling.goal.instances')] ||= new Set();
  if (registry.has(directory)) return {};
  registry.add(directory);
  const states = new Map();
  const armed = new Set();
  const parents = new Map();
  const pending = new Set();
  async function call(session, action, payload = {}) {
    const request = JSON.stringify({ project: directory, session, action, payload });
    const result = await new Promise((resolve, reject) => {
      const child = execFile('python3', [engine], { cwd: directory, timeout: 30000, maxBuffer: 1024 * 1024 },
        (error, stdout, stderr) => error ? reject(new Error(stderr || error.message)) : resolve(stdout));
      child.stdin.end(request);
    });
    const state = JSON.parse(result);
    if (state) states.set(session, state);
    return state;
  }
  async function owner(session) {
    if (states.has(session)) return session;
    if (parents.has(session)) return parents.get(session);
    let cursor = session;
    for (let depth = 0; depth < 8; depth++) {
      const response = await client.session.get({ path: { id: cursor } });
      cursor = response.data?.parentID;
      if (!cursor) break;
      if (states.has(cursor)) {
        parents.set(session, cursor);
        return cursor;
      }
    }
    return null;
  }
  return {
    'command.execute.before': async (input, output) => {
      if (input.command !== 'skalling-goal') return;
      const argument = input.arguments.trim();
      const action = !argument ? 'status' : ({ status: 'status', pause: 'pause', resume: 'resume', cancel: 'cancel' }[argument] || 'start');
      const state = await call(input.sessionID, action, action === 'start' ? { objective: argument } : {});
      if (action === 'start' || action === 'resume') armed.add(input.sessionID);
      if (action === 'pause' || action === 'cancel') armed.delete(input.sessionID);
      output.parts.push({ type: 'text', text: 'Estado verificado de Skalling Goal: ' + JSON.stringify(state) +
        '\nSolo start/resume autoriza continuar. status/pause/cancel solo se informan, sin ejecutar tareas.' });
    },
    'shell.env': async (input, output) => {
      if (!input.sessionID || states.size === 0) return;
      const session = await owner(input.sessionID);
      if (!session) return;
      output.env.SKALLING_GOAL_SESSION = session;
      output.env.SKALLING_GOAL_PROJECT = directory;
    },
    'tool.execute.before': async (input, output) => {
      if (states.size === 0) return;
      const session = await owner(input.sessionID);
      if (!session) return;
      // Defense in depth. Native permission rules still apply, including unknown shell/API tools.
      if (!['active', 'committing'].includes(states.get(session)?.status)) return;
      const command = output.args.command || '';
      if (/(^|[_-])(push|deploy|publish)([_-]|$)/i.test(input.tool) ||
          (input.tool === 'bash' && /\bgit\b[^\n;&|]*\bpush\b|\bgh\s+(pr\s+merge|release\s+create)|\b(npm|pnpm|yarn|wrangler|vercel|netlify)\b[^\n;&|]*\b(deploy|publish)\b/.test(command))) {
        throw new Error('SKALLING-GOAL: push, publicación y despliegue no están autorizados por este objetivo.');
      }
      if (input.tool === 'bash' && /\bgit\s+(?:-\S+\s+\S+\s+)*(commit|add)\b/.test(output.args.command || '')) {
        throw new Error('SKALLING-GOAL: usar skalling-goal.sh commit para comprobar alcance, evidencia y archivos ajenos.');
      }
    },
    'tool.execute.after': async (input) => {
      if (input.tool === 'bash' && states.size && /skalling-goal\.sh/.test(input.args.command || '')) {
        const session = await owner(input.sessionID);
        if (session) await call(session, 'status');
      }
    },
    event: async ({ event }) => {
      if (event.type === 'server.instance.disposed' && event.properties?.directory === directory) {
        registry.delete(directory);
        states.clear();
        armed.clear();
        return;
      }
      const session = event.properties?.sessionID;
      if (!session || !states.has(session)) return;
      if (event.type === 'session.error') {
        armed.delete(session);
        if (states.get(session).status === 'active') {
          await call(session, 'pause', { reason: 'Sesión interrumpida o error de ejecución; retomar explícitamente.' });
        }
        return;
      }
      if (event.type !== 'session.idle' || !armed.has(session) || states.get(session).status !== 'active' || pending.has(session)) return;
      pending.add(session);
      try {
        const state = await call(session, 'tick');
        if (state.status !== 'active') {
          await client.tui.showToast({ body: { title: 'Skalling Goal detenido', message: state.reason, variant: 'warning' } });
          return;
        }
        const response = await client.session.promptAsync({ path: { id: session }, body: { agent: 'Alex', parts: [{ type: 'text',
          text: 'Continuación del objetivo autorizado /skalling-goal. No es permiso nuevo ni ampliación de alcance.\n' +
            JSON.stringify(state) + '\nContinúa el siguiente paso, verifica y termina con skalling-goal.sh commit; nunca push. '
            + 'Si hay una decisión humana pendiente, registra block antes de preguntar. No repitas trabajo ya comprobado.' }] } });
        if (response.error) throw new Error(JSON.stringify(response.error));
      } catch (error) {
        await call(session, 'block', { reason: 'No se pudo continuar: ' + error.message });
        await client.tui.showToast({ body: { title: 'Skalling Goal bloqueado', message: error.message, variant: 'error' } });
      } finally {
        pending.delete(session);
      }
    },
    'experimental.session.compacting': async (input, output) => {
      const state = states.get(input.sessionID);
      if (state) output.context.push('Objetivo Skalling persistente (no ampliar permisos): ' + JSON.stringify(state));
    },
  };
};
