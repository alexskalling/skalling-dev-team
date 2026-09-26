import { tool } from '@opencode-ai/plugin';
import { destructiveTool, setupDataSafetyV2 } from './lib/data-safety.mjs';

// v1: herramienta con aprobación nativa (context.ask). v2: vista previa +
// comando de aplicar que el permiso de la terminal siempre pregunta.
export default {
  id: 'skalling-data-safety',
  server: async () => ({ tool: { teamdb_destructive: destructiveTool(tool) } }),
  setup: async (ctx) => setupDataSafetyV2(ctx),
};
