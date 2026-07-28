# Skalling

Skalling es un equipo de **8 agentes de IA** que trabajan juntos adentro de [OpenCode](https://opencode.ai). Cada agente tiene un rol específico y siguen un ciclo ordenado para construir software bien hecho.

---

## Los 8 agentes

**Alex** — Orquestador. Es tu punto de entrada. Detecta tu intención y deriva al agente correcto.

- Si preguntás algo → responde directo
- Si querés aprender o investigar → deriva a Jes
- Si querés construir algo nuevo → arranca el ciclo con Pol
- Si hay un bug → manda a Teo directo (fast-track)
- Si pedís una auditoría → manda a Luz directo
- Si pedís un commit → pide permiso primero, nunca asume
- Si no entiende qué querés → pregunta con opciones

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

## Reglas del equipo (R1 a R16)

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
| R13 | Si hay interfaz gráfica, necesita un archivo de diseño en `.opencode/context/` |
| R14 | Siempre la solución más simple posible (Escalera de Ponytail) |
| R15 | Reglas para trabajar en equipo sin pisarse |
| R16 | No se hace commit sin preguntarte antes |

---

## Estructura

### El repo de Skalling

```
skalling-dev-team/
├── install-global.sh                 # Instalador (Mac/Linux)
├── install-global.ps1                # Instalador (Windows)
├── setup.sh                          # Para compartir con el equipo
├── setup.ps1                         # PowerShell
├── setup-team-doctor.sh              # Health check
├── bootstrap-context.sh              # Prepara un proyecto nuevo
├── scripts/
│   ├── merge-helper.sh               # Resuelve conflictos
│   ├── update.sh                     # Actualiza Skalling
│   └── lib/lib-os.sh                 # Detecta SO
├── agents-base/                      # Los 8 agentes (archivos .md)
├── constitution/
│   └── constitucion.md               # Las 16 reglas
├── command/                          # Los 7 comandos /skalling-*
├── skills-base/                      # Habilidades de los agentes
├── templates/                        # Plantillas
├── data/                             # Detectores de lenguajes
└── tests/
    └── setup.test.sh                 # 150+ pruebas
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

150+ pruebas que verifican agentes, reglas, comandos, scripts, detección de lenguajes y instalación completa.

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
