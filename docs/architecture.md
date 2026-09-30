# Arquitectura de Skalling Dev Team

> Documento de referencia técnica. Describe la visión, los componentes, los
> agentes, el esquema de datos, los hooks de integridad y el flujo de trabajo
> end-to-end del repositorio `skalling-dev-team`.
>
> Versión de schema: 0.9.0 (ver `sql/project-schema.sql`).

## 1. Visión

`skalling-dev-team` es un sistema de desarrollo asistido **self-hosted** que
persiste el trabajo de un equipo de agentes (memoria de proyecto), le impone
disciplina de calidad (revisión por lentes, sellos de inmutabilidad, intentos
acotados) y usa **git hooks locales** como feedback rápido. Los hooks no son
una frontera de seguridad; CI y ramas protegidas son la capa autoritativa de
integración (ver `docs/security-model.md`).

La premisa central es: el equipo no depende de un servicio externo para
recordar decisiones, tracks de trabajo ni planes. Todo vive en una base SQLite
local (`team.db`) dentro del proyecto, versionada como migraciones SQL, y se
integra con el flujo de git sin servidores.

Componentes que componen el sistema:

| Componente | Qué es |
|---|---|
| `team.db` | Base SQLite del proyecto (memoria + planes + sellos) |
| `sql/project-schema.sql` + `sql/migrations/` | Esquema base y migraciones versionadas |
| `scripts/` | Scripts bash portables (macOS 3.2) que operan la DB |
| `scripts/hooks/` | Hooks de integridad instalados en `.git/hooks` |
| `agents-base/` | Perfiles markdown de los 8 agentes del equipo |
| `tests/` | Suite de tests por script + suite agregadora |
| `bootstrap-context.sh` / `install-global.sh` | Instaladores de hooks y contexto |

## 2. Componentes en detalle

### 2.1 Base de datos: `team.db`

Ruta: `PROYECTO/.opencode/context/team.db` (descubierta con
`teamdb_project_path`). Es SQLite, sin dependencias externas (se usa el binario
`sqlite3` del sistema).

El esquema vive en `sql/project-schema.sql` (fuente de verdad para DBs nuevas)
y en `sql/migrations/0XX_*.sql` (fuente de verdad para DBs existentes).
`scripts/teamdb-init.sh` aplica las migraciones pendientes registrándolas en la
tabla `applied_migrations`.

### 2.2 Tablas principales

- **Memoria de proyecto**: `concepts`, `decisions`, `preferences`,
  `known_problems`, `work_in_progress`, `memory_links`, `memory_tags`.
- **Planes**: `proposals`, `plans`, `specs`, `design_notes`, `tasks`,
  `task_dependencies`, `task_claims`, `plan_history`,
  `task_context_capsules`, `routing_decisions`, `task_lock_history`.
- **Flujo**: `agent_workflows` / `agent_workflow_events` (estado y eventos de
  `skalling_workflow`, la única autoridad del flujo de código),
  `workflow_metrics`.
- **Integridad y trazabilidad**: `receipts` (aprobación sellada con
  `tree_hash`), `attempts` (ledger de intentos), `audit_log`,
  `memory_versions` (versión de decisiones, preferencias y problemas para el
  merge entre integrantes, v0.13.0).
- **Infraestructura**: `schema_meta` (versión y metadatos), `skills_registry`,
  `applied_migrations`.

### 2.3 Scripts

Los scripts siguen el patrón `teamdb-<verbo>.sh`:

- **Ciclo de planes**: `teamdb-plan.sh`, `teamdb-execute-plan.sh`,
  `teamdb-resume.sh`, `teamdb-claim.sh`.
- **Memoria**: `teamdb-context.sh`, `teamdb-search.sh`,
  `teamdb-related.sh`, `teamdb-link.sh`, `teamdb-amend.sh`, `mem-review.sh`,
  `teamdb-status.sh`, `teamdb-graph.sh`.
- **Import/export**: `teamdb-import.sh`, `teamdb-export.sh`,
  `teamdb-export-md.sh`, `migrate-plans-md-to-db.sh`, `teamdb-ingest-change.sh`.
- **Flujo y revisión**: `skalling-workflow.py` (backend privado de la
  herramienta `skalling_workflow`; identidad desde el runtime),
  `skalling_classify.py` (reglas únicas de clasificación),
  `skalling-review.sh` (lenses, `--deep`, `--collect`),
  `teamdb-seal-receipt.sh` (camino humano de terminal; se niega dentro de
  OpenCode), `teamdb-attempt.sh` (presupuesto de reintentos por change).
