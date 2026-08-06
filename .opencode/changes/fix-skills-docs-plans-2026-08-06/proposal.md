<!-- GENERATED from teamdb on 2026-08-06T05:01:40Z. DO NOT EDIT. Source of truth: .opencode/context/team.db.
     Bidirectional is PROHIBITED. To update DB: sqlite3 $DB (proposals table).
     To regenerate: bash scripts/teamdb-export-md.sh . -->

# Proposal: fix-skills-docs-plans-2026-08-06

- **Slug:** fix-skills-docs-plans-2026-08-06
- **Title:** Fix: skills brainstorming y writing-plans deben guardar en DB, no en docs/plans/
- **Status:** draft
- **Agent:** pol
- **Created:** 2026-08-06 05:01:08

## Intent

## Contexto

Las 2 skills copiadas de Superpowers (brainstorming, writing-plans) todavía tienen paths legacy (`docs/plans/`) y referencias externas (`superpowers:*`). El protocolo Skalling v0.7+ exige que TODO se guarde en la DB (`.opencode/context/team.db`) como source of truth, y SOLO se exporte a `.md` cuando es para git legible.

## Causa raíz

- Skills copiadas parcialmente en versiones tempranas
- Mismo bug que Sol.md/Teo.md tenían pre-0.6.2 (ya parcheado, ver CHANGELOG)
- Nunca se extendió el fix a las skills
- Tests/setup.test.sh Tier 1 FIX 1.1 lo valida para agentes pero no para skills

## Solución propuesta

### Skill 1: brainstorming/SKILL.md
- ELIMINAR: "Write the validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`"
- ELIMINAR: refs a `superpowers:using-git-worktrees`, `superpowers:writing-plans`
- REEMPLAZAR por: "Pol devuelve proposal validado a Alex. Source of truth: tabla `proposals` en team.db (vía `teamdb_write_project`). El export `.md` se genera on-demand con `teamdb_export_md`, no es storage primario."

### Skill 2: writing-plans/SKILL.md
- ELIMINAR: refs a `docs/plans/` (líneas 18, 101)
- ELIMINAR: refs a `superpowers:*` (líneas 36, 110, 116)
- REEMPLAZAR por: "Sol escribe `design.md` y `tasks.md` después de INSERT en DB vía `teamdb-plan.sh`. Source of truth: tabla `plans` + `tasks` en team.db."

### Tests nuevos (en tests/setup.test.sh)
- `test_skills_no_docs_plans`: assert NO `docs/plans` en ninguna SKILL.md
- `test_skills_no_superpowers`: assert NO `superpowers:` (excepto whitelist explícita)
- `test_brainstorming_uses_db`: assert que menciona `team.db` o `teamdb_write_project`

## Tasks

- [ ] Reescribir brainstorming/SKILL.md
- [ ] Reescribir writing-plans/SKILL.md
- [ ] Agregar 3 tests en tests/setup.test.sh
- [ ] Correr `bash install-global.sh --force` para distribuir
- [ ] Verificar que ningún proyecto use el path legacy

## Consecuencias

### Positivas
- TODO el flujo de brainstorming va a la DB, no al filesystem
- Consistencia con el resto del sistema
- Rastreable, versionado, auditable
- Backup automático ya aplica (v0.7.6)

### Negativas / Riesgos
- Si algún proyecto cliente tiene archivos en `docs/plans/` viejos, hay que migrarlos manualmente con `teamdb-plan.sh` por cada uno
- Hay 3 menciones de `superpowers:` en `systematic-debugging/SKILL.md` que hay que evaluar caso por caso

## Related

- CHANGELOG 0.6.2: fix similar aplicado a Sol.md/Teo.md
- tests/setup.test.sh FIX 1.1: patrón Tier 1 a replicar
- constitution R6: ubicación canónica `.opencode/changes/<feature-slug>/`


<!-- Footer: regenerar desde DB con scripts/teamdb-export-md.sh -->
