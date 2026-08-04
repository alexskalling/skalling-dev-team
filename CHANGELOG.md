# Changelog

Todos los cambios notables a Skalling se documentan acá. El formato sigue [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] — 2026-08-04

### Added
- **Concept template What/Why/Where/Learned**: reescrito `templates/okf/concept.template.md` con 4 secciones obligatorias; Pau rechaza docs nuevos sin las 4 secciones (PASO 4 de validación previa al archivo).
- **Memory Protocol snippet**: snippet canónico en `templates/agents/snippets/memory-protocol.md` inyectado en los 8 agentes (`## 🧠 Memory Protocol`) con comment block `SINCRONIZADO CON` para mantenimiento; Pau tiene bloque de consolidación extendido.
- **Conflict detection en Pol**: nueva FASE 5 en `agents-base/Pol.md` que lee concept docs y trabajo-en-curso antes de cerrar la proposal, con 3 escenarios (sin conflictos, con conflictos marcados en `## ⚠️ Conflictos detectados`, bundle corrupto salta el check sin bloquear).
- **`/skalling-forget` con consolidación**: comando reescrito para invocar `mem-review` primero y ofrecer opciones A/B/C/D por candidato (archivar, marcar superseded, consolidar, mantener); log en `.opencode/context/log.md`.
- **`scripts/mem-review.sh`**: nuevo script diagnóstico (duplicados → WIP zombie >30d → stale >6m → superseded) basado en `scripts/lib/lib-memory-check.sh`.
- **`scripts/lib/lib-memory-check.sh`**: helper sourceable con 6 funciones (`skalling_parse_yaml_field`, `skalling_find_orphans`, `skalling_find_zombie_wip`, `skalling_find_duplicates`, `skalling_find_stale`, `skalling_find_superseded`); umbrales configurables via `SKALLING_WIP_ZOMBIE_DAYS` (default 30) y `SKALLING_STALE_MONTHS` (default 6).
- **Sección Memoria en `setup-team-doctor.sh`**: nueva función `check_memory_health()` con 5 chequeos del bundle OKF (huérfanos, WIP zombie, duplicados, stale, superseded vigente).

### Changed
- Doctor: output con nueva fila "Memoria (bundle OKF)" y 5 chequeos automáticos.
- Tests: cobertura completa de las nuevas features (8 tests nuevos, 281 PASS total en regresión).

### Security
- Ningún cambio de superficie de seguridad.

## [0.2.2] — 2026-08-03

### Fixed
- **Falso positivo de `update.sh` en `setup-team-doctor.sh`**: el check usaba una ruta hardcodeada (`$OPENCODE_DIR/../skalling-dev-team/scripts/update.sh`) que asumía el repo viviendo en `~/.config/skalling-dev-team/`. Ahora usa `$SCRIPT_DIR/scripts/update.sh`, basada en la ubicación real del script
- **Banner del instalador**: `install-global.sh` mostraba v0.1.0 hardcodeado. Ahora `SKALLING_VERSION="0.2.2"`

## [0.2.1] — 2026-08-03

### Added
- **Auditoría de Luz aplicada a los 8 agentes**: agentes reescritos con protocolos de escalación, evidencia de verificación y consistencia entre prompts y permisos
- **Teo**: receipts con evidencia (`verification`: comando exacto, exit code y output real) en todo handoff a Jhon; límite de 3 iteraciones en el loop Teo ↔ Jhon (escala a Alex, nunca bloquea en silencio); skills de UI condicionadas al stack del proyecto (solo carga si el framework lo requiere)
- **Alex**: protocolo de escalación con límites por fase (Teo↔Jhon 3, Jhon↔Luz 3, Luz↔Pau 2) y notificación al usuario con opciones A/B/C/D; relay de preguntas subagente → usuario (una a la vez, espera la respuesta y la reinyecta); receipts por ruta (`skalling-receipt`); protocolo R16.4 (muestra archivos y mensaje antes del commit); protocolo de negativa fundamentada ante pedidos que violan la constitución
- **Pol**: relay mode (devuelve preguntas a Alex en formato A/B/C/D, nunca espera respuesta directa del usuario); límite de 3 rondas de preguntas por feature (propone con lo que hay y marca suposiciones); triviales → fast-track a Teo sin plan
- **Pau**: dueña del design-system (R13 — fuente de verdad en `.opencode/context/proyecto/design-system.md`); schema OKF completo (catálogo de 6 tipos + frontmatter obligatorio); ownership de archive (mueve changes completados a `.opencode/changes/archive/<YYYY-MM>/`)
- **Jhon**: `project_context` obligatorio en handoff a Luz; validación de receipts de Teo antes de re-ejecutar; umbral de coverage 80%
- **Sol**: pipeline mode (planifica la feature N+1 mientras Teo ejecuta la N)
- **Luz**: chequeo R13 (coherencia con `design-system.md`); checklist de evidencia con exit codes esperados (eslint, tsc, prettier, npm audit, impeccable); `websearch` para verificar CVEs reales antes de aprobar/rechazar dependencias
- **Jes**: PASO 0 — lee el bundle OKF (concept docs) antes de explicar; usa `websearch` para afirmar hechos externos
- `templates/handoff.schema.json`: campo `verification` (type, command, output_summary, exit_code, tests_total/passed/failed)