- **Operación**: `teamdb-init.sh`, `teamdb-migrate.sh`, `teamdb-deps.sh`,
  `build-schema.sh`, `update.sh`, `merge-helper.sh`,
  `wip-tree.sh`, `skalling-drift.sh`, `spec-memory-link.sh`,
  `dashboard-server.py`, `teamdb-dashboard.sh`, `teamdb_exec.py`,
  `skalling-dead-code-check.sh` (audita scripts/plugins sin uso real).

Todos comparten `scripts/lib/lib-teamdb.sh` (helpers: `teamdb_project_path`,
`teamdb_exec_value`, `teamdb_exec_write`, `teamdb_lock`, `teamdb_unlock`,
`_sql_quote`, etc.).

### 2.4 Los 8 agentes (`agents-base/`)

Perfiles markdown que definen la personalidad, el rol y los límites de cada
agente. Son 8: **Alex** (orquestación y clasificación), **Jes**
(investigación y explicación), **Pol** (producto, alcance y aceptación),
**Sol** (plan técnico), **Teo** (implementación), **Jhon** (verificación),
**Luz** (calidad y seguridad) y **Pau** (documentación y memoria).

La ruta de ruteo concreta (rol → agente) se usa en `skalling-review.sh --deep`:

| Lens | Agente |
|---|---|
| `risk` | Luz |
| `resilience` | Jhon |
| `readability` | Pau |
| `reliability` | Jhon |

## 3. Ciclo de trabajo (end-to-end)

El ciclo es adaptativo y lo gobierna una sola autoridad: la herramienta
`skalling_workflow` (plugin + `scripts/skalling-workflow.py`). La identidad de
cada paso la entrega OpenCode (`context.agent`, `context.sessionID`), no una
variable de shell. El guard (`plugins/lib/git-guard.mjs`) solo deja a Alex
delegar a Teo cuando el workflow vigente de su sesión está en
`implementation_ready`, y el pedido cita su id.

| Riesgo | Ruta | Verificación |
|---|---|---|
| focused local y claro | Alex → Teo; Jhon se agrega para riesgo medio/alto | comprobación focal o comando `testing.fast`; sin comando, Jhon |
| staged medium | Alex → Sol → Teo → Jhon | checks de Jhon registrados por el motor |
| staged high | Alex → Pol → Sol → Teo → Jhon → Luz → Pau | Jhon, Luz (con veredicto de riesgo) y documentación de Pau |

Estados: `requested → clarified → planned → implementation_ready →
verification_ready → verified → quality_reviewed → documented → completed`
(además `blocked` cuando se agota el presupuesto de entregas y `superseded`
cuando una reclasificación explícita reemplaza al pedido).

1. **start** (Alex): reglas de `skalling_classify.py`; rechaza decisiones
   pendientes, ambigüedad, alcance desconocido y proyectos sin contexto.
2. **clarify** (Pol), **plan / ready** (Sol, con `plan_id` de un plan aprobado).
3. **deliver** (Teo): congela el candidato (huella de los archivos declarados);
   un cambio fuera del alcance exige `rescope`.
4. **oracle / check / approve | reject** (Jhon; Luz en alto): cada check corre
   el comando sobre el candidato congelado y registra exit code y salida; un
   fallo registrado no se borra con un check verde posterior.
5. **document** (Pau, alto) y **complete** (Alex): prepara en Git exactamente
   los archivos revisados y sella un receipt con el `tree_hash` del diff. Si no
   puede sellar, no completa.
   Teo, Jhon y Luz también pueden **prepare_commit** después de la aprobación
   exigida por el riesgo: prepara y sella sin cerrar ni repetir pruebas. Luego
   crean un commit local sin aprobación humana por commit. El cierre conserva
   ese sello si los cambios ya se commitearon; reabrir la revisión lo revoca.
   El alcance incluye los cambios commiteados desde el inicio del workflow.
6. Las tasks de un plan (`teamdb-claim.sh`) avanzan a `approved` con la
   verificación que registró el motor para el workflow de esa task.
7. Un workflow permite tres entregas. Cada rechazo conserva el agente, el
   motivo, el número de entrega y la siguiente acción tipada para que Teo
   corrija el hallazgo concreto. Tras el tercer candidato rechazado, el motor
   bloquea nuevas ediciones bajo ese workflow; Alex debe aclarar el criterio o
   alcance y abrir uno nuevo que superseda al anterior.

