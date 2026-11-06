import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const pluginPath = fileURLToPath(import.meta.url);
const sha256 = value => createHash('sha256').update(value).digest('hex');
const loadedPluginSha = sha256(readFileSync(pluginPath));

const engine = fileURLToPath(new URL('../../scripts/skalling-workflow.py', import.meta.url));
const nodeDiagnostic = fileURLToPath(new URL('../../scripts/skalling-node-diagnostic.py', import.meta.url));
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

const quote = x => /^[a-zA-Z0-9_./:-]+$/.test(x) ? x : "'" + x.replaceAll("'", "'\\''") + "'";

// Identidad y proyecto vienen del runtime; approve consulta la política
// compilada del agente, porque un plugin de OpenCode 2 no puede preguntar.
async function handle(args, runtime, execute) {
  // Se admite objeto o JSON serializado; OpenCode puede reparar el payload.
  const payload = typeof args.payload === 'string' ? JSON.parse(args.payload) : args.payload;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('payload debe ser un objeto JSON con id');
  if (args.action === 'start' && payload.request_kind !== 'code') {
    throw new Error('start requiere request_kind:"code" explícito y un pedido de implementación. '
      + 'Una auditoría o informe sin cambios no abre un workflow de código: usar '
      + 'skalling-route.sh classify --kind audit --record y delegar Alex → Luz; '
      + 'research va a Jes y query la responde Alex. Si el usuario pidió corregir hallazgos, '
      + 'iniciar ese pedido de implementación con request_kind:"code".');
  }
  for (const key of ['actor','session','project','model','exit_code','digest']) {
    if (key in payload) throw new Error('Runtime owns ' + key);
  }
  if (!runtime.agent || !runtime.sessionID) throw new Error('Runtime identity unavailable');
  runtime.signal?.throwIfAborted?.();
  // check {configured: true}: el motor corre el comando que declara el
  // proyecto, congelado en start; no lo elige el modelo, así que no pide
  // permiso (en v2 el plugin no puede pedirlo y Jhon quedaba sin evidencia).
  const configured = args.action === 'check' && (payload.configured === true || payload.configured === 'true');
  const inspection = args.action === 'check' && payload.inspection != null;
  if (inspection && (configured || 'argv' in payload)) throw new Error('inspection no acepta argv ni configured');
  if (args.action === 'check' && !configured && !inspection) {
    // A local inline diagnostic gets only the capabilities of the approved
    // runner. Never fall back to unrestricted Node if it cannot run.
    const inlineNode = Array.isArray(payload.argv) && payload.argv.length === 3
      && payload.argv[0] === 'node' && ['-e', '--eval'].includes(payload.argv[1])
      && typeof payload.argv[2] === 'string' && !payload.argv[2].includes('\0');
    const restrictedNode = inlineNode && ['jhon', 'luz'].includes(String(runtime.agent).toLowerCase());
    if (restrictedNode) {
      const { realpath } = await import('node:fs/promises');
      const projectRoot = await realpath(runtime.directory).catch(() => runtime.directory);
      const runner = nodeDiagnostic === projectRoot + '/.opencode/scripts/skalling-node-diagnostic.py'
        ? '.opencode/scripts/skalling-node-diagnostic.py' : nodeDiagnostic;
      payload.argv = ['python3', runner, '--source', payload.argv[2]];
    }
    if (!Array.isArray(payload.argv) || !payload.argv.length || !payload.argv.every((x, i) => typeof x === 'string'
      && !x.includes('\0') && ((restrictedNode && i === 3) || !/[\n\r]/.test(x)))) {
      throw new Error('Exact argv required (lista de strings), o configured: true para el comando de verificación del proyecto');
    }
    await runtime.approve(payload.argv.map(quote).join(' '), payload.argv);
  }
  if (args.action === 'probe' && 'argv' in payload) throw new Error('probe solo ejecuta el comando configurado; no acepta argv');
  if (configured) delete payload.argv;
  runtime.signal?.throwIfAborted?.();
  const result = await execute({project:runtime.directory, actor:String(runtime.agent).toLowerCase(),
    session:runtime.sessionID, action:args.action, payload}, runtime.signal);
  let diskSha = null;
  try { diskSha = sha256(readFileSync(pluginPath)); } catch { /* Runtime may have been removed while the session stays open. */ }
  result.runtime = {...result.runtime, plugin_path:pluginPath, plugin_loaded_sha256:loadedPluginSha,
    plugin_disk_sha256:diskSha, reload_required:loadedPluginSha !== diskSha,
    tool_contract_sha256:sha256(WORKFLOW_DESCRIPTION), agent_prompt_loaded:'not_observable'};
  return JSON.stringify(result);
}

