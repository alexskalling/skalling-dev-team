import { workflowTool, blocksDirectWorkflowScript, setupWorkflowV2 } from './lib/workflow.mjs';

// v1: herramienta con aprobación nativa del check. v2: los checks que la
// política del agente ya permite corren; los que pedirían aprobación se
// rechazan (un plugin v2 no puede preguntar). El bloqueo del script crudo en
// v2 lo hace skalling-git-guard (mismo chequeo).
export default {
  id: 'skalling-workflow',
  // El SDK solo lo usa la v1: importado arriba, OpenCode 2.0.x descartaba el
  // plugin (y la herramienta skalling_workflow no existía para los agentes)
  // cuando el paquete no estaba al lado. Prueba real con 2.0.18.
  server: async () => ({
    tool: {skalling_workflow:workflowTool((await import('@opencode-ai/plugin')).tool)},
    'tool.execute.before': async (input, output) => {
      if (input.tool !== 'bash') return;
      if (blocksDirectWorkflowScript(output.args.command || '')) {
        throw new Error('Use skalling_workflow: identidad y evidencia provienen del runtime, no de --by ni de variables shell.');
      }
    },
  }),
  setup: async (ctx) => setupWorkflowV2(ctx),
};
