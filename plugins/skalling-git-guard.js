import { createGuard, setupGuardV2 } from './lib/git-guard.mjs';

// Un solo default export sirve a las dos versiones de OpenCode: la v1 usa la
// función `server` (hooks tool.execute.before, shell.env...), la v2 usa
// `setup` (ctx.tool.hook / ctx.shell.hook). Sin otros exports: la v1 trata
// cada export del archivo como un plugin.
export default {
  id: 'skalling-git-guard',
  server: async () => createGuard(),
  setup: async (ctx) => setupGuardV2(ctx),
};
