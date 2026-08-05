# Changelog

Todos los cambios notables a Skalling se documentan acá. El formato sigue [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.2] — 2026-08-05

### Added
- **Ciclo de planificación en DB**: `scripts/teamdb-plan.sh` (crea filas en `proposals`, `plans`, `tasks`), `teamdb-status.sh` (resume del plan activo), `teamdb-resume.sh`, `teamdb-execute-plan.sh` (descubre/orquesta la próxima task; NO ejecuta shell arbitrario desde la DB — DC-3), `teamdb-amend.sh` (amendment atómico in-place con version/historial en `plan_history` y preservación de tasks aprobadas como inmutables), `teamdb-deps.sh` (DAG con `task_dependencies`, detección de ciclos y query `runnable`), `teamdb-claim.sh` (claim atómico con lease/attempt/input_hash + resume), `teamdb-context.sh` (context capsules para handoff de Teo), `teamdb-export-md.sh` (markdown GENERADO desde DB, sin escritura bidireccional)
- **Tablas nuevas** en `sql/project-schema.sql` (migration `003_add_dag_claims_history.sql`): `task_dependencies`, `task_claims`, `plan_history`, `task_context_capsules`
- **SQL parametrizado real**: `scripts/teamdb_exec.py` (wrapper Python `sqlite3` con bound params) — `teamdb_safe_query` queda deprecated. Escrituras con transacciones `BEGIN IMMEDIATE` + WAL + `busy_timeout` en `teamdb_write_project`/`teamdb_write_global` (reemplaza flock)
- **FTS5 para `known_problems`**: virtual table `problems_fts` + triggers sync (`teamdb-search.sh` la usa)
- **Snippets single-source (DC-2)**: markers `@include-snippet` en los 8 agentes, resolución build-time en `install-global.sh::resolve_snippets`; canónicos en `templates/agents/snippets/`
- **Handoff schema condicional**: `templates/handoff.schema.json` con `allOf` if/then — `project_context` required cuando `to` ∈ {TEO, LUZ}; `verification` required cuando `to` ∈ {JHON, LUZ} (o emisor de ingeniería)
- **`audit_log.actor_source`**: columna nueva (`'helper'` vía `teamdb_write_*`, `'trigger'` en 12 triggers reescritos); plumbing de `TEAMDB_ACTOR`
- **CI**: `.github/workflows/tests.yml` ampliado con 22 suites teamdb + 3 workflows nuevos (`teamdb-sqli.yml`, `handoffs.yml`, `teamdb-dag-claims.yml`) = 4 workflows en cada PR
- **Suite agregadora** `tests/teamdb-hardening-suite.sh` (regresión completa 45/45)
- **Tests nuevos**: version-coherence, portability-bash32, snippets-sync, install-resolves-snippets, handoff-schema-validation, agents-teamdb-integration, dag-tables, amend-full, deps-dag, claim-lease/strict/history, export-md, context-capsule/issue8, cycle-amended, execute-plan-no-shell, migration-003-unique, plan-atomic-idempotent, python-bindparams, write-wal, export-audit, migrate-md-preserve

### Changed
- `scripts/teamdb-search.sh` y `teamdb-related.sh` parametrizados (sin interpolación; whitelist de tipos en related)
- `agents-base/Alex.md` y `agents-base/Jes.md`: TeamDB preferente para cargar contexto (fallback legacy)
- `scripts/teamdb-migrate.sh`: SQL parametrizado + preserva `.md` (solo mueve `.jsonl` a `legacy/` — DC-1)
- `scripts/teamdb-export.sh` exporta también `audit_log` y `schema_meta`
- `scripts/build-schema.sh` (nuevo): estampa SOLO la fila `schema_meta.version` desde `VERSION` (AD-4 corregido)
- Hooks `pre-commit`/`post-merge`: resuelven paths absolutos con `git rev-parse --show-toplevel` (sin `$SCRIPT_DIR/../`)
- `install-global.sh`: instala todos los `teamdb-*.sh` dinámicamente + hooks ejecutables sin `|| true` silenciadores

### Fixed
- **SQL injection** en `teamdb-search.sh` y `teamdb-related.sh`: entradas del usuario pasan por bound params reales (Python `sqlite3`), no escape manual
- Fixes del quality gate de Luz (H1/H2/M1-M5, commit `cfbf3f3`) y fix menor de handoff-schema (`6ad8944`): el test de schema deja de saltar silenciosamente si `jsonschema` falta

## [0.7.0] — 2026-08-05

