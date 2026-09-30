import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const roles = new Set(['Alex','Jes','Jhon','Luz','Pau','Pol','Sol','Teo']);
const modelID = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_./:-]+(?:#[A-Za-z0-9_.-]+)?$/;
const recoverable = new Set(['provider.transport','provider.timeout','provider.internal',
  'provider.invalid-output','provider.auth','provider.no-route','provider.unsupported-operation',
  'provider.rate-limit','provider.quota']);
export const configDirectory = () => process.env.SKALLING_OPENCODE_DIR || process.env.OPENCODE_CONFIG_DIR ||
  join(process.env.XDG_CONFIG_HOME || join(homedir(), '.config'), 'opencode');

export function validatePolicy(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('model-fallbacks.json debe ser un objeto');
  for (const [role, policy] of Object.entries(value)) {
    if (!roles.has(role) || !policy || !Array.isArray(policy.models) || policy.models.length < 1 || policy.models.length > 3 ||
        policy.models.some(id => typeof id !== 'string' || !modelID.test(id)) || new Set(policy.models).size !== policy.models.length ||
        Object.keys(policy).some(key => !['models','timeoutMs','chunkTimeoutMs'].includes(key))) {
      throw new Error(`Fallback inválido para ${role}: requiere entre 1 y 3 modelos provider/model distintos`);
    }
    for (const key of ['timeoutMs','chunkTimeoutMs']) {
      if (policy[key] !== undefined && (!Number.isInteger(policy[key]) || policy[key] < 1000 || policy[key] > 600000)) {
        throw new Error(`${key}: debe estar entre 1000 y 600000 ms`);
      }
    }
    if ((policy.chunkTimeoutMs ?? 60000) > (policy.timeoutMs ?? 180000)) {
      throw new Error('El plazo de silencio no puede superar el plazo total');
    }
  }
  return value;
}

export function readPolicy() {
  try { return validatePolicy(JSON.parse(readFileSync(join(configDirectory(),'model-fallbacks.json'),'utf8'))); }
  catch (error) { if (error.code === 'ENOENT') return {}; throw error; }
}

function ref(id) {
  const [base, variant] = id.split('#');
  const slash = base.indexOf('/');
  return {providerID:base.slice(0,slash),id:base.slice(slash+1),...(variant ? {variant} : {})};
}
const key = model => `${model.providerID}/${model.id}${model.variant ? '#' + model.variant : ''}`;

// OpenCode 2.0.18 reloads session context between native retries. Changing the
// session model here preserves the current execution (including parent waits
// and completed tools). Never synthesize a second prompt after session failure.
export async function setupModelFallback(ctx, load = readPolicy, notify = record => console.warn('[skalling-fallback]', JSON.stringify(record))) {
  const policies = validatePolicy(load());
  if (!Object.keys(policies).length) return;
  if (!ctx.session?.hook || !ctx.session?.switchModel || !ctx.model?.list || !ctx.provider?.transform) {
    throw new Error('Skalling fallback requiere OpenCode 2.0.18 con session.retry y switchModel');
  }
  const requests = new Map();
  await ctx.session.hook('context', event => {
    // Bounded process-local bookkeeping, never transcript copies or provider payloads.
    if (requests.size >= 1024 && !requests.has(event.sessionID)) requests.delete(requests.keys().next().value);
    const previous = requests.get(event.sessionID);
    requests.set(event.sessionID, {primary:true, agent:event.agent, model:key(event.model), tried:previous?.tried || new Set()});
  });
  for (const kind of ['compaction','title','generate']) {
    await ctx.session.hook(kind, event => requests.delete(event.sessionID));
  }
  // Native transport deadlines cover both initial silence and stalled streams.
  // Provider settings apply to all calls through that provider; keep stricter user limits.
  await ctx.provider.transform(editor => {
    const configured = Object.values(policies);
    const timeout = Math.min(...configured.map(p => p.timeoutMs ?? 180000));
    const chunkTimeout = Math.min(...configured.map(p => p.chunkTimeoutMs ?? 60000));
    for (const {provider} of editor.list()) editor.update(provider.id, draft => {
      draft.settings ||= {};
      for (const [name, limit] of Object.entries({timeout,chunkTimeout})) {
        const current = draft.settings[name];
        draft.settings[name] = typeof current === 'number' && current > 0 ? Math.min(current,limit) : limit;
      }
    });
  });
  await ctx.session.hook('http.response', event => {
    if (event.kind === 'primary' && policies[event.agent]) event.response = guardEmptyResponse(event.response);
  });
  const sockets = new Map();
  await ctx.session.hook('experimental.ws.handshake', event => {
    if (event.kind !== 'primary' || !policies[event.agent]) return;
    if (sockets.size >= 1024) sockets.delete(sockets.keys().next().value);
    sockets.set(event.sessionID, outputInspector());
  });
  await ctx.session.hook('experimental.ws.receive', event => {
    if (event.kind !== 'primary' || !policies[event.agent]) return;
    let value;
    try { value = JSON.parse(event.frame); } catch { return; }
    sockets.get(event.sessionID)?.(value);
  });
  await ctx.session.hook('retry', async event => {
    const policy = policies[event.agent];
    const request = requests.get(event.sessionID);
    if (!policy || !request || request.agent !== event.agent || request.model !== key(event.model)) return;
    if (!recoverable.has(event.error.type) && !(event.error.type === 'provider.invalid-request' && event.error.status === 404)) return;
    if (event.attempt === 2) request.tried.clear();
    request.tried.add(key(event.model));
    // Exhaustion must not fall back into OpenCode's retries of the same broken model.
    event.decision = {retry:false};
    for (const id of policy.models) {
      if (request.tried.has(id)) continue;
      request.tried.add(id);
      const model = ref(id);
      let available;
      try { available = (await ctx.model.list()).data.find(item => item.providerID === model.providerID && item.id === model.id); }
      catch { notify({sessionID:event.sessionID,agent:event.agent,model:id,result:'unavailable'}); continue; }
      if (!available || available.capabilities?.tools === false ||
          (model.variant && !available.variants?.some(variant => variant.id === model.variant))) continue;
      await ctx.session.switchModel({sessionID:event.sessionID,model});
      event.decision = {retry:true,delay:0};
      notify({sessionID:event.sessionID,agent:event.agent,from:key(event.model),to:id,reason:event.error.type});
      return;
    }
    notify({sessionID:event.sessionID,agent:event.agent,reason:event.error.type,result:'exhausted'});
  });
}

// Observe only documented SSE shapes. Unknown/binary protocols pass through;
// do not buffer a whole completion or infer answer quality from its wording.
export function guardEmptyResponse(response) {
  if (!response.ok || !response.body || !response.headers.get('content-type')?.includes('text/event-stream')) return response;
  const inspect = outputInspector();
  const decoder = new TextDecoder();
  let pending = '', disabled = false;
  const stream = response.body.pipeThrough(new TransformStream({
    transform(chunk, controller) {
      if (!disabled) {
        pending += decoder.decode(chunk, {stream:true});
        const lines = pending.split('\n');
        pending = lines.pop();
        for (const line of lines) {
          if (!line.startsWith('data:')) continue;
          const data = line.slice(5).trim();
          if (!data || data === '[DONE]') continue;
          let value;
          try { value = JSON.parse(data); }
          catch { disabled = true; break; }
          inspect(value);
        }
        if (pending.length > 65536) disabled = true;
      }
      controller.enqueue(chunk);
    },
  }));
  return new Response(stream, {status:response.status,statusText:response.statusText,headers:response.headers});
}

export function outputInspector() {
  let useful = false;
  return data => {
    let terminal = false;
    if (Array.isArray(data.choices)) {
      for (const choice of data.choices) {
        const delta = choice.delta || choice.message || {};
        useful ||= Boolean(delta.content?.trim?.() || delta.refusal || delta.tool_calls?.length || delta.function_call);
        if (choice.finish_reason === 'content_filter') useful = true;
        terminal ||= choice.finish_reason === 'stop';
      }
    } else if (data.type === 'content_block_start') {
      useful ||= ['tool_use','server_tool_use'].includes(data.content_block?.type) || Boolean(data.content_block?.text?.trim());
    } else if (data.type === 'content_block_delta') {
      useful ||= Boolean(data.delta?.text?.trim() || data.delta?.partial_json);
    } else if (data.type === 'message_delta') {
      terminal = data.delta?.stop_reason === 'end_turn';
      if (data.delta?.stop_reason === 'refusal') useful = true;
    } else if (data.type === 'response.output_text.delta' || data.type === 'response.refusal.delta') {
      useful ||= Boolean(data.delta?.trim());
    } else if (data.type === 'response.output_item.added') {
      useful ||= Boolean(data.item?.type && !['message','reasoning'].includes(data.item.type));
    } else if (data.type === 'response.completed') {
      useful ||= data.response?.output?.some(item => item.type !== 'reasoning' &&
        (item.type !== 'message' || item.content?.some(part => part.text?.trim() || part.refusal)));
      terminal = true;
    } else if (Array.isArray(data.candidates)) {
      for (const candidate of data.candidates) {
        useful ||= candidate.content?.parts?.some(part => (!part.thought && part.text?.trim()) || part.functionCall || part.inlineData);
        terminal ||= candidate.finishReason === 'STOP';
      }
    }
    if (terminal && !useful) throw new Error('Skalling: el proveedor terminó sin texto ni llamadas a herramientas');
  };
}
