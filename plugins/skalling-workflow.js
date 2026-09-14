import { tool } from '@opencode-ai/plugin';
import { workflowTool, blocksDirectWorkflowScript } from './lib/workflow.mjs';

export const SkallingWorkflow = async () => ({
  tool: {skalling_workflow:workflowTool(tool)},
  'tool.execute.before': async (input, output) => {
    if (input.tool !== 'bash') return;
    if (blocksDirectWorkflowScript(output.args.command || '')) {
      throw new Error('Use skalling_workflow: identidad y evidencia provienen del runtime, no de --by ni de variables shell.');
    }
  },
});
