-- v0.14.3: fix placeholders rotos en ejemplos JSON y coherencia de versión (28-09-2026).
--
-- 0.14.2 cambió los ejemplos de handoff a "números reales que devolvió
-- teamdb-plan.sh", pero el schema exige integer y el placeholder era string:
-- context-regressions rompió. 0.14.3 quita la línea `plan_id` de los ejemplos
-- (no está en required del schema), renombra la migración de versión y alinea
-- todos los loci a 0.14.3.
UPDATE schema_meta SET value = '0.14.3' WHERE key = 'version';
