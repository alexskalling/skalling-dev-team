INSERT INTO schema_meta(key, value)
VALUES ('legacy_surface.work_in_progress', 'read_only_compatibility')
ON CONFLICT(key) DO UPDATE SET value=excluded.value;

INSERT INTO schema_meta(key, value)
VALUES ('legacy_surface.code_graph_cache', 'external_codegraph')
ON CONFLICT(key) DO UPDATE SET value=excluded.value;

INSERT INTO schema_meta(key, value)
VALUES ('legacy_surface.code_imports', 'external_codegraph')
ON CONFLICT(key) DO UPDATE SET value=excluded.value;

UPDATE schema_meta SET value = '0.10.2' WHERE key = 'version';
