-- v0.15.1: failover policy belongs to the OpenCode installation, not project memory.
UPDATE schema_meta SET value = '0.15.1' WHERE key = 'version';
