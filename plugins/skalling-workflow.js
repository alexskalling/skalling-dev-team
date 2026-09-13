import { tool } from '@opencode-ai/plugin';
import { workflowTool } from './lib/workflow.mjs';

export const SkallingWorkflow = async () => ({
  tool: {skalling_workflow:workflowTool(tool)},
  'tool.execute.before': async (input, output) => {
    if (input.tool !== 'bash') return;
    const command = output.args.command || '';
    if (/skalling-workflow\.py|teamdb-claim\.sh[^\n]*--advance|teamdb-seal-receipt\.sh/.test(command)) {
      throw new Error('Use skalling_workflow: identidad y evidencia provienen del runtime, no de --by ni de variables shell.');
    }
  },
});
