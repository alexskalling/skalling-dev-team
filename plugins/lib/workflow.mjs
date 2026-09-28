import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const engine = fileURLToPath(new URL('../../scripts/skalling-workflow.py', import.meta.url));
export const ENGINE_TIMEOUT_MS = 3_660_000;
async function run(request, signal) {
  return new Promise((resolve, reject) => {
    // Más que el máximo del motor (1 h): el límite real de cada verificación
    // es testing.timeout_seconds; cancelar la llamada manda SIGTERM y el
    // motor termina el grupo de procesos de la prueba.
    const child = execFile('python3', [engine], {cwd:request.project, signal, timeout:ENGINE_TIMEOUT_MS,
      killSignal:'SIGTERM', maxBuffer:4*1024*1024},
      (error, stdout, stderr) => {
        if (error) return reject(new Error(stderr || error.message));
        try { resolve(JSON.parse(stdout)); } catch (failure) { reject(failure); }
      });
    child.stdin.end(JSON.stringify(request));
  });
}

// El motor es la única autoridad del flujo de código dentro de OpenCode:
// su actor/sesión vienen de ToolContext, no de argv, así que correr el
// script crudo falsificaría identidad. teamdb-seal-receipt.sh se niega solo
// cuando lo invoca un agente (SKALLING_RUNTIME_AGENT presente); queda como
// camino humano de terminal.
export function blocksDirectWorkflowScript(command) {
  return /skalling-workflow\.py/.test(command);
}

const quote = x => /^[a-zA-Z0-9_./:-]+$/.test(x) ? x : "'" + x.replaceAll("'", "'\\''") + "'";

// Lógica común v1/v2: identidad y proyecto vienen del runtime; `approve`
// decide si el argv de un check puede correr (v1: permiso nativo; v2: la
// política compilada del agente, porque un plugin v2 no puede preguntar).
async function handle(args, runtime, execute) {
  // En v2 (code mode) los modelos pasan el payload como objeto; en v1 llega
  // como string JSON. Se aceptan ambos (prueba real con OpenCode 2.0.18).
  const payload = typeof args.payload === 'string' ? JSON.parse(args.payload) : args.payload;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('payload debe ser un objeto JSON con id');
  for (const key of ['actor','session','project','model','exit_code','digest']) {
    if (key in payload) throw new Error('Runtime owns ' + key);
  }
  if (!runtime.agent || !runtime.sessionID) throw new Error('Runtime identity unavailable');
  runtime.signal?.throwIfAborted?.();
  // check {configured: true}: el motor corre el comando que declara el
  // proyecto, congelado en start; no lo elige el modelo, así que no pide
  // permiso (en v2 el plugin no puede pedirlo y Jhon quedaba sin evidencia).
  const configured = args.action === 'check' && (payload.configured === true || payload.configured === 'true');
  if (args.action === 'check' && !configured) {
    if (!Array.isArray(payload.argv) || !payload.argv.length || !payload.argv.every(x => typeof x === 'string' && !/[\n\r\0]/.test(x))) {
      throw new Error('Exact argv required (lista de strings), o configured: true para el comando de verificación del proyecto');
    }
    await runtime.approve(payload.argv.map(quote).join(' '), payload.argv);
  }
  if (configured) delete payload.argv;
  runtime.signal?.throwIfAborted?.();
  return JSON.stringify(await execute({project:runtime.directory, actor:String(runtime.agent).toLowerCase(),
    session:runtime.sessionID, action:args.action, payload}, runtime.signal));
}

