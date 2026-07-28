# Skalling — Equipo Agentico para OpenCode

Un equipo de **8 agentes especializados** que se instala una vez y trabaja en cualquier proyecto.

> "Un orquestador (Alex) + 7 especialistas (Pol, Jes, Sol, Teo, Jhon, Luz, Pau) que ejecutan un ciclo disciplinado: SDD → TDD → Quality Gate → Docs, con memoria persistente por proyecto."

## ¿Qué es?

Skalling convierte OpenCode en un **equipo de trabajo agentico** con:

- **Alex** — Orquestador, detecta intención y rutea
- **Pol** — Spec author, interroga para entender el "por qué"
- **Jes** — Profesora-investigadora, explica e investiga
- **Sol** — Estratega, desglosa specs en tareas (SDD)
- **Teo** — Ingeniero, implementa con TDD y la Escalera de Ponytail
- **Jhon** — Guardián de tests, verifica cobertura y regresión
- **Luz** — Auditora, calidad + seguridad + Impeccable (frontend)
- **Pau** — Documentalista, mantiene memoria OKF y docs

## Quick Start

### 1. Instalación (una vez por máquina)

#### macOS / Linux / WSL2

```bash
git clone https://github.com/tu-usuario/skalling-dev-team.git ~/skalling-dev-team
bash ~/skalling-dev-team/install-global.sh
```

Eso copia los 8 agentes, 12 skills core, 5 comandos y la constitución a `~/.config/opencode/`.

#### Windows (PowerShell)

```powershell
# Opción A: PowerShell wrapper (delega a Git Bash o WSL)
git clone https://github.com/tu-usuario/skalling-dev-team.git $HOME\skalling-dev-team
.\skalling-dev-team\install-global.ps1

# Opción B: Git Bash directo (recomendado)
#   1. Abrí Git Bash
#   2. cd /c/Users/TU_USUARIO/skalling-dev-team
#   3. bash install-global.sh
```

