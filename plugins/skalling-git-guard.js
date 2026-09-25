import { blocksChainedSensitiveGit } from './lib/git-guard.mjs';

export const SkallingGitGuard = async () => ({
  'tool.execute.before': async (input, output) => {
    if (input.tool !== 'bash') return;
    if (blocksChainedSensitiveGit(output.args.command || '')) {
      throw new Error(
        'git push/reset/clean/checkout/restore/commit/"branch -d|-D"/"worktree remove|prune" ' +
        'no pueden ir encadenados con && / ; / | en el mismo comando -- un patrón "allow" más ' +
        'amplio (como "git add *") matchea la cadena completa y evita el permiso "ask" ya ' +
        'configurado para esa operación. Correr esa operación de git como su propio bash call.'
      );
    }
  },
});
