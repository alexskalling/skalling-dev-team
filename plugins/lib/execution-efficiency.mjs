// Advisory only: never changes commands, permissions, agent identity or results.
// No filesystem, network, subprocess or model calls on the execution path.
import { createHash } from 'node:crypto';

export const marker = 'SKALLING_EXECUTION_EFFICIENCY';
const skallingAgents = new Set(['alex', 'pol', 'sol', 'teo', 'jhon', 'luz', 'jes', 'pau']);
const isSkalling = agent => typeof agent === 'string' && skallingAgents.has(agent.toLowerCase());
export const policy = `Trabaja con la menor latencia compatible con el resultado pedido y las verificaciones necesarias.
- Resuelve primero el alcance y el criterio observable usando contexto ya disponible. Consulta memoria vigente y después solo los archivos o el estado remoto necesarios. No conviertas una pregunta en implementación ni añadas infraestructura de despliegue sin comprobar la existente.
- Agrupa lecturas y consultas independientes en una llamada cuando sea posible. Paraleliza solo operaciones independientes; no escrituras sobre el mismo estado ni operaciones dependientes.
- Al ejecutar pruebas, guarda toda la salida en un log temporal privado y conserva el código de salida original. Lee ese log para investigar fallos; nunca repitas una suite solo porque tail/grep ocultó su salida. No uses el éxito de tail/tee/grep como éxito del test o de Git. Si usas un pipe, conserva explícitamente el estado del productor; pipefail puede detectar errores pero head también puede provocar SIGPIPE.
- Durante una corrección ejecuta las pruebas afectadas. Reutiliza evidencia solo si comando, código, configuración, dependencias y entorno pertinentes no cambiaron. Ejecuta la validación final requerida una vez por candidato; un commit por sí solo no exige repetirla si conserva esos mismos contenidos. Un resultado verde no prueba criterios que la prueba no cubre.
- Consulta CI antes de esperar. No uses sleep largo ni gh run watch bloqueante para ocultar minutos de espera. Si sigue pendiente, informa el estado y usa seguimiento en segundo plano solo si el entorno realmente permite reanudar o notificar. Si el usuario pidió esperar hasta terminar, mantén un seguimiento acotado con avances; no declares completado ni abandones ese objetivo por estar pendiente. No hagas polling continuo.
- Distingue cambio verificado, commit local, push y despliegue: cada uno requiere evidencia propia. Ejecuta los commits autorizados sin mandar comandos al usuario. Push, merge y publicación requieren autorización aplicable del usuario; nunca la infieras de esta política. No amplíes una corrección local a PR/deploy salvo que el objetivo lo requiera.
- Ante un rechazo, reúne todos los hallazgos pendientes y corrígelos juntos. No reinicies la investigación ni delegues de nuevo solo para repetir lecturas o pruebas disponibles.`;

export async function setupEfficiency(ctx) {
  if (!ctx.session?.hook) return;
  const registry = globalThis[Symbol.for('skalling.efficiency.instances')] ||= new Set();
  const key = ctx.location?.directory;
  if (!key || registry.has(key)) return;
  registry.add(key);
  const sessions = new Map();
  try {
    await ctx.tool?.hook('execute.after', async event => {
      if (!isSkalling(event.agent)) return;
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
      const state = sessions.get(event.sessionID);
      const hints = [];
      if (state?.filtered) hints.push('La última salida shell fue filtrada: consulta el log existente y comprueba el estado original antes de repetir el comando.');
      if (state?.waited) hints.push('El último comando incluía espera bloqueante: consulta el estado actual antes de programar otra espera.');
      if (state?.repeats) hints.push(`Se observaron ${state.repeats} repeticiones de comandos en esta sesión. No implica que sobren: verifica qué cambió antes de repetir pruebas.`);
      event.system.push({ type: 'text', metadata: { skalling: marker }, text: marker + '\n' + policy + (hints.length ? '\n' + hints.join('\n') : '') });
      return event;
    });
  } catch (error) {
    registry.delete(key);
    throw error;
  }
  return () => { registry.delete(key); sessions.clear(); };
}
