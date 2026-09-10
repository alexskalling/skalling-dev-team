import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const engine = fileURLToPath(new URL('../../scripts/teamdb-destructive.py', import.meta.url));

async function call(request, signal) {
  return new Promise((resolve, reject) => {
    const child = execFile('python3', [engine], { cwd: request.project, maxBuffer: 1024 * 1024, signal },
      (error, stdout, stderr) => {
        if (error) return reject(new Error(stderr || error.message));
        try { resolve(JSON.parse(stdout)); } catch (parseError) { reject(parseError); }
      });
    child.stdin.end(JSON.stringify(request));
  });
}

// context.ask is supplied by OpenCode, never by model arguments.
export function destructiveTool(tool, run = call) {
  return tool({
    description: 'Operación SQLite con pérdida de datos: muestra SQL y base exactos, exige aprobación humana y respalda antes de ejecutar. Nunca concedida por Goal.',
    args: { database: tool.schema.string(), sql: tool.schema.string(), params: tool.schema.string().optional() },
    async execute(args, context) {
      const request = { project: context.directory, database: args.database, sql: args.sql,
        params: JSON.parse(args.params || '[]') };
      const preview = await run({ ...request, action: 'preview' }, context.abort);
      context.abort.throwIfAborted();
      await context.ask({ permission: 'teamdb_destructive',
        patterns: [preview.database + '\nSQL: ' + preview.sql + '\nParams: ' + JSON.stringify(preview.params) + '\nRequest: ' + randomUUID()], always: [],
        metadata: { database: preview.database, sql: preview.sql, params: preview.params,
          state_hash: preview.state_hash, warning: 'Puede eliminar datos. Se guardará respaldo antes de ejecutar.' } });
      context.abort.throwIfAborted();
      return JSON.stringify(await run({ ...request, action: 'apply', state_hash: preview.state_hash }, context.abort));
    },
  });
}
