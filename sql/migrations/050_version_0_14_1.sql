-- v0.14.1: /skalling-init instala el proyecto completo (27-09-2026).
--
-- Sin cambios de schema. bootstrap-context.sh --install-project (lo usa
-- /skalling-init) instala agentes, plugins, scripts y hooks en el proyecto con
-- el setup.sh del checkout registrado por install-global.sh, y los controles
-- (hooks, Alex por defecto) se activan aunque el contexto esté incompleto.
UPDATE schema_meta SET value = '0.14.1' WHERE key = 'version';
