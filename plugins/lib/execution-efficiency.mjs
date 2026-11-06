// Advisory workflow policy plus bounded native context compaction.
// Never changes commands, permissions, agent identity or persisted history.
import { createHash } from 'node:crypto';
import { createContextBudget, compactionPolicy } from './context-budget.mjs';

export const marker = 'SKALLING_EXECUTION_EFFICIENCY';
const skallingAgents = new Set(['alex', 'pol', 'sol', 'teo', 'jhon', 'luz', 'jes', 'pau']);
const isSkalling = agent => typeof agent === 'string' && skallingAgents.has(agent.toLowerCase());
export const policy = `Conserva el foco del pedido con la menor latencia compatible con una entrega correcta.
- TeamDB es la fuente: usa intent, outcomes, constraints, non_goals y evidencia del workflow. Tras perder contexto, status con id o resume {} si falta; no reconstruyas desde archivos de memoria paralelos. No retomes un candidato que no corresponda al pedido actual.
- Elige la ruta mínima suficiente; cada agente/revisión responde a un resultado o riesgo concreto. No añadas planificación, auditoría, refactor ni despliegue por rutina. Guarda sugerencias opcionales con defer; no bloquean ni amplían el trabajo.
- Agrupa lecturas independientes. Entrega a cada rol solo id, foco, restricciones y evidencia pertinente; amplía memoria omitida solo cuando sea necesaria. No repitas lecturas ya disponibles ni asumas que otro agente conserva tu contexto.
- Copy, iconos y orden declarativo local sin cambios de lógica, permisos o contratos: leer lo afectado, editar y verificar resultado/diff. No cargar TDD/Ponytail ni fabricar tests temporales por rutina; strict_tdd conserva su aplicación a cambios de comportamiento. Jhon verifica los criterios sin ampliar el alcance.
- Pruebas afectadas durante la corrección; validación final requerida una vez por candidato. Reutiliza evidencia solo si código, comando, configuración, dependencias y entorno pertinentes siguen iguales. Un verde genérico no prueba el pedido. Reúne hallazgos antes de corregir.
- Conserva salida completa en log temporal y código de salida original. tail/tee/grep no prueban éxito; head puede causar SIGPIPE. Consulta el log existente antes de repetir una suite.
- Consulta CI antes de esperar; evita sleep largo, gh run watch bloqueante y polling continuo. Si el usuario pidió seguir hasta terminar, conserva ese objetivo con seguimiento acotado e informa avances; pendiente no es completado.
- Cuando los criterios estén cubiertos, sigue el cierre indicado. Commit local autorizado sin devolver comandos al usuario; push, merge y publicación requieren autorización aplicable. Una sugerencia opcional o un commit sin cambios de contenido no obliga a otra revisión.
- Sin avance, identifica causa y siguiente recuperación concreta antes de repetir una delegación. No inventes presupuestos de tokens ni sacrifiques una comprobación necesaria para aparentar ahorro.`;

export async function setupEfficiency(ctx) {
  if (!ctx.session?.hook) return;
  const registry = globalThis[Symbol.for('skalling.efficiency.instances')] ||= new Set();
  const key = ctx.location?.directory;
  if (!key || registry.has(key)) return;
  registry.add(key);
  const sessions = new Map();
  const budget = createContextBudget(ctx);
  try {
    await ctx.tool?.hook('execute.after', async event => {
      if (!isSkalling(event.agent)) return;
      budget.tool(event.sessionID);
      if (event.tool === 'skalling_workflow' && event.result && typeof event.result === 'object') {
        event.result.metadata = { ...event.result.metadata, skalling_context: budget.report(event.sessionID) };
      }
      if (!event.sessionID || !['shell', 'bash', 'terminal'].includes(event.tool)) return;
      const command = event.input?.command;
      if (typeof command !== 'string') return;
      let state = sessions.get(event.sessionID);
      if (!state) {
        if (sessions.size >= 64) sessions.delete(sessions.keys().next().value);
        sessions.set(event.sessionID, state = { recent: [], repeats: 0 });
      }
      // Hash only; do not retain shell text, output, credentials or file contents.
      const digest = createHash('sha256').update(command).digest('hex');
      state.repeats += Number(state.recent.includes(digest));
      state.recent.push(digest);
      if (state.recent.length > 32) state.recent.shift();
      state.filtered = /\|\s*(?:tail|head|grep|tee)\b/.test(command);
      state.waited = /\bsleep\s+(?:[3-9]\d|\d{3,})(?:s)?\b|\bgh\s+run\s+watch\b/.test(command);
    });
    await ctx.session.hook('context', async event => {
      // Remove only our prior capsule, including when switching to a native agent.
      for (let i = event.system.length - 1; i >= 0; i--) {
        if (event.system[i].metadata?.skalling === marker) event.system.splice(i, 1);
      }
      if (!isSkalling(event.agent)) return;
      await budget.observe(event);
      const state = sessions.get(event.sessionID);
      const hints = [];
      const context = budget.report(event.sessionID);
      if (context?.compaction === 'queued') hints.push('Se solicitó compactación nativa para el próximo punto seguro. Conserva el workflow; no abras otro ni repitas checks tras el resumen.');
      if (['unsupported', 'request_failed'].includes(context?.compaction)) hints.push('El historial supera el umbral de contexto y no se pudo programar la compactación nativa. No bloquees el trabajo ni afirmes que se compactó; conserva el foco en TeamDB.');
      if (state?.filtered) hints.push('La última salida shell fue filtrada: consulta el log existente y comprueba el estado original antes de repetir el comando.');
      if (state?.waited) hints.push('El último comando incluía espera bloqueante: consulta el estado actual antes de programar otra espera.');
      if (state?.repeats) hints.push(`Se observaron ${state.repeats} repeticiones de comandos en esta sesión. No implica que sobren: verifica qué cambió antes de repetir pruebas.`);
      event.system.push({ type: 'text', metadata: { skalling: marker }, text: marker + '\n' + policy + (hints.length ? '\n' + hints.join('\n') : '') });
      return event;
    });
    await ctx.session.hook('compaction', event => {
      if (!budget.report(event.sessionID)) return;
      event.system.push({ type: 'text', text: compactionPolicy });
    });
  } catch (error) {
    registry.delete(key);
    throw error;
  }
  return () => { registry.delete(key); sessions.clear(); budget.clear(); };
}
