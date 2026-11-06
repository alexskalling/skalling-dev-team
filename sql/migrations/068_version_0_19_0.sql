-- Release marker only; preserve workflows and memory.
UPDATE schema_meta SET value = '0.19.0' WHERE key = 'version';
