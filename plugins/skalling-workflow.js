import { tool } from '@opencode-ai/plugin';
import { workflowTool, blocksDirectWorkflowScript } from './lib/workflow.mjs';

// OpenCode v2: su API de plugins (2.0.18) no da una forma de que una
// herramienta pida al humano una aprobación exacta como context.ask de la v1.
// Hasta tenerla, en v2 skalling_workflow no se registra (falla cerrado: nada se habilita
// sin aprobación); `setup` existe para que la v2 cargue el archivo sin error.
// El bloqueo del script crudo en v2 lo hace skalling-git-guard (mismo chequeo).
export default {
  id: 'skalling-workflow',
  server: async () => ({
    tool: {skalling_workflow:workflowTool(tool)},
    'tool.execute.before': async (input, output) => {
      if (input.tool !== 'bash') return;
      if (blocksDirectWorkflowScript(output.args.command || '')) {
        throw new Error('Use skalling_workflow: identidad y evidencia provienen del runtime, no de --by ni de variables shell.');
      }
    },
  }),
  setup: async () => {},
};