**Requisitos en Windows:**
- Windows 10+ (64-bit)
- Una de estas opciones de bash:
  - **Git Bash** (descarga desde https://git-scm.com/download/win) — más simple
  - **WSL2** (`wsl --install` en PowerShell admin, luego reiniciar) — más completo
- OpenCode para Windows

Los scripts bash están adaptados para Windows via `scripts/lib/lib-os.sh` (detección de OS + paths portables). Los wrappers PowerShell delegan a bash.

### 2. Setup por proyecto (solo si querés team-sharing vía git)

#### macOS / Linux / WSL2 / Git Bash

```bash
cd ~/Proyectos/mi-proyecto
bash ~/skalling-dev-team/setup.sh
```

#### Windows (PowerShell)

```powershell
cd C:\Proyectos\mi-proyecto
.\skalling-dev-team\setup.ps1

# O desde Git Bash:
cd /c/Proyectos/mi-proyecto
bash /c/Users/TU_USUARIO/skalling-dev-team/setup.sh
```

Esto commitea los agentes al repo (overridable por proyecto). Si trabajás solo, **no necesitás este paso** — los agentes globales ya están disponibles.

### 3. Bootstrap de un proyecto

Abrí OpenCode en cualquier proyecto:

```bash
cd ~/Proyectos/mi-proyecto
opencode
```

Alex detecta el estado y sugiere:

```
Veo que este proyecto no tiene Skalling. ¿Corro /skalling-init?
```

O ejecutalo directo:

```
/skalling-init
```

Esto detecta el stack (Next.js, Python, Rust, Go, etc.), crea el bundle OKF de memoria, instala skills stack-specific, y genera `project.yaml`.

## Comandos `/skalling-*`

Todos disponibles en cualquier proyecto después de instalar:

| Comando | Qué hace |
|---|---|
| `/skalling-init` | Bootstrap del proyecto (3 modos: nuevo / virgen / actualizar) |
| `/skalling-status` | Ver bundle OKF, memoria, trabajo en curso |
| `/skalling-refresh` | Re-detectar stack y actualizar |
| `/skalling-doctor` | Health check de la instalación |
| `/skalling-forget` | Purgar concept docs obsoletos |
| `/skalling-merge` | Asistir en resolución de conflictos en `.opencode/` |

## Arquitectura

```
~/skalling-dev-team/                            # El installer (este repo)
├── install-global.sh                       # Una vez: copia a ~/.config/opencode/
├── install-global.ps1                      # Wrapper PowerShell (Windows)
├── setup.sh                                # Per-project (team-sharing vía git)
├── setup.ps1                               # Wrapper PowerShell (Windows)
├── setup-team-doctor.sh                    # Health check
├── setup-team-doctor.ps1                   # Wrapper PowerShell (Windows)
├── bootstrap-context.sh                    # Detecta stack y genera bundle OKF
├── bootstrap-context.ps1                   # Wrapper PowerShell (Windows)
├── scripts/
│   ├── merge-helper.sh                     # Asistente de resolución de conflictos
│   └── lib/lib-os.sh                        # Detección de OS + helpers portables
├── agents-base/                            # 8 agentes (Alex.md + 7 subagents)
├── constitution/constitucion.md            # 15 reglas universales (R1-R15)
├── command/                                # 6 comandos /skalling-*
├── skills-base/                            # 12 skills core + 4 skalling-*
├── templates/                              # SDD + OKF + project.yaml + gitattributes
├── data/                                   # stack-detectors + skills-by-stack
└── tests/setup.test.sh                     # 118 tests del installer

~/.config/opencode/                         # Instalación global (Unix)
%USERPROFILE%\.config\opencode\             # Instalación global (Windows)
├── agents/                                 # 8 agentes
├── skills/                                 # 12 skills core
├── command/                                # 6 comandos
├── constitucion.md                         # Constitución universal
├── templates/                              # SDD + OKF
└── skalling-data/                          # Stack detectors

<proyecto>/.opencode/                       # Por proyecto (auto-creado)
├── .gitattributes                          # Estrategias de merge R15
├── agents/                                 # (opcional, override)
├── skills/                                 # Skills stack-specific
├── context/                                # Bundle OKF (memoria)
├── changes/                                # SDD artifacts
└── project.yaml                            # Stack detectado
```

## CI/CD

El repo incluye `.github/workflows/tests.yml` con 4 jobs:
- **test**: corre los 153 tests en Linux/macOS/Windows × bash 3/4/5
- **lint**: shellcheck sobre todos los scripts bash
- **validate-yaml**: valida `data/*.yaml` y JSON schemas
- **test-cross-platform**: smoke test en ubuntu/macos/windows

**Estado**: el archivo está en el filesystem local pero NO en el commit inicial (`e895453`) porque el PAT por defecto no tiene scope `workflow` para pushearlo.

**Cómo activarlo** (elegí una):

```bash
# Opción 1: Regenerar el PAT con scope "workflow" en
# https://github.com/settings/tokens → Regenerate token
# Después:
git add .github/workflows/tests.yml
git commit -m "ci: add GitHub Actions workflow"
git push origin main

# Opción 2: Subir vía web UI
# https://github.com/alexskalling/skalling-dev-team/new/main/.github/workflows/tests.yml
# Pegar el contenido de .github/workflows/tests.yml local
```

Sin el workflow, los tests corren local con `bash tests/setup.test.sh`.

## Compatibilidad

| OS | Soporte | Notas |
|---|---|---|
| **macOS** | ✓ Nativo | bash default, funciona out-of-the-box |
| **Linux** | ✓ Nativo | bash, tar, sed, etc. disponibles |
| **WSL2** | ✓ Nativo | Recomendado en Windows para mejor experiencia |
| **Git Bash** | ✓ Nativo | Funciona out-of-the-box, paths Unix-style |
| **Windows PowerShell** | ✓ Vía wrapper | Wrappers `.ps1` delegan a Git Bash/WSL |
| **Windows cmd.exe** | ✗ | No soportado (PowerShell mínimo) |

## Características

### Memoria persistente por proyecto (OKF)

Cada proyecto tiene su propio bundle de memoria en formato [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf):

```
.opencode/context/
├── README.md           # Descripción del bundle
├── index.md            # Navegación root
├── log.md              # Historial cronológico
├── stack/              # Lenguaje, framework, runtime
├── proyecto/           # Qué es y para quién
├── decisiones/         # ADRs
├── trabajo-en-curso/   # Features activas
├── preferencias/       # Convenciones del equipo
└── problemas-conocidos/ # Workarounds
```

Portable, estándar abierto, navegable como grafo.

### Collaborative memory (R15 — manejo de conflictos)

Cuando dos devs trabajan en paralelo y commitean cambios en `.opencode/`, git necesita saber cómo manejar cada archivo. Skalling instala `.opencode/.gitattributes` con estrategias por tipo:

| Archivo | Estrategia | Comportamiento |
|---|---|---|
| `log.md`, `index.md`, `README.md` | `merge=union` | Auto-merge (concatena ambos lados) |
| `workflow.json` | `merge=lock` | Bloquea merge — requiere coordinación |
| `constitucion.md` | `merge=lock` | Cambios requieren consenso |
| `project.yaml` | `merge=union` | Regenerable con `/skalling-refresh` |
| `decisiones/*`, `trabajo-en-curso/*`, etc. | Manual | Cada uno resuelve su conflicto |

Cuando hay un merge en curso:

```bash
bash scripts/merge-helper.sh
```

Detecta conflictos, da sugerencias por tipo de archivo, y propone resolución. Si el conflicto es irresoluble (constitución, decisiones contradictorias), escala al equipo.

Recomendaciones para devs:
- **Un feature por branch** (minimiza conflictos).
- **Sufijo de autor en ADRs**: `2026-07-28-titulo-JPM.md`.
- **Git worktrees** para features grandes.
- **NO aceptar ours/theirs sin leer**.

### SDD formal (Spec-Driven Development)

Cada feature sigue un ciclo de 4 artefactos:

1. **`proposal.md`** — Qué, por qué, rollback
2. **`specs/*.md`** — Given/When/Then + RFC 2119 keywords
3. **`design.md`** — Arquitectura, ADRs, diagramas
4. **`tasks.md`** — Granular por fase, TDD-friendly

Ubicación: `.opencode/changes/<feature-slug>/`

### TDD obligatorio

```
RED:    escribir test → verificar que falla
GREEN:  implementar lo mínimo para pasar
REFACTOR: limpiar con test como red de seguridad
```

Verificado por Jhon después de cada tarea. Iron Law: código sin test = borrar.

### Clean Code + Clean Architecture + Ponytail

- **Clean Code**: cero comentarios, nombres descriptivos, funciones < 30 líneas
- **Clean Architecture**: dependencias hacia el centro, dominio sin imports externos
- **Ponytail Ladder (R14)**: 7 peldaños desde YAGNI hasta "el mínimo que funcione"

### Frontend: design-system.md obligatorio (REGLA #13)

Si el stack tiene UI (React, Vue, Flutter, etc.), debe existir `.opencode/context/proyecto/design-system.md` en el bundle OKF. Lo crea Impeccable (via bridge) o template manual. NO se commitea al repo. Luz corre `npx impeccable detect src/` como quality gate.

### Agnóstico de stack

Soporta 13+ lenguajes: TypeScript, JavaScript, Python, Rust, Go, Java, Kotlin, C#, Ruby, PHP, Elixir, Swift, Dart/Flutter. La detección es data-driven (`data/stack-detectors.yaml`).

### Idempotente

- Re-ejecutable sin romper nada
- Backup tar.gz con dedup + prune (mantiene últimos 5)
- Per-file diff con confirmación antes de sobrescribir customizaciones

## Tests

```bash
bash tests/setup.test.sh
```

130+ tests verifican:
- Estructura del installer
- 8 agentes con frontmatter correcto
- 15 reglas en constitución (R1-R15)
- 6 comandos presentes
- Templates SDD + OKF + JSON Schema válido
- Skills skalling-* propios
- Data files YAML
- Stack detection data-driven
- Syntax de scripts
- Bootstrap end-to-end en proyecto mock
- install-global.sh dry-run
- Regresión Tier 1 (5 fixes críticos)
- OS detection cross-platform

## Health Check

```bash
bash setup-team-doctor.sh
```

Verifica:
- Ambiente (bash, opencode, node, git)
- Instalación global (constitución, agentes, skills, comandos)
- Instalación per-project (bundle OKF, project.yaml, REGLA #13)
- Frontmatter de cada agente

## Documentación adicional

- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — Cómo contribuir (Conventional Commits, PR rules)
- [`constitution/constitucion.md`](./constitution/constitucion.md) — Las 14 reglas
- [`data/stack-detectors.yaml`](./data/stack-detectors.yaml) — Cómo se detecta cada stack
- [`data/skills-by-stack.yaml`](./data/skills-by-stack.yaml) — Skills recomendadas por stack
- [`templates/handoff.schema.json`](./templates/handoff.schema.json) — Schema JSON de handoffs

## Stack tecnológico del installer

- Bash 3.2+ compatible (probado en macOS default + Linux)
- OpenCode como target
- Sin dependencias externas más allá de bash + opencode + node (para Impeccable opcional)

## Licencia

MIT — el código más corto que funciona.