### Changed
- Los 8 agentes (`agents-base/*.md`) reescritos según las recomendaciones de la auditoría de Luz
- **Teo**: R16 — commits requieren consentimiento explícito del usuario; permisos `git add*`/`git commit*` en `ask` (antes solo `git push*`)
- **Alex**: Session Start Protocol lee concept docs del bundle OKF (YAML) en lugar de memorias `.jsonl`; permisos ampliados a `.opencode/changes/**/receipts/*.json`
- **Jes**: contradicciones resueltas — la tabla gana: pregunta conceptual → responde directo; hecho externo → busca primero
- **Pol**: sin límite de rondas → máximo 3 (nunca bloquea el ciclo por perfeccionismo)
- **Sol**: lee `.opencode/project.yaml` con la herramienta de lectura (no bash — permiso `bash: deny`); granularidad de tareas ~30 min (unidad verificable por Jhon); archiving delegado a Pau (antes lo hacía Sol)
- **Luz**: valida `project_context` del handoff de Jhon antes de arrancar; veredictos con exit code real de cada comando ejecutado
- `skills-base/skalling-handoff/SKILL.md`: ejemplo de Approval Handoff corregido con `project_context`
- **README**: simplificado y reescrito en lenguaje simple (antes técnico y extenso)

## [0.2.0] — 2026-08-03

### Added
- **`skalling-routing`**: Formato Gentle-AI con Hard Rules + Decision Gates. 6 rutas: INLINE, INTERVENTION, FAST-TRACK, SDD, DIRECT, RESEARCH
- **`skalling-receipt`**: Formaliza verificación en receipts JSON con receipt_id, verification types, delivery gates
- **`skalling-memory`**: Engram-style usando `.jsonl` locales (DECISIONS, PATTERNS, PREFERENCES, REJECTIONS). ~90% token savings
- **Alex actualizado**: Usa Decision Tree de routing, carga skalling-memory al inicio de sesión
- **Skills como core**: Los 3 nuevos skills instalados por `install-global.sh` (data-driven via `skills-by-stack.yaml`)

### Changed
- Alex.md: Detección de intención ahora usa Decision Tree en lugar de tabla estática
- Alex.md: Session Start Protocol carga memorias relevantes con grep

## [0.1.0] — 2026-07-28

### Added
- **Comando `/skalling-update`**: busca cambios en el repo remoto, muestra changelog, pide permiso y actualiza la instalación.
- **`scripts/update.sh`**: script bash para el update automático con confirmación del usuario.
- **R16**: commits requieren permiso explícito del usuario y mensajes descriptivos en español.
- **R13**: DESIGN.md reubicado de `docs/design/` a `.opencode/context/proyecto/design-system.md` (no se commitea).
- **Detección de intención de Alex**: tabla expandida con consulta directa, auditoría a Luz, operaciones git y catch-all con opciones.
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
- **Pipeline Mode**: Sol puede planificar siguiente feature mientras Teo ejecuta la actual (parallelization)
- **`project_context` en handoff**: Schema actualizado para incluir stack, has_ui, design_system_exists, okf_bundle_valid

### Changed
- Frontmatter de agentes: `mode: primary|subagent`, `permission:` con reglas finas (reemplaza `tools:` deprecated)
- `Alex.md`: prompt magro (~150 líneas), Constitución separada
- `Sol.md` y `Teo.md`: paths corregidos a `.opencode/changes/<feature-slug>/` (antes `.opencode/plans/`)
- `Luz.md`: bash permission permite `npx impeccable *` (antes deny total)
- `setup.sh`: default = cwd con warning (antes directorio padre)
- `install-global.sh`: instala también `gitattributes.template`
- `Alex.md`: OKF Checkpoint obligatorio antes de derivar agentes (R12 enforcement)
- `Sol.md`: Handoff a Teo incluye `project_context` obligatorio
- `Teo.md`: Carga de contexto de proyecto obligatoria antes de implementar
- `skalling-handoff/SKILL.md`: Agregado Project Context Handoff como requerido
- `skalling-cycle/SKILL.md`: Agregado Pipeline Mode para parallelization
- `templates/handoff.schema.json`: Agregado `project_context` como propiedad opcional

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
- **Teo responde vacío**: Handoff ahora incluye `project_context` para transferir contexto del proyecto

## [0.1.0] — 2026-07-28

### Added
- Installer inicial con 8 agentes (Alex primary + 7 subagents)
- 14 skills base (test-driven-development, systematic-debugging, etc.)
- Constitución con 13 reglas base
- Templates OKF (6 tipos: Concept, Decision, Preference, Workaround, WorkInProgress, Context)
- `setup.sh` inicial (legacy, sin idempotencia)

[Unreleased]: https://github.com/tu-usuario/skalling-dev-team/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.3.0
[0.2.2]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.2.2
[0.2.1]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.2.1
[0.1.0]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.1.0
