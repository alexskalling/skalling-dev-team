import { tool } from '@opencode-ai/plugin';
import { destructiveTool } from './lib/data-safety.mjs';

export const SkallingDataSafety = async () => ({
  tool: { teamdb_destructive: destructiveTool(tool) },
});
