import { setupGuardV2 } from './lib/git-guard.mjs';

// Integración exclusiva para OpenCode 2.
export default {
  id: 'skalling-git-guard',
  setup: setupGuardV2,
};
