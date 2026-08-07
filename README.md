# Skalling

Skalling es un equipo de **8 agentes de IA** que trabajan juntos adentro de [OpenCode](https://opencode.ai). Cada agente tiene un rol específico y siguen un ciclo ordenado para construir software bien hecho.

**Versión actual: 0.7.6**

---

## Los 8 agentes

**Alex** — Orquestador. Es tu punto de entrada. Detecta tu intención y delega directamente al agente correcto según su rol, sin pedir permiso previo cuando el destino está claro.

Usa una **tabla de despacho intención → agente → permiso** junto con un **Decision Tree** de 6 rutas:
- **INLINE** (1-3 archivos, scope claro) → Teo directo
- **INTERVENTION** (bug aislado) → Teo surgical
- **FAST-TRACK** (UI trivial, typo, config) → Teo sin plan
- **SDD** (4+ archivos, scope ambiguo) → Pol → Sol → Teo
- **DIRECT** (auditoría/seguridad) → Luz directo
- **RESEARCH** (aprendizaje) → Jes

Si la intención es ambigua, pregunta qué querés lograr; nunca te pide elegir qué agente usar.

Carga memorias relevantes al inicio de sesión (`skalling-memory`).

**Pol** — Spec Author. Te hace preguntas para entender bien qué necesitás. Una por una, no avanza sin tu confirmación. Su objetivo: evitar que el equipo construya cualquier cosa incorrecta o innecesaria.

**Jes** — Teacher/Researcher. Si necesitás entender un concepto o investigar un tema, Jes te lo explica al nivel que pidas. Busca en internet antes de responder.

**Sol** — Strategist/Planner. Toma lo que vos y Pol acordaron y lo convierte en un plan detallado: qué archivos tocar, en qué orden, cómo probarlo. Sin ambigüedades.

**Teo** — Principal Engineer. Escribe código aplicando TDD: primero escribe el test, después el código mínimo para que pase, después refactoriza. No codea lógica sin un test que falle antes.

**Jhon** — Test Verifier. Después de cada tarea de Teo verifica que los tests pasen. Al final corre la suite completa de regresión. Sin su aprobación no se avanza a la siguiente fase.

**Luz** — QA & Security Auditor. Revisa el código terminado: calidad, seguridad, rendimiento, duplicación, complejidad. Si encuentra problemas lo devuelve a Teo.

**Pau** — Documentalist / Memory Keeper. Cuando todo está aprobado, Pau guarda los cambios en la documentación y en la memoria del proyecto para que el equipo nunca empiece de cero.

---

## Instalación

### Mac / Linux

```bash
git clone https://github.com/alexskalling/skalling-dev-team.git ~/skalling-dev-team
bash ~/skalling-dev-team/install-global.sh
```

### Windows

```powershell
git clone https://github.com/alexskalling/skalling-dev-team.git $HOME\skalling-dev-team
.\skalling-dev-team\install-global.ps1
```

Requiere Windows 10+ y Git Bash o WSL2.

### Code Intelligence (opt-in, v0.4.0+)

**Code Intelligence (opt-in, v0.4.0+)**: Skalling ofrece integración opcional con [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp), un servidor MCP que indexa el código del proyecto en un grafo estructural. Esto permite a los agentes hacer queries como "¿quién llama a X?" o "¿qué afecta Y?" en lugar de leer archivos uno por uno. NO es dependencia dura — no se instala desde `/skalling-init`; si querés usarlo instalalo manualmente. Si está instalado, los 8 agentes saben cuándo usar las 5 tools mediante el snippet de Code Intelligence.

### Drift detection

Drift detection contrasta los claims `archivo`, `count` y `contiene` declarados bajo `## Verificación` en las specs de un plan archivado con el estado actual del repositorio. Es una comprobación manual y de solo lectura: ejecutá `bash scripts/skalling-drift.sh <plan-archivado>` desde cualquier directorio para obtener el detalle de aprobados y fallidos; el doctor solo informa que la herramienta está disponible y no la ejecuta automáticamente.

### Spec ↔ Memory link

Pau enlaza cada concept doc (`docs/`, `.opencode/context/concept/*.md`) a la spec archivada que lo originó. Cuando archiva un plan, corre `bash scripts/spec-memory-link.sh <dir-origen> <dir-destino>` antes del `git mv`: el script detecta los concept docs mencionados en `proposal.md`, `design.md`, `tasks.md` y `specs/*.md`, y les agrega un footer `## Spec original` con el link relativo al path final del plan. La operación es idempotente (segundo run preserva) y portable con Bash 3.2. El doctor solo informa la disponibilidad del script — no lo ejecuta automáticamente.

---

## Primeros pasos

1. Abrí OpenCode en tu proyecto:

```bash
cd ~/Proyectos/mi-proyecto
opencode
```

2. La primera vez Alex te va a sugerir `/skalling-init`. Ese comando prepara el proyecto: detecta el lenguaje y herramientas que usás, crea la memoria del proyecto, instala habilidades específicas.

3. Después ya podés pedir cosas como:

```
"necesito un login con JWT"
"explicame React Server Components"
"revisá la seguridad del módulo auth"
"cómo vamos con el proyecto?"
```

Alex clasifica tu pedido y deriva al agente que corresponde.

---

## Comandos disponibles

| Comando | Qué hace |
|---|---|
| `/skalling-init` | Prepara el proyecto por primera vez (detecta lenguaje, crea memoria) |
| `/skalling-status` | Muestra el estado del proyecto y el trabajo en curso |
| `/skalling-refresh` | Vuelve a detectar el lenguaje y herramientas |
| `/skalling-doctor` | Revisa que la instalación esté sana |
| `/skalling-forget` | Limpia documentos viejos de la memoria |
| `/skalling-merge` | Ayuda a resolver conflictos cuando trabajan varios |
| `/skalling-update` | Busca versiones nuevas de Skalling y las instala si confirmás |

---

## Ciclo de trabajo

Para construir algo nuevo, los agentes siguen este orden:

```
FASE 0: Alex recibe tu pedido y clasifica la intención
FASE 1: Pol te pregunta hasta entender bien qué y por qué
FASE 2: Sol arma un plan con tareas precisas
FASE 3: Teo implementa cada tarea (con TDD) → Jhon verifica tests
        (se repite hasta terminar todas las tareas)
FASE 4: Jhon corre todos los tests de nuevo (regresión)
FASE 5: Luz revisa calidad y seguridad del código completo
FASE 6: Pau documenta los cambios
```

Para cosas chicas (un typo, un color, un texto) Alex puede mandarte directo a Teo sin todo el ciclo. Para auditorías puede mandar a Luz directo.

---

## Reglas del equipo (R1 a R17)

| # | Regla |
|---|---|
| R1 | Todo el código en español (variables, funciones, commits) |
| R2 | Cero comentarios — el código se explica solo |
| R3 | Tipado estricto — nada de `any` |
| R4 | TDD obligatorio — escribir test antes que código |
| R5 | No saltarse pasos del ciclo |
| R6 | Plan escrito antes de construir (Spec-Driven Development) |
| R7 | Clean Architecture — dependencias hacia adentro |
| R8 | Nombres descriptivos — nada de abreviaciones crípticas |
| R9 | Funciones de máximo 30 líneas |
| R10 | Manejo de errores explícito — nada de try/catch vacíos |
| R11 | Sin código muerto — nada de console.log, variables sin usar |
| R12 | Cada proyecto tiene su propia memoria |
| R13 | Si hay interfaz gráfica, necesita un `design-system.md` en `.opencode/context/proyecto/` |
| R15 | Siempre la solución más simple posible (Escalera de Ponytail) |
| R16 | Reglas para trabajar en equipo sin pisarse |
| R17 | No se hace commit sin preguntarte antes |

---

## Estructura

### El repo de Skalling

```
skalling-dev-team/
├── VERSION                           # Versión actual
├── CHANGELOG.md                      # Historial de cambios
├── CONTRIBUTING.md                   # Cómo contribuir
├── install-global.sh                 # Instalador (Mac/Linux)
├── install-global.ps1                # Instalador (Windows)
├── setup.sh                          # Para compartir con el equipo
├── setup.ps1                         # PowerShell
├── setup-team-doctor.sh              # Health check
├── setup-team-doctor.ps1             # Health check (Windows)
├── bootstrap-context.sh              # Prepara un proyecto nuevo
├── bootstrap-context.ps1             # Prepara un proyecto nuevo (Windows)
├── scripts/
│   ├── merge-helper.sh               # Resuelve conflictos
│   ├── update.sh                     # Actualiza Skalling
│   └── lib/
│       ├── lib-os.sh                 # Detecta SO
│       └── lib-stack-detect.sh       # Detecta lenguajes y skills
├── .github/
│   └── workflows/                    # CI (GitHub Actions): tests, teamdb-sqli, handoffs, teamdb-dag-claims
├── agents-base/                      # Los 8 agentes (archivos .md)
├── constitution/
│   └── constitucion.md               # Las 16 reglas
├── command/                          # Los 8 comandos /skalling-*
├── skills-base/                      # Habilidades de los agentes (7 skalling-* core)
├── templates/                        # Plantillas
├── data/                             # Detectores de lenguajes
└── tests/
    ├── setup.test.sh                 # 268+ pruebas
    └── README.md                     # Info de los tests
```

### Lo que se instala globalmente

```
~/.config/opencode/
├── agents/              # Los 8 agentes
├── skills/              # Habilidades
├── command/             # Comandos
├── constitucion.md      # Reglas
├── templates/           # Plantillas
└── skalling-data/       # Detectores
```

### Lo que se crea por proyecto

```
tu-proyecto/.opencode/
├── .gitattributes       # Para trabajo en equipo
├── agents/              # (opcional) Agentes personalizados
├── skills/              # Habilidades para tu stack
├── context/             # Memoria del proyecto
├── changes/             # Planes de las features
└── project.yaml         # Lenguaje y herramientas detectados
```

---

## Sistemas operativos

| Sistema | Anda? |
|---|---|
| macOS | ✅ Completo |
| Linux | ✅ Completo |
| WSL2 | ✅ Completo |
| Git Bash | ✅ Completo |
| PowerShell | ✅ Vía wrapper |
| cmd.exe | ❌ |

---

## Tests

```bash
cd ~/skalling-dev-team
bash tests/setup.test.sh
```

268+ pruebas que verifican agentes, reglas, comandos, scripts, detección de lenguajes, instalación completa, helpers de memoria y doctor.

---

## Memoria y Token Reduction

Skalling usa **skalling-memory** (estilo Engram) para reducir contexto:

```
.opencode/context/
├── team.db              # Memoria del proyecto (fuente de verdad desde v0.7.0)
│   └── tablas:
│       ├── concepts       # Concept docs (What/Why/Where/Learned)
│       ├── decisions      # Decisiones arquitectónicas
│       ├── preferences    # Preferencias del equipo
│       └── known_problems # Qué no funcionó y por qué (búsqueda FTS)
├── skills_registry       # Índice de skills del proyecto (name/description/source)
└── proyecto/
    └── design-system.md  # R13: tokens de diseño (documento de referencia, no memoria)
```

**Los archivos de memoria `.jsonl`/`.md` ya NO se crean desde v0.7.0**: viven en `team.db` (se exportan a `.sql` en cada commit y se importan al pull). Los legacy se migran con `teamdb-migrate.sh`.

**Ahorro: ~90% tokens** (de ~8000 a ~700 por tarea).

Los receipts (`skalling-receipt`) formalizan cada verificación con evidence antes de claims.

**Memoria del proyecto**: Skalling ahora estructura la memoria con un template de 4 secciones (What/Why/Where/Learned) para concept docs, un snippet de Memory Protocol en cada agente que fuerza el guardado de decisiones y marcado de contradicciones, detección de conflictos en Pol antes de cerrar proposals, y herramientas de salud (`mem-review`, sección de memoria en el doctor) que detectan huérfanos, WIP zombie, duplicados y docs stale o superseded.

---

## TeamDB (libSQL)

Skalling v0.7.6 usa **libSQL** como fuente de verdad para memoria y tracking de trabajo.

### Dos bases de datos

| DB | Path | Contenido |
|---|---|---|
| Global | `~/.config/opencode/team.db` | Agentes, skills, constitución, preferencias cross-project |
| Proyecto | `<proyecto>/.opencode/context/team.db` | Conceptos, decisiones, problemas, WIP |

### Scripts principales

```bash
# Inicializar DB en un proyecto
bash scripts/teamdb-init.sh /path/to/project

# Migrar .jsonl legacy a DB
bash scripts/teamdb-migrate.sh /path/to/project

# Export DB → .sql (para git)
bash scripts/teamdb-export.sh /path/to/project

# Import .sql → DB (post-merge)
bash scripts/teamdb-import.sh /path/to/project

# Ciclo de planificación en DB (proposals → plans → tasks)
bash scripts/teamdb-plan.sh /path/to/project <plan-slug> <título> <tasks.md>
bash scripts/teamdb-status.sh <plan-slug> /path/to/project
bash scripts/teamdb-amend.sh <plan-slug> --add-task "..." --by <actor> /path/to/project
bash scripts/teamdb-execute-plan.sh <plan-slug> /path/to/project

# DAG de dependencias + claims atómicos
bash scripts/teamdb-deps.sh runnable <plan-slug> /path/to/project
bash scripts/teamdb-claim.sh claim <plan-slug> /path/to/project

# Visualizar jerarquía plan/feature/task (legacy)
bash scripts/wip-tree.sh /path/to/project
```

### Queries útiles

```bash
source ~/.config/opencode/scripts/lib-teamdb.sh

# ¿Qué decisiones hay?
teamdb_query_project "SELECT slug, title FROM decisions WHERE status='accepted'"

# Búsqueda full-text
teamdb_query_project "SELECT slug, title FROM concepts_fts WHERE concepts_fts MATCH 'JWT OR auth'"

# Grafo de relaciones
teamdb_query_project "SELECT c.title FROM concepts c JOIN memory_links ml ON ml.from_id=c.id WHERE ml.link_type='uses'"
```

### Ciclo de planificación en DB

El ciclo SDD vive en tablas `proposals`, `plans` y `tasks` (desde v0.7.2): los planes contienen tasks con dependencias (`task_dependencies`), historial de amendments (`plan_history`), claims atómicos (`task_claims`) y context capsules (`task_context_capsules`).

```bash
# Crear plan desde un tasks.md (genera filas en proposals/plans/tasks)
bash scripts/teamdb-plan.sh /path/to/project "auth-jwt" "Auth JWT" /tmp/tasks.md

# Ver estado del plan (próxima task, owner, blockers)
bash scripts/teamdb-status.sh auth-jwt /path/to/project

# Amendment atómico (versiona en plan_history; tasks aprobadas quedan inmutables)
bash scripts/teamdb-amend.sh auth-jwt --add-task "refresh token" --by sol /path/to/project

# DAG: qué tasks son ejecutables ahora
bash scripts/teamdb-deps.sh runnable auth-jwt /path/to/project

# Claim atómico de la próxima task (lease + attempt + input_hash)
bash scripts/teamdb-claim.sh claim auth-jwt /path/to/project

# Orquestar ejecución (solo descubre la próxima task; no ejecuta shell de la DB)
bash scripts/teamdb-execute-plan.sh auth-jwt /path/to/project
```

> **Legacy**: `work_in_progress` y `wip-tree.sh` siguen existiendo para visualización; los scripts nuevos del ciclo usan `proposals`/`plans`/`tasks`.

### Hooks git

- `pre-commit`: exporta DB → `.sql` antes de commitear y valida que el árbol staged coincida con el último receipt sellado (tree_hash, v0.8.3+)
- `post-merge`: importa `.sql` → DB después de hacer pull

### Review con lenses (v0.8.3+)

`scripts/skalling-review.sh` reemplaza la revisión visual ("Luz mira a ojo") por un análisis estructurado sobre el diff, con 4 lentes adaptados al stack bash/sqlite:

| Lens | Qué busca |
|---|---|
| `risk` | `eval` sin comillas, `rm -rf` sin guarda de ruta, `curl/wget -k`, `http://`, secretos hardcodeados, `chmod 777`, SQL injection en queries `sqlite3` |
| `resilience` | scripts sin `set -euo pipefail`, `mktemp -d` sin trap de cleanup, locks sin timeout |
| `readability` | funciones > 50 líneas, variables genéricas, TODO/FIXME/HACK, líneas > 120 chars, archivos > 400 líneas |
| `reliability` | scripts sin test que los cubra, tests sin `assert_`/PASS counter |

```bash
# Review completa
bash scripts/skalling-review.sh

# Un solo lente
bash scripts/skalling-review.sh --lens risk

# Otro directorio / rango de diff
bash scripts/skalling-review.sh --cwd /path/to/project --diff HEAD~1

# Kill switch (default: ON)
SKALLING_REVIEW_MODE=off bash scripts/skalling-review.sh
```

Cada finding se emite con severidad `BLOCKER` (falla el review), `WARNING` o `INFO`. Al final se sella un **receipt inmutable** (`scripts/teamdb-seal-receipt.sh`) con `tree_hash`: el hash SHA-256 (16 chars) de `git diff HEAD`. El `pre-commit` compara ese hash con el árbol staged: si alguien tocó una línea después de la revisión, el commit se bloquea hasta re-sellar o revertir.

### Tests

```bash
bash tests/teamdb.test.sh          # suite base teamdb
bash tests/teamdb-hardening-suite.sh  # suite agregadora v0.7.2 (regresión completa)
```

La suite agregadora `tests/teamdb-hardening-suite.sh` corre 41 suites de teamdb: schemas, FTS5, SQLi (search/related), ciclo completo en DB (plan/amend/deps/claim/execute-plan), escrituras WAL, export/import, migración, snippets, handoffs y versionado.

---

## Health check

Si algo no funciona:

```bash
cd ~/skalling-dev-team
bash setup-team-doctor.sh
```

O desde OpenCode: `/skalling-doctor`

---

## Licencia

MIT.
