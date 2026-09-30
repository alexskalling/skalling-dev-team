-- v0.15.0: objective/coverage/feedback live in versioned workflow JSON.
-- No existing workflow history or human memory is rewritten.
UPDATE schema_meta SET value = '0.15.0' WHERE key = 'version';
