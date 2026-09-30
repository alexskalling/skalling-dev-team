import { readPolicy, setupModelFallback } from './lib/model-fallback.mjs';

export default {
  id: 'skalling-model-fallback',
  setup: setupModelFallback,
  server: async () => {
    if (Object.keys(readPolicy()).length) {
      throw new Error('Skalling fallback requiere OpenCode 2.0.18; OpenCode v1 no ofrece este mecanismo de recuperación.');
    }
    return {};
  },
};
