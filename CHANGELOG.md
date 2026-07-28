# Changelog

Todos los cambios notables a Skalling se documentan acá. El formato sigue [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Fase 13**: Regla R14 — Escalera de Ponytail (integrada de [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail))
- **Fase 12**: Bridge skill `skalling-impeccable-bridge` para integrar con [Impeccable](https://impeccable.style/)
- **Fase 11**: Comandos `/skalling-status`, `/skalling-refresh`, `/skalling-doctor`, `/skalling-forget`, `/skalling-merge`
- **Fase 8**: Memoria persistente por proyecto en formato [OKF v0.1](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf) con extensiones v0.2 (agent, confidence, supersedes)
- **Fase 8**: `bootstrap-context.sh` con detección data-driven desde `data/stack-detectors.yaml`
- **Fase 5**: 4 skills propios `skalling-*` (cycle, handoff, ponytail, impeccable-bridge)
- **Fase 4**: SDD formal con templates `proposal/spec/design/tasks` + JSON Schema para handoffs
- **Fase 3**: `install-global.sh` + `setup.sh` (idempotente con backup + dedup + prune)
- **Fase 3**: `setup-team-doctor.sh` para health check
- **Fase 15**: Regla R15 — Resolución de Conflictos Colaborativos vía `.gitattributes`
- **Fase 15**: `scripts/merge-helper.sh` + `command/skalling-merge.md`
- **Fase 11**: Wrappers PowerShell `.ps1` para Windows (`install-global.ps1`, `setup.ps1`, `bootstrap-context.ps1`, `setup-team-doctor.ps1`)
- **Fase 11**: `scripts/lib/lib-os.sh` con detección de OS (macOS, Linux, WSL, Git Bash, Windows)
- **Tests**: 130+ tests automatizados en `tests/setup.test.sh`
- **R14**: Constitución universal con 15 reglas (R1-R15)
- **R13**: DESIGN.md obligatorio para proyectos con interfaz gráfica

### Changed
- Frontmatter de agentes: `mode: primary|subagent`, `permission:` con reglas finas (reemplaza `tools:` deprecated)
- `Alex.md`: prompt magro (~150 líneas), Constitución separada
- `Sol.md` y `Teo.md`: paths corregidos a `.opencode/changes/<feature-slug>/` (antes `.opencode/plans/`)
- `Luz.md`: bash permission permite `npx impeccable *` (antes deny total)
- `setup.sh`: default = cwd con warning (antes directorio padre)
- `install-global.sh`: instala también `gitattributes.template`

### Removed
- `active.lock` (era documentación sin implementación)
- `data/stack-detectors.yaml` y `data/skills-by-stack.yaml` ahora son data files activos (antes eran documentación inerte)
- Flavor text "Frase Típica" de Alex.md

### Fixed
- Inconsistencia: Sol.md y Teo.md referenciaban `.opencode/plans/` legacy pero constitución R6 exigía `.opencode/changes/<feature-slug>/`
- Permisos: Luz tenía `bash: deny` pero prompt decía que ejecuta `npx impeccable`
- `set -u` crash con `$MSYSTEM` unbound en macOS — ahora usa `${MSYSTEM:-}`
- `sed -i.bak` no portable — reemplazado por `skalling_sed_inplace` (helper con macOS vs Linux)
- Bootstrap no detectaba correctamente stack desde YAML — ahora data-driven

## [0.1.0] — 2026-07-28

### Added
- Installer inicial con 8 agentes (Alex primary + 7 subagents)
- 14 skills base (test-driven-development, systematic-debugging, etc.)
- Constitución con 13 reglas base
- Templates OKF (6 tipos: Concept, Decision, Preference, Workaround, WorkInProgress, Context)
- `setup.sh` inicial (legacy, sin idempotencia)

[Unreleased]: https://github.com/tu-usuario/skalling-dev-team/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.1.0
