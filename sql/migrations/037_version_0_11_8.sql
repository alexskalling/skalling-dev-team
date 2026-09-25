-- v0.11.8: tests/mirror-parity.test.sh vigila los dos mecanismos de espejo
-- de archivos que no tenían cobertura (agents-base/*.md -> .opencode/
-- agents/*.md vía render-agent.sh, y scripts/hooks/* -> .opencode/hooks/*
-- copia cruda). Encontrado al escribirlo: .opencode/agents/Alex.md tenía
-- "hidden: true" colado por accidente en un commit anterior cuyo mensaje no
-- lo mencionaba -- rompía el patrón real (hidden: true es para agentes
-- internos como Jhon/Pau/Luz, nunca para Alex, el orquestador de cara al
-- usuario). Corregido regenerando el espejo desde agents-base/Alex.md.
-- Sin cambios de schema; solo eleva la versión declarada.
UPDATE schema_meta SET value = '0.11.8' WHERE key = 'version';
