import { tool } from '@opencode-ai/plugin';
import { workflowTool, blocksDirectWorkflowScript, setupWorkflowV2 } from './lib/workflow.mjs';

// v1: herramienta con aprobación nativa del check. v2: los checks que la
// política del agente ya permite corren; los que pedirían aprobación se
// rechazan (un plugin v2 no puede preguntar). El bloqueo del script crudo en
// v2 lo hace skalling-git-guard (mismo chequeo).
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
  setup: async (ctx) => setupWorkflowV2(ctx),
};
