-- Migration 006: teamdb-link.sh (grafo auto-enlazado) (v0.7.4)
-- No cambia schema: el grafo usa concepts/decisions/memory_tags/memory_links
-- que ya existen. Solo avanza schema_meta.version. Idempotente.
UPDATE schema_meta SET value = '0.7.6' WHERE key = 'version';