## 4. Hooks de integridad

Instalados en `.git/hooks` por `bootstrap-context.sh` (loop que copia
`pre-commit`, `post-merge` y `pre-push`) y por `install-global.sh` (copia todos
los scripts de `scripts/hooks/` por glob).

- **`pre-commit`**: fail-closed. Compara el hash del diff staged contra
  `receipts` y solo acepta evidencia calculada: `skalling_workflow:complete` o `prepare_commit`,
  la verificación real de Jhon (`skalling-verify.sh`), la revisión real de Luz
  (`review --...`) o una dispensa humana (`waived:`). Un receipt hecho a mano
  no cuenta.
- **`post-merge`**: fail-open. Si el bundle `teamdb` no existe, no hace nada.
- **`pre-push`** (v0.9.0): fail-closed. Lee el stdin de git pre-push (una línea
  por ref: `local_ref local_sha remote_ref remote_sha`), calcula el hash del
  rango `merge-base..local_sha` de cada ref y lo compara contra el último
  receipt sellado. Reglas:

  - Deleción de branch (`local_sha` todo-ceros): se saltea.
  - Branch nuevo (`remote_sha` todo-ceros): usa `merge-base local_sha HEAD`;
    sin merge-base, advierte y no bloquea.
  - Sin receipt sellado o hash distinto: **bloquea** el push.

## 5. Kill switches

Variables de entorno que apagan comportamiento sin tocar código:

- `SKALLING_REVIEW_MODE=off`: desactiva `skalling-review.sh` (imprime
  "skalling-review: desactivado" y sale con 0). Por defecto `on`.
- `SKALLING_OPENCODE_DIR`: redefine el directorio de configuración de opencode
  que usan `teamdb-init.sh` y `scripts/lib/lib-os.sh`.

## 6. Revisión por lentes (`skalling-review.sh`)

Cuatro lenses sobre el diff del proyecto:

- `risk` → eval/rm -rf/curl -k/http:///secretos/chmod 777/SQL injection.
- `resilience` → `set -euo pipefail`, `mktemp` sin trap, locks sin timeout.
- `readability` → funciones largas, variables genéricas, TODO/FIXME/HACK,
  líneas largas.
- `reliability` → scripts sin test que los cubra, tests sin asserts.

Modos:

- `--lens <x>`: corre un solo lens (o `all`).
- `--deep`: congela el diff en `.opencode/context/review/<tree_hash>/` con
  `candidate.diff`, `files.txt` y un prompt por lens dirigido al agente
  correcto ("REVISÁ SOLO EL DIFF CONGELADO"). Idempotente: no sobreescribe un
  bundle existente.
- `--collect <dir>`: consume el bundle de un `--deep` previo, parsea los
  findings (`BLOCKER|WARNING|SUGGEST`), imprime `REVIEW: PASS/FAIL` y,
  si pasa, sella el receipt con el `tree_hash` del bundle.

## 7. Doctor y salud del sistema

- `setup-team-doctor.sh` tiene `check_receipts()`: cuenta receipts recientes
  (< 1 día) y sellados con `tree_hash`, para validar que el equipo está
  sellando el trabajo.
- `skalling-drift.sh` detecta desvíos entre el plan y el estado real.
- `teamdb-status.sh` muestra el estado del proyecto; `teamdb-dashboard.sh` +
  `dashboard-server.py` exponen un dashboard web.

## 8. Cómo extender

1. **Nueva tabla o columna**: agregarla a `sql/project-schema.sql` Y crear
   `sql/migrations/0XX_*.sql` (los `CREATE TABLE`/`ALTER TABLE` deben ser
   idempotentes con `IF NOT EXISTS`; si cambia `schema_meta.version`, usar un
   `INSERT` en el schema base y un `UPDATE` en la migración).
2. **Nuevo script**: seguir el patrón de `teamdb-*.sh` (sourcing de
   `lib-teamdb.sh`, lock con `teamdb_lock`, escrituras con
   `teamdb_exec_write`, sin patrones bash 4+ — el repo apunta a bash 3.2 de
   macOS).
3. **Nuevo test**: crear `tests/<script>.test.sh` con el patrón
   `PASS=/FAIL=` y registrarlo en la suite agregadora
   (`tests/teamdb-hardening-suite.sh`) y en `.github/workflows/tests.yml`.
4. **Nuevo hook**: crear el archivo en `scripts/hooks/` y agregarlo al loop de
   `bootstrap-context.sh` (install-global.sh lo copia solo vía glob).
