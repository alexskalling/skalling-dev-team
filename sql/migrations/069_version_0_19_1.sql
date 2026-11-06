-- Release marker only; keep audit findings and existing workflow history.
UPDATE schema_meta SET value = '0.19.1' WHERE key = 'version';
