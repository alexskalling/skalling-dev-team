-- Memoria instalada no certifica comprensión del proyecto ni del pedido.
UPDATE schema_meta SET value='initialized' WHERE key='project_readiness' AND value='ready';
UPDATE schema_meta SET value = '0.10.4' WHERE key = 'version';
