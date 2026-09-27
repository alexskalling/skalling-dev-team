import { destructiveTool, setupDataSafetyV2 } from './lib/data-safety.mjs';

// v1: herramienta con aprobación nativa (context.ask). v2: vista previa +
// comando de aplicar que el permiso de la terminal siempre pregunta.
export default {
  id: 'skalling-data-safety',
  // El SDK solo lo usa la v1. Importarlo arriba hacía que OpenCode 2.0.x
  // descartara el plugin entero cuando el paquete no estaba al lado
  // (proyecto preparado con setup.sh, prueba real con 2.0.18).
  server: async () => {
    const { tool } = await import('@opencode-ai/plugin');
    return { tool: { teamdb_destructive: destructiveTool(tool) } };
  },
  setup: async (ctx) => setupDataSafetyV2(ctx),
};
