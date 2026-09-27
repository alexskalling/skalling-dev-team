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

// Reglas bash como las evalúa OpenCode: se concatenan config global, config
// del proyecto y frontmatter del agente (en ese orden) y GANA LA ÚLTIMA regla
// que coincide (https://opencode.ai/v2/docs/permissions). Sin coincidencia,
// "ask". Antes ganaba el patrón más largo: `npm test: allow` seguido de
// `*: deny` devolvía allow aunque OpenCode deniega.
function globToRegExp(pattern) {
  return new RegExp('^' + pattern.split('*').map(p => p.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('[\\s\\S]*') + '$');
}

export function agentBashRules(agentMarkdown) {
  const front = String(agentMarkdown || '').split('---')[1] || '';
  const block = front.split('\n');
  const start = block.findIndex(l => /^  bash:/.test(l));
  if (start < 0) return [];
  const scalar = block[start].match(/^  bash:\s*(allow|ask|deny)\s*$/);
  if (scalar) return [['*', scalar[1]]];
  const rules = [];
  for (const line of block.slice(start + 1)) {
    if (!/^    \S/.test(line)) break;
    const m = line.match(/^    ("(?:[^"\\]|\\.)*"|[^:]+):\s*(allow|ask|deny)\s*$/);
    if (m) rules.push([m[1].startsWith('"') ? JSON.parse(m[1]) : m[1], m[2]]);
  }
  return rules;
}

// JSONC (opencode.jsonc): comentarios fuera de strings y comas finales.
function parseJsonc(text) {
  let out = '';
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (c === '"') {
      let j = i + 1;
      while (j < text.length && text[j] !== '"') j += text[j] === '\\' ? 2 : 1;
      out += text.slice(i, j + 1); i = j; continue;
    }
    if (c === '/' && text[i + 1] === '/') { while (i < text.length && text[i] !== '\n') i += 1; out += '\n'; continue; }
    if (c === '/' && text[i + 1] === '*') { i = text.indexOf('*/', i + 2); if (i < 0) break; i += 1; continue; }
    out += c;
  }
  return JSON.parse(out.replace(/,(\s*[}\]])/g, '$1'));
}

const EFFECTS = ['allow', 'ask', 'deny'];

export function configBashRules(configText) {
  let config;
  try { config = parseJsonc(String(configText || '')); } catch { return []; }
  const rules = [];
  // Formato v1: permission (string o { bash: string | { patrón: efecto } }).
  const perm = config?.permission;
  if (typeof perm === 'string' && EFFECTS.includes(perm)) rules.push(['*', perm]);
  const bash = perm?.bash;
  if (typeof bash === 'string' && EFFECTS.includes(bash)) rules.push(['*', bash]);
  if (bash && typeof bash === 'object') rules.push(...Object.entries(bash).filter(([, v]) => EFFECTS.includes(v)));
  // Formato nativo v2: permissions: [{ action, resource, effect }], en orden.
  if (Array.isArray(config?.permissions)) {
    for (const rule of config.permissions) {
      if (!['shell', 'bash', '*'].includes(rule?.action) || !EFFECTS.includes(rule?.effect)) continue;
      rules.push([typeof rule.resource === 'string' ? rule.resource : '*', rule.effect]);
    }
  }
  return rules;
}

export function decideRules(rules, command) {
  let decision = 'ask';
  for (const [pattern, value] of rules) {
    if (globToRegExp(pattern).test(command)) decision = value;
  }
  return decision;
}

// Compatibilidad: decisión con solo el frontmatter del agente.
export function policyDecision(agentMarkdown, command) {
  return decideRules(agentBashRules(agentMarkdown), command);
}

export async function setupWorkflowV2(ctx, execute = run, agentsDir = fileURLToPath(new URL('../../agents/', import.meta.url)),
  globalConfigDir = process.env.OPENCODE_CONFIG_DIR || ((process.env.XDG_CONFIG_HOME || ((process.env.HOME || '') + '/.config')) + '/opencode')) {
  const { readFile } = await import('node:fs/promises');
  const read = (path) => readFile(path, 'utf8').catch(() => '');
  async function effectiveRules(agent, directory) {
    const name = String(agent || '');
    const file = name[0].toUpperCase() + name.slice(1).toLowerCase() + '.md';
    // El agente del proyecto reemplaza al global, igual que en OpenCode.
    const agentMarkdown = (await read(directory + '/.opencode/agents/' + file)) || (await read(agentsDir + file))
      || (await read(globalConfigDir + '/agents/' + file));
    const configs = [globalConfigDir + '/opencode.json', globalConfigDir + '/opencode.jsonc',
      directory + '/opencode.json', directory + '/opencode.jsonc',
      directory + '/.opencode/opencode.json', directory + '/.opencode/opencode.jsonc'];
    const rules = [];
    for (const path of configs) rules.push(...configBashRules(await read(path)));
    rules.push(...agentBashRules(agentMarkdown));
    return rules;
  }
  await ctx.tool.transform((tools) => {
    tools.add({
      name: 'skalling_workflow',
      description: 'Flujo por rol con evidencia ejecutada: start, clarify, plan, ready, deliver, oracle, check, reject, document, complete, status. Payload JSON incluye id; nunca actor. FAST mantiene Teo→Jhon; alto exige Luz y Pau.',
      input: { type: 'object', properties: { action: { type: 'string' }, payload: { type: 'string' } },
        required: ['action', 'payload'], additionalProperties: false },
      execute: async (input, context) => {
        const directory = ctx.location?.directory || process.cwd();
        return {
          content: await handle(input, {agent:context.agent, sessionID:context.sessionID, directory, signal: context.signal,
            approve: async (pattern) => {
              // Un plugin v2 no puede abrir un pedido de permiso: solo corre
              // lo que la política efectiva ya permite; todo lo demás, fuera.
              if (decideRules(await effectiveRules(context.agent, directory), pattern) !== 'allow') {
                throw new Error('Este check necesita aprobación humana y en OpenCode v2 un plugin no puede pedirla: '
                  + 'corré el comando con la terminal (el permiso te pregunta) y registrá el resultado. Comando: ' + pattern);
              }
            }}, execute),
        };
      },
    });
  });
}
