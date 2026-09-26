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

const quote = (value) => "'" + String(value).replaceAll("'", "'\\''") + "'";

// Comando exacto que aplica la operación: el permiso nativo de la terminal se
// lo muestra entero al usuario (base, SQL, parámetros) antes de correrlo.
export function applyCommand(preview, project, engine = engineForShell()) {
  return ['python3', engine, 'apply', '--project', quote(project), '--database', quote(preview.database), '--state-hash', preview.state_hash,
    '--sql', quote(preview.sql), '--params', quote(JSON.stringify(preview.params))].join(' ');
}

function engineForShell() {
  return engine.includes(' ') ? quote(engine) : engine;
}

// OpenCode v2: un plugin externo no puede pedir aprobación desde una
// herramienta (solo las internas pueden). La herramienta hace la vista previa
// y devuelve el comando de aplicar; ese comando pasa por el permiso nativo de
// la terminal, y el hook de permisos lo fuerza a preguntar siempre, aunque el
// usuario haya elegido "permitir siempre" antes. El respaldo y el rechazo si
// la base cambió los sigue haciendo el motor.
export async function setupDataSafetyV2(ctx, run = call) {
  const directory = () => ctx.location?.directory || process.cwd();
  await ctx.tool.transform((tools) => {
    tools.add({
      name: 'teamdb_destructive',
      description: 'Operación SQLite con pérdida de datos: muestra SQL y base exactos y devuelve el comando '
        + 'de aplicar, que OpenCode siempre pide aprobar; respalda antes de ejecutar. Nunca concedida por Goal.',
      input: {
        type: 'object',
        properties: { database: { type: 'string' }, sql: { type: 'string' }, params: { type: 'string' } },
        required: ['database', 'sql'],
        additionalProperties: false,
      },
      execute: async (input) => {
        const preview = await run({ project: directory(), database: input.database, sql: input.sql,
          params: JSON.parse(input.params || '[]'), action: 'preview' });
        return {
          content: 'Vista previa (no se cambió nada):\n' + JSON.stringify(preview, null, 2)
            + '\n\nPara aplicarla, corré exactamente este comando con la terminal. OpenCode le va a pedir '
            + 'aprobación al usuario mostrando el SQL; si la base cambió desde esta vista previa, se rechaza:\n'
            + applyCommand(preview, directory()),
        };
      },
    });
  });
  if (ctx.permission?.hook) {
    await ctx.permission.hook('evaluate', async (event) => {
      if (event.action !== 'shell' && event.action !== 'bash') return;
      if (!(event.resources || []).some((r) => /teamdb-destructive\.py\s+apply\b/.test(String(r)))) return;
      if (event.effect === 'deny') return;
      event.effect = 'ask';
      event.message = 'Operación con pérdida de datos en TeamDB: revisá base, SQL y parámetros antes de aprobar.';
    });
  }
}