export function workflowTool(tool, execute = run) {
  return tool({
    description: 'Única autoridad del flujo de código, con evidencia ejecutada. Orden: start (Alex) → clarify (Pol, solo alto) → plan (Sol) → ready (Sol, con el plan_id REAL que devolvió teamdb-plan.sh y aprobado con teamdb-plan-approve.sh) → deliver/rescope (Teo) → oracle/check/approve o reject (Jhon, DESPUÉS del deliver; Luz además en alto) → document (Pau, alto) → complete (Alex sella). Bajo: Teo + verificación automática; medio: Sol → Teo → Jhon; alto: Pol → Sol → Teo → Jhon → Luz → Pau. Cada respuesta y cada rechazo traen el siguiente paso (quién y qué acción): seguilo; no hay otras acciones. Payload JSON con id; nunca actor.',
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

const WORKFLOW_ACTIONS = ['start', 'status', 'clarify', 'plan', 'ready', 'deliver', 'rescope', 'oracle', 'check',
  'approve', 'reject', 'document', 'complete'];
const text = { type: 'string' };
const PAYLOAD_SCHEMA = {
  type: 'object',
  properties: {
    id: text, risk: { type: 'string', enum: ['low', 'medium', 'high'] },
    scope: { type: 'string', enum: ['local', 'module', 'cross-cutting'] },
    clarity: { type: 'string', enum: ['clear', 'ambiguous'] },
    decision: { type: 'string', enum: ['none', 'pending', 'resolved'] },
    sensitive: { type: 'boolean' }, visual: { type: 'boolean' },
    files: { type: 'array', items: text }, argv: { type: 'array', items: text },
    acceptance: text, reuse: text, intent: text, task: text, supersedes: text, evidence: text,
    plan_id: { type: 'integer' }, method: text, criterion: text, expected: text, negative: text,
    invariant: text, refutation: text, findings: text, configured: { type: 'boolean' },
  },
  required: ['id'],
  additionalProperties: true,
};

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
      // Herramienta directa, fuera del "code mode" de 2.0.x: dentro de
      // `execute` los modelos no la encontraban (prueba real: varios intentos
      // fallidos antes del primer start).
      options: { codemode: false },
      description: 'Única autoridad del flujo de código, con evidencia ejecutada. Orden: start (Alex) → clarify (Pol, solo alto) → plan (Sol) → ready (Sol, con el plan_id REAL que devolvió teamdb-plan.sh y aprobado con teamdb-plan-approve.sh) → deliver/rescope (Teo) → oracle/check/approve o reject (Jhon, DESPUÉS del deliver; Luz además en alto) → document (Pau, alto) → complete (Alex sella). Bajo: Teo + verificación automática; medio: Sol → Teo → Jhon; alto: Pol → Sol → Teo → Jhon → Luz → Pau. Cada respuesta y cada rechazo traen el siguiente paso (quién y qué acción): seguilo; no hay otras acciones. Payload JSON con id; nunca actor.',
      // Esquema completo: OpenCode 2.x repara los tipos antes de llamar
      // ("false" → false, string JSON → objeto). Sin él, un modelo mandó
      // "visual": "false" y el motor lo leyó como visual (prueba real).
      input: { type: 'object', properties: { action: { type: 'string', enum: WORKFLOW_ACTIONS }, payload: PAYLOAD_SCHEMA },
        required: ['action', 'payload'], additionalProperties: false },
      execute: async (input, context) => {
        const directory = ctx.location?.directory || process.cwd();
        return {
          content: await handle(input, {agent:context.agent, sessionID:context.sessionID, directory, signal: context.signal,
            approve: async (pattern) => {
              // Un plugin v2 no puede abrir un pedido de permiso: solo corre
              // lo que la política efectiva ya permite; todo lo demás, fuera.
              if (decideRules(await effectiveRules(context.agent, directory), pattern) !== 'allow') {
                throw new Error('En OpenCode v2 un check solo corre comandos que tu política ya permite (un plugin no '
                  + 'puede pedir aprobación). Para el comando de verificación del proyecto usá check con configured: true; '
                  + 'si hace falta otro comando, informalo a Alex. Comando rechazado: ' + pattern);
              }
            }}, execute),
        };
      },
    });
  });
}
