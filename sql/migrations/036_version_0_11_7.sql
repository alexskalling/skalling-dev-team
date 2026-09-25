-- v0.11.7: teamdb-plan.sh corre teamdb-task-groups.sh automáticamente al
-- crear un plan y anota en design_md (+ plan_history versionado) qué tasks
-- quedan sin vínculo entre sí (candidatas a un worktree cada una) y cuáles
-- deben ir en secuencia. Antes, el detector existía pero nadie lo invocaba
-- solo: dependía de que un humano se acordara de correrlo a mano, así que no
-- generaba ningún valor real hasta que alguien lo usara manualmente.
-- Sin cambios de schema; solo eleva la versión declarada.
UPDATE schema_meta SET value = '0.11.7' WHERE key = 'version';
