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

export function workflowTool(tool, execute = run) {
  return tool({
    description: 'Flujo por rol con evidencia ejecutada: start, clarify, plan, ready, deliver, oracle, check, reject, document, complete, status. Payload JSON incluye id; nunca actor. FAST mantiene Teo→Jhon; alto exige Luz y Pau.',
    args: {action:tool.schema.string(), payload:tool.schema.string()},
    async execute(args, context) {
      const payload = JSON.parse(args.payload);
      for (const key of ['actor','session','project','model','exit_code','digest']) {
        if (key in payload) throw new Error('Runtime owns ' + key);
      }
      if (!context.agent || !context.sessionID) throw new Error('Runtime identity unavailable');
      context.abort.throwIfAborted();
      if (args.action === 'check') {
        if (!Array.isArray(payload.argv) || !payload.argv.length || !payload.argv.every(x => typeof x === 'string' && !/[\n\r\0]/.test(x))) {
          throw new Error('Exact argv required');
        }
        const quote = x => /^[a-zA-Z0-9_./:-]+$/.test(x) ? x : "'" + x.replaceAll("'", "'\\''") + "'";
        await context.ask({permission:'bash', patterns:[payload.argv.map(quote).join(' ')], always:[],
          metadata:{argv:payload.argv, reason:'Ejecutar evidencia independiente sobre el candidato congelado'}});
      }
      context.abort.throwIfAborted();
      return JSON.stringify(await execute({project:context.directory, actor:context.agent.toLowerCase(),
        session:context.sessionID, action:args.action, payload}, context.abort));
    },
  });
}
