-- v0.14.0: cierre de la auditoría de preparación para producción (27-09-2026).
--
-- Sin cambios de schema. Cambia quién puede sellar un receipt: además de
-- jhon, luz y auto, el verificador "humano" (skalling-approve.sh, una persona
-- en su terminal fuera de OpenCode) corre el test real sobre lo staged igual
-- que Jhon y el gate lo acepta con la misma evidencia calculada.
UPDATE schema_meta SET value = '0.14.0' WHERE key = 'version';