### Added
- **libSQL como fuente de verdad**: 2 DBs (global + proyecto) con esquema formal
- **Schema global** (`sql/global-schema.sql`): 8 tablas para agents_meta, skills_active, constitution_rules, user_preferences, stack_cache, projects_index
- **Schema proyecto** (`sql/project-schema.sql`): 12 tablas + FTS5 + triggers para concepts, decisions, preferences, known_problems, work_in_progress, memory_tags, memory_links, audit_log
- **Jerarquía plan/feature/task** en `work_in_progress` (columnas `type`, `parent_id`)
- **Grafo de relaciones**: `memory_links` (extends/contradicts/uses/supersedes/related) + `memory_tags`
- **FTS5**: búsqueda full-text en conceptos, decisiones y WIP
- **Triggers automáticos**: mantienen FTS5 sincronizado con tablas base
- **Audit log automático**: registra cada cambio
- **lib-teamdb.sh**: wrapper bash con `flock` para multi-writer seguro
- **teamdb-init.sh**: inicializa DB proyecto
- **teamdb-migrate.sh**: migra `.jsonl` legacy a DB
- **teamdb-export.sh**: DB → `.sql` para git
- **teamdb-import.sh**: `.sql` → DB
- **wip-tree.sh**: visualizador recursivo plan/feature/task con estados derivados
- **30 tests** en `tests/teamdb.test.sh` (8 schemas + 7 scripts + 5 E2E + 7 FTS5/jerarquía + 3 fixes audit/migrate/import)

### Changed
- `install-global.sh`: instala teamdb global (DB + scripts)
- `bootstrap-context.sh`: inicializa teamdb proyecto
- `Pau.md`: documenta uso real de teamdb con queries

### Fixed
- **SQL injection en `teamdb-migrate.sh`**: helper `sql_escape` con `sed "s/'/''/g"` aplicado a todos los campos JSON antes de interpolación SQL. Migración segura de `.jsonl` legacy.
- **Audit log triggers implementados**: 12 triggers (4 tablas × INSERT/UPDATE/DELETE) registran cada cambio en `audit_log` con timestamp, agent, action, table, row_id y details en JSON.
- **flock wrappea escrituras (`teamdb_write_project`)**: nueva función en `lib-teamdb.sh` que toma lock de flock con timeout 5s antes de ejecutar INSERT/UPDATE/DELETE. Previene race conditions en escrituras concurrentes. Usada en `teamdb-migrate.sh`.
- **Import en DB existente**: `teamdb-import.sh` ahora extrae solo líneas `INSERT INTO` del dump SQL (con `grep -E "^INSERT INTO "`), evitando conflicto con `CREATE TABLE` que ya existe. Importa idempotentemente con warnings por tabla que falle.
- **`install-global.sh` lee VERSION dinámico**: ya no tiene `SKALLING_VERSION="0.6.2"` hardcodeado; lee de `VERSION` file via `grep '__version__' | sed`. Mismo fix en `setup-team-doctor.sh`.
- **Doctor chequea teamdb**: nueva sección `check_teamdb()` valida `team.db` global y per-project contra VERSION, y verifica que los 12 audit triggers estén activos. Advierte si hay mismatch.
- **`.gitattributes` para `.sql` merge**: `data_*.sql` usa `merge=union` (cada INSERT es idempotente, conservar ambas líneas es seguro).
- **Hooks se activan automáticamente**: `bootstrap-context.sh` llama nueva función `activate_teamdb_hooks()` que copia `pre-commit` y `post-merge` a `.git/hooks/` y los hace ejecutables.
- **`wip-tree.sh` SQL escape**: helper `sql_escape` aplicado a `parent_slug` antes de la query. Previene crash cuando un slug contiene comillas.
- **`post-merge` no suprime errores**: removido `2>/dev/null || true`. Errores de import ahora son visibles en consola (la salud de teamdb es importante).

### Removed
- `sql/migrations/001_add_wip_hierarchy.sql`: dead code. La jerarquía `type`/`parent_id` ya está en `sql/project-schema.sql` desde v0.7.0 inicial. Directorio `sql/migrations/` vacío eliminado.

### Migration Guide v0.6.x → v0.7.0
1. `git pull origin teamdb`
2. `bash install-global.sh` (instala teamdb global automáticamente)
3. Por cada proyecto: `bash bootstrap-context.sh` (crea team.db proyecto + activa hooks)
4. Los archivos `.jsonl` legacy se migran automáticamente a la DB
5. Verificar instalación: `bash setup-team-doctor.sh`

## [0.6.2] — 2026-08-04

### Changed
- **Refactor de Alex (orquestador)**: delegación directa por rol. Eliminada la fricción de pedir permiso antes de delegar a otros agentes. Nueva tabla de despacho intención → agente → permiso en `agents-base/Alex.md`. Catch-all refactorizado para preguntar QUÉ quiere el usuario, no QUÉ agente.
- **Anti-patrones explícitos en Alex**: ya no pregunta "¿te parece bien?" antes de delegar, ni ofrece opciones de agente, ni repite el trabajo del equipo.
- **R16 reforzado**: Alex escribe el mensaje del commit en español siguiendo Conventional Commits.

### Fixed
- Bundle global: install-global.sh ahora copia `scripts/spec-memory-link.sh` y `scripts/skalling-drift.sh` (v0.6.1 ya había intentado el fix pero quedó incompleto hasta aquí).