const WORKFLOW_DESCRIPTION = `TeamDB es la fuente del foco, estado y evidencia. start requiere request_kind:"code" explícito: sólo implementación. Auditoría/informe read-only: skalling-route.sh classify --kind audit --record → Luz, sin start/deliver/plan; corregir hallazgos por pedido humano sí es code. start: id, intent, files, acceptance, reuse; outcomes [{id,expected}] solo producto, constraints/non_goals listas breves de restricciones explícitas. commit_policy: allowed por defecto (cierre sin commit), required si el usuario lo exige, forbidden si lo prohíbe. Commit/hooks/push se acreditan aparte.
El foco de start/status/resume viene directamente del workflow, fuera de la búsqueda textual. Al retomar usa la respuesta vigente; si falta el id, resume con payload {} recupera desde la sesión del runtime sin escribir. Si devuelve candidatos, comparar con el pedido y consultar status con su id; no elegir otro objetivo ni crear otro plan por pérdida de contexto. start/status/ready traen context; no repetir lecturas ya recibidas. context_seen solo para cuerpos aún presentes. Memoria no autoriza acciones nuevas. requires_resolution/relations advierten contradicciones o reemplazos registrados: consultar las referencias pertinentes antes de usar esa memoria como regla, sin abrir revisiones ajenas al pedido.
resource_budget opcional en start: max_checks/max_elapsed_seconds sólo si el usuario fijó esos límites. Bloquea nuevas pruebas al agotarse; conserva evidencia y permite cierre válido. No representa cuota de tokens ni autoriza reiniciar el presupuesto. Seguir recommended_action. focused para local; direct para alcance claro con planning_required:false; staged para planes necesarios. Conservar riesgo y revisores; no agregar agentes por rutina. ready: plan_id aprobado y task_ids. rescope: files adicionales, outcome_id válido y evidence de su necesidad; conserva objetivo y restricciones. supersedes conserva restricciones, commit_policy y presupuesto. Para una corrección explícita del usuario: focus_revision {feedback_id,evidence} y las listas constraints/non_goals de reemplazo; claves omitidas se heredan. No usarlo para eludir límites; la revisión empieza de nuevo.
Teo probe con id es opcional: solo testing.fast pertinente, sin argv; no aprueba ni entrega. Sin fast no ejecutar suite por rutina. Suite configurada en probe/check exige profile:"unit" e impact_reason concreto; comandos congelados al iniciar. deliver corre auto_verify; no duplicarlo en terminal. Jhon oracle con review_plan:[criterios mínimos] → check usando esos criterion → approve con coverage. Jhon y Luz pueden declarar review_plan en su primer check/reuse; si se omite, el motor fija un plan mínimo. Cubierto el plan de cada revisor, otro check exige gap concreto; Luz según riesgo, Pau si hay memoria durable necesaria. Reutilizar oracle. check configured:true usa fast congelado. check inspection:{kind:"diff"|"file",files:[rutas del alcance]} lee Git base/candidato sin shell arbitrario; inspection_output viene en respuesta, si truncado recuperar evidence. Inspecciones nativas son reutilizables automáticamente por sus archivos/base/motor: no recorren el workspace ni expiran por tiempo. Un cambio ajeno no invalida el diff. Jhon/Luz conservan sus propios veredictos. No usar child_process ni packfiles para inspeccionar Git. retry_of conserva comando; replacement_of permite corregir un check inválido/infrastuctura con el mismo criterion, failure_kind:"invalid_check"|"infrastructure" y evidence concreta. Ambos comparten dos reparaciones; no pedir nueva entrega por fallos del verificador ni reclasificar defectos reales; reusable:true solo entradas deterministas. Luz reuse con check_index y evidence. evidence recupera un log sin repetir la prueba. node -e/--eval de revisores usa el runner restringido, nunca ejecución irrestricta como fallback.
approve requiere coverage [{outcome_id,check_index,observation}] para TODOS los outcomes con evidencia pertinente del candidato. Verde genérico no demuestra el pedido. reject: evidence y findings [{id,problem,expected,outcome_id}] o {id,problem,expected,risk,files}; outcome_id válido o impacto concreto sobre archivos del pedido son obligatorios para bloquear nuevos workflows. Una preferencia opcional va a defer {id,note_id,suggestion,reason}: queda en TeamDB, no rechaza ni invalida pruebas. No ejecutar sugerencias diferidas por iniciativa propia. deliver requiere resolutions [{finding_id,change}] de todos los pendientes. Máximo tres entregas aun con supersedes; parallel_agents reúne ambos veredictos antes de corregir.
Con aprobación, commit del rol indicado con id/message/coverage crea commit local verificado, preservando staging ajeno; no pedir Git al usuario ni repetir checks válidos. prepare_commit conserva compatibilidad. Alex complete exige commit solo con commit_policy required y cambios. forbidden bloquea commit/prepare_commit incluso tras complete; no usar Git directo para eludirlo. No confundir preparado con SHA ni commit con push: publicación requiere autorización. Runtime .opencode exige archivos enumerados y riesgo alto; contexto/secretos excluidos. preserve_external de Alex registra cambios ajenos con evidence; no excluye los propios.
Ante blocked no repetir supersedes: Alex registra feedback correction/scope_change de la instrucción humana existente y recover {id,feedback_id,evidence,recovery_plan}. Una sola recuperación por pedido habilita una entrega adicional; conserva historia, riesgo, hallazgos y presupuesto explícito. constraints/non_goals/commit_policy sólo se reemplazan si esa instrucción lo autoriza; omitidos se conservan. Si se consume y el usuario vuelve a ordenar continuar tras el bloqueo, registrar esa instrucción nueva en feedback y usar recover con continuation:true, feedback_id, evidence y recovery_plan. recover también acepta user_instruction con el texto humano real y feedback_id para registrar feedback y continuación atómicamente en una llamada. Una entrega por autorización nueva; nunca reciclar feedback gastado ni inventar consentimiento. No pedir de nuevo autorización ya recibida. Sin instrucción nueva, diagnosticar el bloqueo concreto. Registrar memoria autorizada con Pau/teamdb-memory.sh no requiere action document: document cierra la etapa tras revisión. Un JSON candidato no demuestra que exista la fila. No convertir documentación pendiente en una prohibición de escribir memoria.
cancel/fail de Alex exigen evidence y no certifican éxito. feedback registra feedback_id, kind accepted/correction/scope_change/new_task y evidence humana; silencio no es aceptación. runtime identifica backend y plugin realmente cargado; reload_required detecta un plugin viejo en memoria tras actualizar disco. No inferir el prompt de agente cargado: agent_prompt_loaded es not_observable. review_timing separa comando y validación de caché; usage es estimación por ventana de sesiones, no sumar workflows compartidos como consumo exacto. Payload con id salvo resume; identidad/proyecto/sesión los aporta el runtime.`;

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
  // Configuración y frontmatter: permission (string o { bash: string | { patrón: efecto } }).
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

