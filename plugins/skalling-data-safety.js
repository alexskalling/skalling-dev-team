import { tool } from '@opencode-ai/plugin';
import { destructiveTool } from './lib/data-safety.mjs';

// OpenCode v2: su API de plugins (2.0.18) no da una forma de que una
// herramienta pida al humano una aprobación exacta como context.ask de la v1.
// Hasta tenerla, en v2 esto no se registra (falla cerrado: nada se habilita
// sin aprobación); `setup` existe para que la v2 cargue el archivo sin error.
export default {
  id: 'skalling-data-safety',
  server: async () => ({ tool: { teamdb_destructive: destructiveTool(tool) } }),
  setup: async () => {},
};