## [0.6.0] — 2026-08-04

### Added
- **`scripts/spec-memory-link.sh`**: CLI de Pau para enlazar concept docs (`docs/`, `.opencode/context/concept/*.md`) a la spec archivada que los originó. Detecta paths literales en `proposal.md`, `design.md`, `tasks.md` y `specs/*.md` mediante el regex `\.opencode/context/concept/[A-Za-z0-9._-]+\.md`, descarta matches con traversal/espacios/nombre vacío, valida existencia, deduplica y aplica un footer `## Spec original` con link relativo hardcodeado (`../../changes/archive/<YYYY-MM>/<slug>/`) al path final del plan. Escritura atómica con `mktemp` + `mv`; idempotente (segundo run preserva el primero); portable con Bash 3.2.
- **`tests/spec-memory-link.test.sh`**: cobertura autocontenida de estructura, argv inválido, detección por archivo, regex con/sin prefijo repo, deduplicación, validación de path, cálculo de path relativo, formato exacto del footer, idempotencia 2-run y 3-run, preservación del primero, errores por archivo, integración con Pau, integración informativa del doctor, portabilidad Bash 3.2 e identificadores R1.
- **Integración informativa del doctor**: línea `ℹ` (azul, no bloqueante) sobre la disponibilidad de `scripts/spec-memory-link.sh` agregada al final de la sección de instalación per-project; mantiene el exit code 0 normal y bajo `--strict` mientras no haya otros findings propios.
- **Documentación**: nuevo párrafo en `README.md` describiendo Spec ↔ Memory link y fila en la tabla de salida de `command/skalling-doctor.md` con nota sobre ejecución manual.

### Changed
- `agents-base/Pau.md`: PASO 5 extendido con sub-paso explícito de invocar el script antes del `git mv`, y reporte final al usuario listando los concept docs enlazados (omitiendo la sección si la lista está vacía). Permisos y resto del PASO 5 intactos.

## [0.5.0] — 2026-08-04

### Added
- **`scripts/skalling-drift.sh`**: CLI de solo lectura para detectar drift entre claims declarados en specs archivadas y el estado actual del repositorio.
- **Verificadores declarativos**: soporte para existencia de archivos, conteo no recursivo y presencia de texto literal mediante claims `archivo`, `count` y `contiene`.
- **Validación defensiva**: rechazo de claims malformados, paths absolutos, traversal y espacios, con límites de bloque y advertencias no bloqueantes.
- **`tests/skalling-drift.test.sh`**: cobertura autocontenida de casos exitosos, drift mixto, errores de entrada, TTY, límites, portabilidad Bash 3.2 e identificadores R1.
- **Integración con doctor**: línea informativa azul y no bloqueante que indica cómo ejecutar drift detection manualmente, documentada en `command/skalling-doctor.md`.

## [0.4.0] — 2026-08-04

### Added
- **Codebase-memory-mcp como feature opt-in**: integración con [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) (servidor MCP de inteligencia estructural de código). NO es dependencia dura — se ofrece como paso 4.7 en `/skalling-init`.
- **Snippet canónico `templates/agents/snippets/code-intelligence.md`**: single source con guía de cuándo usar las 5 tools (`trace_path`, `get_architecture`, `search_graph`, `find_dead_code`, `detect_changes`).
- **Inyección en los 8 agentes**: sección `## 🔍 Code Intelligence` agregada antes de `## 🧠 Memory Protocol`, con comment block `SINCRONIZADO CON:`.
- **Paso 4.7 en `/skalling-init`**: pregunta al usuario si quiere instalar codebase-memory-mcp; 3 ramas (Sí/No/ya-instalado).
- **`check_code_intelligence()` en el doctor**: verifica instalación y configuración del MCP server como info (no bloquea).

### Changed
- `command/skalling-init.md`: paso 4.7 nuevo.
- `setup-team-doctor.sh`: nueva función informativa de Code Intelligence.
- Tests: 3 archivos de prueba nuevos (`tests/code-intelligence.test.sh` con 44 asserts + `tests/doctor-code-intelligence.test.sh` con 13 asserts + `tests/doctor-strict-environment.test.sh` con 7 asserts = 64 asserts nuevos, 345 PASS total).

### Security
- El comando de instalación verifica SHA-256 contra `checksums.txt` del tag fijo antes de ejecutar; aborta con `exit 1` si el checksum no coincide.

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

[Unreleased]: https://github.com/alexskalling/skalling-dev-team/compare/v0.6.2...HEAD
[0.6.2]: https://github.com/alexskalling/skalling-dev-team/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/alexskalling/skalling-dev-team/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/alexskalling/skalling-dev-team/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.3.0
[0.2.2]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.2.2
[0.2.1]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.2.1
[0.1.0]: https://github.com/tu-usuario/skalling-dev-team/releases/tag/v0.1.0