const WORKFLOW_ACTIONS = ['start', 'status', 'clarify', 'plan', 'ready', 'probe', 'deliver', 'rescope', 'oracle', 'check',
  'approve', 'reject', 'document', 'complete', 'prepare_commit', 'commit', 'preserve_external', 'reuse', 'evidence', 'feedback', 'recover', 'cancel', 'fail'];
const text = { type: 'string' };
const PAYLOAD_SCHEMA = {
  type: 'object',
  properties: {
    context_seen: {type: 'array', items: text, description: 'read_keys cuyos cuerpos completos siguen en TU contexto; vacío después de compacción o en otro agente.'},
    id: text, risk: { type: 'string', enum: ['low', 'medium', 'high'] },
    request_kind: {type: 'string', enum: ['code', 'audit', 'research', 'query'],
      description: 'Obligatorio en start: code sólo para implementar cambios; auditoría, investigación y consultas no usan este motor.'},
    scope: { type: 'string', enum: ['local', 'module', 'cross-cutting'] },
    clarity: { type: 'string', enum: ['clear', 'ambiguous'] },
    decision: { type: 'string', enum: ['none', 'pending', 'resolved'] },
    sensitive: { type: 'boolean' }, visual: { type: 'boolean' },
    files: { type: 'array', items: text }, argv: { type: 'array', items: text },
    outcomes: {type: 'array', items: {type: 'object', properties: {id: text, expected: text}, required: ['id', 'expected']}},
    coverage: {type: 'array', items: {type: 'object', properties: {outcome_id: text, check_index: {type: 'integer'}, observation: text}, required: ['outcome_id', 'check_index', 'observation']}},
    feedback_id: text, recovery_plan: text, user_instruction: text, continuation: {type: 'boolean'}, kind: {type: 'string', enum: ['accepted', 'correction', 'scope_change', 'new_task']},
    message: text, acceptance: text, reuse: text, intent: text, task: text, supersedes: text, evidence: {type: 'string', description: 'En rescope es obligatorio: explica por qué cada archivo o grupo añadido es necesario para el objetivo.'},
    task_ids: {type: 'array', items: {type: 'integer'}},
    plan_id: { type: 'integer' }, method: text, criterion: text, expected: text, negative: text,
    invariant: text, refutation: text, findings: text, configured: { type: 'boolean' },
    profile: {type: 'string', enum: ['fast', 'unit']}, impact_reason: text,
    inspection: {type: 'object', properties: {kind: {type: 'string', enum: ['diff', 'file']}, files: {type: 'array', items: text}}, required: ['kind'], additionalProperties: false},
    review_plan: {type: 'array', items: text}, gap: text, replacement_of: {type: 'integer'},
    execution_mode: { type: 'string', enum: ['focused', 'staged'] },
    planning_required: { type: 'boolean' }, memory_required: { type: 'boolean' },
    reusable: { type: 'boolean' }, check_index: { type: 'integer' }, retry_of: { type: 'integer' },
    failure_kind: { type: 'string', enum: ['product', 'infrastructure', 'flaky', 'invalid_check'] },
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
      description: WORKFLOW_DESCRIPTION,
      // Esquema completo: OpenCode 2.x repara los tipos antes de llamar
      // ("false" → false, string JSON → objeto). Sin él, un modelo mandó
      // "visual": "false" y el motor lo leyó como visual (prueba real).
      input: { type: 'object', properties: { action: { type: 'string', enum: WORKFLOW_ACTIONS }, payload: PAYLOAD_SCHEMA },
        required: ['action', 'payload'], additionalProperties: false },
      execute: async (input, context) => {
        const directory = ctx.location?.directory || process.cwd();
        return {
          content: await handle(input, {agent:context.agent, sessionID:context.sessionID, directory, signal: context.signal,
            approve: async (pattern, argv) => {
              // Un plugin v2 no puede abrir un pedido de permiso: solo corre
              // lo que la política efectiva ya permite; todo lo demás, fuera.
              if (decideRules(await effectiveRules(context.agent, directory), pattern) !== 'allow') {
                const ignoreCheck = /^python[\d.]*$/.test(argv[0]) && argv[1] === '-c'
                  && argv[2]?.includes('check-ignore');
                const guidance = ignoreCheck
                  ? 'Para comprobar las exclusiones de Skalling, usá check con argv '
                    + '["bash", "<SKALLING_ROOT>/scripts/skalling-privacy.sh", "verify-internal", "<proyecto>"]. '
                    + 'Es de solo lectura y verifica reglas efectivas; no habilites python3 -c de forma general. '
                  : '';
                const commandSummary = argv[1] === '-c' ? `${argv[0]} -c [código inline omitido]`
                  : pattern.slice(0, 400) + (pattern.length > 400 ? '…' : '');
                throw new Error('En OpenCode v2 un check solo corre comandos que tu política ya permite (un plugin no '
                  + 'puede pedir aprobación). Usá configured: true solo si el comando configurado demuestra este criterio; '
                  + 'si hace falta otro comando, informalo a Alex para corregir el permiso del mismo verificador. '
                  + guidance + 'No lo delegues a Pau ni apruebes como ejecutado un check pendiente. Comando rechazado: ' + commandSummary);
              }
            }}, execute),
        };
      },
    });
  });
}
