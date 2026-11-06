// Use OpenCode's native checkpoint queue. Never rewrite messages or TeamDB.
export const DEFAULT_CONTEXT_TOKENS = 64000;
export const compactionPolicy = `Conserva el pedido actual, sus restricciones y autorizaciones humanas exactas, archivos, workflow id, estado, hallazgos pendientes y próximo paso. TeamDB es la fuente durable: después del resumen recuperar status por id, o resume si falta, antes de actuar. No convertir planes en resultados ni perder instrucciones aún no registradas. Resumir tareas antiguas ya cerradas; no copiar sus logs completos.`;

export function createContextBudget(ctx, notify = record => console.info('[skalling-context]', JSON.stringify(record))) {
  const states = new Map();
  const configured = ctx.options?.contextTokens;
  const threshold = Number.isInteger(configured) && configured >= 16000 ? configured : DEFAULT_CONTEXT_TOKENS;
  const enabled = ctx.options?.autoCompact !== false;
  function stateFor(id) {
    if (!states.has(id)) {
      if (states.size >= 64) states.delete(states.keys().next().value);
      states.set(id, { context_dispatches: 0, tool_calls: 0, requested: false });
    }
    return states.get(id);
  }
  function report(id) {
    const s = states.get(id);
    if (!s) return undefined;
    return { scope: 'plugin_session_since_load', context_dispatches: s.context_dispatches, tool_calls: s.tool_calls,
      history_estimated_tokens: s.history, system_and_tools_estimated_tokens: s.fixed,
      estimate_method: 'serialized_utf8_bytes_divided_by_4', billed_tokens: false,
      threshold, compaction: s.compaction || 'not_needed' };
  }
  return {
    report,
    clear: () => states.clear(),
    tool(id) { if (id) stateFor(id).tool_calls++; },
    async observe(event) {
      if (!event.sessionID || !Array.isArray(event.messages)) return;
      const s = stateFor(event.sessionID);
      s.context_dispatches++;
      const estimate = value => Math.ceil(Buffer.byteLength(JSON.stringify(value ?? []), 'utf8') / 4);
      s.history = estimate(event.messages);
      s.fixed = estimate(event.system) + estimate(event.tools);
      // Re-arm only after a substantial reduction, never once per model step.
      if (s.requested && s.history < threshold / 2) {
        s.requested = false;
        s.compaction = 'context_reduced';
      }
      if (s.history < threshold || event.messages.length < 8 || s.requested) return;
      s.requested = true;
      s.compaction = !enabled ? 'disabled' : typeof ctx.session?.compact !== 'function' ? 'unsupported' : 'requesting';
      if (s.compaction === 'requesting') {
        try {
          // Resolves admission only; the runtime schedules the safe boundary.
          await ctx.session.compact({ sessionID: event.sessionID });
          s.compaction = 'queued';
        } catch {
          // An optional optimization must not block work or retry indefinitely.
          s.compaction = 'request_failed';
        }
      }
      notify({ session_id: event.sessionID, ...report(event.sessionID) });
    },
  };
}
