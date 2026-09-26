import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const engine = fileURLToPath(new URL('../../scripts/skalling-workflow.py', import.meta.url));
async function run(request, signal) {
  return new Promise((resolve, reject) => {
    const child = execFile('python3', [engine], {cwd:request.project, signal, timeout:130000, maxBuffer:1024*1024},
      (error, stdout, stderr) => {
        if (error) return reject(new Error(stderr || error.message));
        try { resolve(JSON.parse(stdout)); } catch (failure) { reject(failure); }
      });
    child.stdin.end(JSON.stringify(request));
  });
}

// Only the engine script itself is gated: its actor/session come from
// ToolContext, not argv, so calling it raw would forge identity. Do NOT add
// teamdb-claim.sh/teamdb-seal-receipt.sh here -- those are the plans/tasks
// system's real, live approval path; nothing currently calls
// skalling_workflow.start, so blocking them has no replacement and strands
// Jhon/Pau's actually-used flow.
export function blocksDirectWorkflowScript(command) {
  return /skalling-workflow\.py/.test(command);
}

const quote = x => /^[a-zA-Z0-9_./:-]+$/.test(x) ? x : "'" + x.replaceAll("'", "'\\''") + "'";

// Lógica común v1/v2: identidad y proyecto vienen del runtime; `approve`
// decide si el argv de un check puede correr (v1: permiso nativo; v2: la
// política compilada del agente, porque un plugin v2 no puede preguntar).
async function handle(args, runtime, execute) {
  const payload = JSON.parse(args.payload);
  for (const key of ['actor','session','project','model','exit_code','digest']) {
    if (key in payload) throw new Error('Runtime owns ' + key);
  }
  if (!runtime.agent || !runtime.sessionID) throw new Error('Runtime identity unavailable');
  runtime.signal?.throwIfAborted?.();
  if (args.action === 'check') {
    if (!Array.isArray(payload.argv) || !payload.argv.length || !payload.argv.every(x => typeof x === 'string' && !/[\n\r\0]/.test(x))) {
      throw new Error('Exact argv required');
    }
    await runtime.approve(payload.argv.map(quote).join(' '), payload.argv);
  }
  runtime.signal?.throwIfAborted?.();
  return JSON.stringify(await execute({project:runtime.directory, actor:String(runtime.agent).toLowerCase(),
    session:runtime.sessionID, action:args.action, payload}, runtime.signal));
}

export function workflowTool(tool, execute = run) {
  return tool({
    description: 'Flujo por rol con evidencia ejecutada: start, clarify, plan, ready, deliver, oracle, check, reject, document, complete, status. Payload JSON incluye id; nunca actor. FAST mantiene Teo→Jhon; alto exige Luz y Pau.',
    args: {action:tool.schema.string(), payload:tool.schema.string()},
    async execute(args, context) {
      return handle(args, {agent:context.agent, sessionID:context.sessionID, directory:context.directory,
        signal:context.abort, approve: async (pattern, argv) => {
          await context.ask({permission:'bash', patterns:[pattern], always:[],
            metadata:{argv, reason:'Ejecutar evidencia independiente sobre el candidato congelado'}});
        }}, execute);
    },
  });
}

// Decisión de la política compilada en el frontmatter del agente instalado
// (bloque `permission: bash:`). Gana el patrón más largo que coincide, como
// en OpenCode; sin coincidencia o sin archivo, "ask" (falla cerrado).
export function policyDecision(agentMarkdown, command) {
  const front = String(agentMarkdown || '').split('---')[1] || '';
  const block = front.split('\n');
  const start = block.findIndex(l => /^  bash:\s*$/.test(l));
  if (start < 0) return 'ask';
  let best = null;
  for (const line of block.slice(start + 1)) {
    if (!/^    \S/.test(line)) break;
    const m = line.match(/^    ("(?:[^"\\]|\\.)*"|[^:]+):\s*(allow|ask|deny)\s*$/);
    if (!m) continue;
    const pattern = m[1].startsWith('"') ? JSON.parse(m[1]) : m[1];
    const re = new RegExp('^' + pattern.split('*').map(p => p.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('[\\s\\S]*') + '$');
    if (re.test(command) && (!best || pattern.length >= best.pattern.length)) best = { pattern, decision: m[2] };
  }
  return best ? best.decision : 'ask';
}

export async function setupWorkflowV2(ctx, execute = run, agentsDir = fileURLToPath(new URL('../../agents/', import.meta.url))) {
  const { readFile } = await import('node:fs/promises');
  await ctx.tool.transform((tools) => {
    tools.add({
      name: 'skalling_workflow',
      description: 'Flujo por rol con evidencia ejecutada: start, clarify, plan, ready, deliver, oracle, check, reject, document, complete, status. Payload JSON incluye id; nunca actor. FAST mantiene Teo→Jhon; alto exige Luz y Pau.',
      input: { type: 'object', properties: { action: { type: 'string' }, payload: { type: 'string' } },
        required: ['action', 'payload'], additionalProperties: false },
      execute: async (input, context) => ({
        content: await handle(input, {agent:context.agent, sessionID:context.sessionID,
          directory: ctx.location?.directory || process.cwd(), signal: context.signal,
          approve: async (pattern) => {
            const name = String(context.agent || '');
            const markdown = await readFile(agentsDir + name[0].toUpperCase() + name.slice(1).toLowerCase() + '.md', 'utf8').catch(() => '');
            if (policyDecision(markdown, pattern) !== 'allow') {
              throw new Error('Este check necesita aprobación humana y en OpenCode v2 un plugin no puede pedirla: '
                + 'corré el comando con la terminal (el permiso te pregunta) y registrá el resultado. Comando: ' + pattern);
            }
          }}, execute),
      }),
    });
  });
}
