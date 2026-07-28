# Skalling — Tu equipo de agentes para OpenCode

**Skalling** es un equipo de 8 agentes de inteligencia artificial que trabajan juntos para ayudarte a programar mejor. Se instala una vez y funciona en cualquier proyecto, sin importar el lenguaje o framework que uses.

Piensa en Skalling como tener un equipo completo de desarrollo a tu lado: un líder que organiza, un analista que cuestiona, un arquitecto que planifica, un programador que construye, un tester que verifica, un auditor que revisa calidad y seguridad, y un documentalista que guarda todo el conocimiento.

---

## Contenido

- [¿Cómo funciona?](#cómo-funciona)
- [Los 8 agentes](#los-8-agentes)
- [Instalación rápida](#instalación-rápida)
- [Primeros pasos en un proyecto](#primeros-pasos-en-un-proyecto)
- [Comandos disponibles](#comandos-disponibles)
- [El ciclo de trabajo](#el-ciclo-de-trabajo)
- [Las reglas del equipo (constitución)](#las-reglas-del-equipo-constitución)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Características principales](#características-principales)
- [Sistemas operativos compatibles](#sistemas-operativos-compatibles)
- [Tests](#tests)
- [Health check](#health-check)
- [Cómo contribuir](#cómo-contribuir)

---

## ¿Cómo funciona?

Cuando trabajas con OpenCode y tienes Skalling instalado, todo empieza con **Alex**, el agente orquestador. Alex recibe tu mensaje, detecta qué necesitas (aprender algo nuevo, construir una feature, arreglar un bug, pedir una auditoría, etc.) y deriva el trabajo al agente correcto.

El flujo normal para construir algo nuevo es:

```
Tú → Alex → Pol → Sol → Teo ↔ Jhon → Luz → Pau
```

Cada agente hace su parte y pasa el trabajo al siguiente. Nadie salta pasos. Nadie hace el trabajo de otro. Esto asegura que todo lo que se construye está bien pensado, bien probado y bien documentado.

---

## Los 8 agentes

### 🎯 Alex — El Orquestador (punto de entrada)
Es quien recibe tu mensaje primero. Detecta tu intención y decide qué hacer:
- Si preguntas algo → te responde directo
- Si necesitas aprender o investigar → llama a Jes
- Si quieres construir algo → inicia el ciclo con Pol
- Si tienes un bug → envía a Teo directo (fast-track)
- Si pides una auditoría → llama a Luz directamente
- Si pides un commit → pide tu permiso antes de hacerlo
- Si no entiende tu intención → pregunta con opciones

**Nunca asume. Siempre confirma antes de actuar.**

### ❓ Pol — El Cuestionador (spec author)
Antes de construir cualquier cosa, Pol te hace preguntas para entender bien qué necesitas. Una pregunta a la vez. No avanza hasta que confirmes. Su objetivo es evitar que el equipo construya algo incorrecto o innecesario.

### 📚 Jes — La Investigadora (teacher/researcher)
Si necesitas aprender un concepto, entender cómo funciona algo o investigar un tema, Jes te explica con el nivel de detalle que pidas. Busca información actualizada en internet antes de responder.

### ☀️ Sol — La Estratega (planner)
Toma lo que Pol validó contigo y lo convierte en un plan detallado: qué archivos tocar, en qué orden, cómo probarlo. Sus planes son tan precisos que Teo puede ejecutarlos sin ambigüedades.

### 🔧 Teo — El Ingeniero (implementador)
Escribe el código siguiendo TDD (Test-Driven Development): primero escribe el test, luego el código para que pase, luego refactoriza. No escribe una línea de lógica sin un test que falle primero. Aplica la Escalera de Ponytail: siempre busca la solución más simple posible.

### 🧪 Jhon — El Guardián de Tests (test verifier)
Después de cada tarea de Teo, Jhon ejecuta los tests y verifica que todo pase. También corre la suite completa al final del plan para asegurar que nada se rompió. Sin su aprobación, Luz no puede empezar.

### 🛡️ Luz — La Auditora (QA & security)
Una vez que Jhon aprueba la regresión completa, Luz revisa el código completo: calidad, seguridad, rendimiento, duplicación, complejidad. Para proyectos con interfaz gráfica, ejecuta `npx impeccable detect` para detectar "AI slop" visual. Si encuentra problemas, devuelve el código a Teo.

### 📖 Pau — La Documentalista (memory keeper)
Cuando Luz aprueba todo, Pau documenta los cambios. Actualiza tanto la documentación pública (`docs/`) como la memoria interna del equipo (`.opencode/context/`). Sin el Quality Gate PASSED de Luz, Pau no documenta nada.

---

## Instalación rápida

### macOS / Linux / WSL2

Abre una terminal y ejecuta:

```bash
git clone https://github.com/alexskalling/skalling-dev-team.git ~/skalling-dev-team
bash ~/skalling-dev-team/install-global.sh
```

Esto copia los 8 agentes, los comandos, las skills y la constitución a `~/.config/opencode/`. Una vez instalado, Skalling está disponible en cualquier proyecto donde abras OpenCode.

### Windows (PowerShell)

```powershell
git clone https://github.com/alexskalling/skalling-dev-team.git $HOME\skalling-dev-team
.\skalling-dev-team\install-global.ps1
```

**Requisitos:** Windows 10+ y Git Bash o WSL2. Lee [la guía de Windows](https://git-scm.com/download/win) para instalar Git Bash.

---

## Primeros pasos en un proyecto

### 1. Abre OpenCode en tu proyecto

```bash
cd ~/Proyectos/mi-proyecto
opencode
```

### 2. Inicializa Skalling

La primera vez, Alex te sugerirá ejecutar `/skalling-init`. Este comando:

- Detecta el stack tecnológico (lenguaje, framework, test runner, etc.)
- Crea el bundle de memoria del proyecto (`.opencode/context/`)
- Instala skills específicas para tu stack
- Genera `project.yaml` con la configuración detectada
- Si tu proyecto tiene interfaz gráfica, te preguntará si quieres crear un `design-system.md`

### 3. Empieza a trabajar

Ya puedes pedirle a Alex lo que necesites:

```
"necesito un login con JWT"
"explicame cómo funciona React Server Components"
"auditá la seguridad del módulo auth"
"cómo vamos con el proyecto?"
```

Alex clasificará tu intención y derivará al agente correcto automáticamente.

---

## Comandos disponibles

Después de instalar, estos comandos están disponibles en cualquier proyecto:

| Comando | Qué hace |
|---|---|
| `/skalling-init` | Inicializa Skalling en el proyecto actual (detecta stack, crea memoria) |
| `/skalling-status` | Muestra el estado actual: memoria, trabajo en curso, stack |
| `/skalling-refresh` | Vuelve a detectar el stack y actualiza la configuración |
| `/skalling-doctor` | Revisa que la instalación esté sana (bash, agentes, skills, constitución) |
| `/skalling-forget` | Limpia concept docs obsoletos de la memoria |
| `/skalling-merge` | Ayuda a resolver conflictos en archivos de `.opencode/` |
| `/skalling-update` | Busca actualizaciones de Skalling en el repo, muestra cambios y las instala si confirmas |

---

## El ciclo de trabajo

Skalling sigue un ciclo disciplinado de 6 fases para construir features:

```
FASE 0: Tú pides algo → Alex clasifica tu intención
FASE 1: Pol te hace preguntas para entender bien el qué y por qué
FASE 2: Sol crea un plan detallado con tareas precisas
FASE 3: Teo implementa cada tarea con TDD → Jhon verifica los tests
        (se repite hasta completar todas las tareas del plan)
FASE 4: Jhon ejecuta la suite completa de regresión
FASE 5: Luz audita calidad, seguridad y limpieza del código
FASE 6: Pau documenta los cambios (docs + memoria interna)
```

### Fast-track (atajo para cambios simples)

Para cambios triviales (un typo, un color, un texto), Alex puede enviarte directo a Teo sin pasar por Pol ni Sol:

```
Tú → Alex → Teo (sin plan formal)
```

### Auditoría directa

Si solo necesitas una revisión de código o seguridad, Alex puede llamar a Luz directamente, sin pasar por todo el ciclo de construcción:

```
Tú → Alex → Luz (sin Pol/Sol/Teo/Jhon)
```

---

## Las reglas del equipo (constitución)

Skalling opera con 16 reglas llamadas **R1 a R16**. Estas reglas las sigue cada agente automáticamente:

| Regla | Qué dice |
|---|---|
| **R1** | Todo el código en español (variables, funciones, commits) |
| **R2** | Cero comentarios en el código — el código se explica solo |
| **R3** | Tipado estricto — nada de `any` |
| **R4** | TDD obligatorio — test antes que código |
| **R5** | Calidad total — nadie salta pasos del ciclo |
| **R6** | Spec-Driven Development — plan escrito antes de construir |
| **R7** | Clean Architecture — dependencias hacia el centro |
| **R8** | Nombres descriptivos — nada de abreviaciones crípticas |
| **R9** | Funciones pequeñas — máximo 30 líneas |
| **R10** | Manejo de errores explícito — nada de try/catch vacíos |
| **R11** | Sin código muerto — nada de console.log, variables sin usar |
| **R12** | Memoria por proyecto — cada proyecto tiene su propio contexto |
| **R13** | DESIGN.md obligatorio si hay interfaz gráfica (en `.opencode/context/`, no se commitea) |
| **R14** | Escalera de Ponytail — siempre la solución más simple |
| **R15** | Resolución de conflictos colaborativos para trabajo en equipo |
| **R16** | Commits requieren permiso del usuario y mensajes descriptivos en español |

---

## Estructura del proyecto

### El repo de Skalling (donde se instala)

```
~/skalling-dev-team/
├── install-global.sh                 # Instalación global (una vez por máquina)
├── install-global.ps1                # Para Windows PowerShell
├── setup.sh                          # Setup por proyecto (para compartir en equipo)
├── setup.ps1                         # Para Windows PowerShell
├── setup-team-doctor.sh              # Health check de la instalación
├── bootstrap-context.sh              # Detecta stack y crea memoria del proyecto
├── bootstrap-context.ps1             # Para Windows PowerShell
├── scripts/
│   ├── merge-helper.sh               # Ayuda a resolver conflictos
│   ├── update.sh                     # Actualiza Skalling desde el repo
│   └── lib/lib-os.sh                 # Detecta el sistema operativo
├── agents-base/                      # Los 8 agentes (Alex.md + 7 subagentes)
├── constitution/
│   └── constitucion.md               # Las 16 reglas del equipo
├── command/                          # 7 comandos /skalling-*
├── skills-base/                      # Skills que los agentes pueden cargar
├── templates/                        # Plantillas para planes, memoria, config
├── data/                             # Detectores de stack y skills por stack
└── tests/
    └── setup.test.sh                 # 150+ tests del instalador
```

### Lo que se instala en tu máquina

```
~/.config/opencode/                   # Instalación global
├── agents/                           # 8 agentes
├── skills/                           # Skills core
├── command/                          # 7 comandos
├── constitucion.md                   # Las reglas
├── templates/                        # Plantillas
├── scripts/                          # Scripts de utilidad
└── skalling-data/                    # Datos de detección
```

### Lo que se crea en cada proyecto

```
tu-proyecto/.opencode/
├── .gitattributes                    # Estrategias de merge para trabajo en equipo
├── agents/                           # (opcional) Agentes personalizados por proyecto
├── skills/                           # Skills específicas del stack
├── context/                          # Memoria del proyecto (bundle OKF)
├── changes/                          # Planes y artefactos de features
└── project.yaml                      # Stack detectado automáticamente
```

---

## Características principales

### Memoria persistente por proyecto (OKF)

Cada proyecto tiene su propia memoria en `.opencode/context/`. Los agentes la consultan para recordar decisiones, preferencias, trabajo en curso y problemas conocidos. Nunca empiezan desde cero.

```
.opencode/context/
├── index.md          # Navegación principal
├── log.md            # Historial de cambios
├── stack/            # Lenguaje, framework, runtime
├── proyecto/         # Descripción del proyecto
├── decisiones/       # Decisiones técnicas (ADRs)
├── trabajo-en-curso/ # Features activas
├── preferencias/     # Convenciones del equipo
└── problemas-conocidos/ # Workarounds
```

### Trabajo en equipo (R15)

Si trabajas con otros desarrolladores, Skalling instala reglas de merge para que los archivos de `.opencode/` no generen conflictos. Cada tipo de archivo tiene su estrategia: algunos se auto-merged, otros requieren decisión manual.

### Spec-Driven Development

Para features nuevas, el ciclo produce 4 artefactos en `.opencode/changes/<feature>/`:

1. **`proposal.md`** — Qué se va a hacer y por qué
2. **`specs/*.md`** — Especificaciones detalladas (Given/When/Then)
3. **`design.md`** — Arquitectura y decisiones técnicas
4. **`tasks.md`** — Lista de tareas granular para implementar

### TDD obligatorio (R4)

Los agentes no escriben código de lógica de negocio sin un test que falle primero. El ciclo es:

```
RED:    escribir el test → verificar que falla
GREEN:  escribir el código mínimo para que pase
REFACTOR: limpiar el código con el test como seguridad
```

### Escalera de Ponytail (R14)

Antes de escribir cualquier solución, los agentes preguntan:

1. ¿Realmente necesita existir? → si no, skip
2. ¿Ya existe en el proyecto? → reusar
3. ¿Lo resuelve la librería estándar? → usarla
4. ¿Lo resuelve una función nativa de la plataforma? → usarla
5. ¿Una dependencia ya instalada lo hace? → usarla
6. ¿Se puede resolver en una línea? → una línea
7. Recién entonces: el mínimo que funcione

### Sin bloqueos silenciosos

Si un agente se traba o llega al límite de iteraciones, escala a Alex, quien te notifica con opciones para resolverlo.

---

## Sistemas operativos compatibles

| Sistema | Soporte | Notas |
|---|---|---|
| **macOS** | ✅ Completo | Funciona out-of-the-box con la terminal |
| **Linux** | ✅ Completo | bash, sed, git disponibles |
| **WSL2** | ✅ Completo | Recomendado en Windows |
| **Git Bash** | ✅ Completo | Funciona con paths Unix-style |
| **PowerShell** | ✅ Vía wrapper | Los `.ps1` delegan a Git Bash o WSL |
| **cmd.exe** | ❌ No soportado | Usa PowerShell o Git Bash |

---

## Tests

Para verificar que todo funciona correctamente:

```bash
cd ~/skalling-dev-team
bash tests/setup.test.sh
```

Esto corre 150+ tests que verifican:
- Que los 8 agentes existen con su configuración correcta
- Que las 16 reglas de la constitución están presentes
- Que los 7 comandos están instalados
- Que las plantillas y schemas son válidos
- Que los scripts tienen sintaxis correcta
- Que el bootstrap funciona de principio a fin
- Que la detección de stack funciona en diferentes escenarios
- Que los scripts funcionan en todos los sistemas operativos soportados

---

## Health check

Si algo no funciona como esperas:

```bash
cd ~/skalling-dev-team
bash setup-team-doctor.sh
```

O desde OpenCode:

```
/skalling-doctor
```

Esto revisa: bash version, opencode en PATH, node disponible, agentes instalados, skills presentes, constitución válida, comandos disponibles, y el estado del proyecto actual.

---

## Cómo contribuir

Lee [`CONTRIBUTING.md`](./CONTRIBUTING.md) para saber cómo:

- Reportar bugs
- Proponer mejoras
- Agregar un nuevo comando `/skalling-*`
- Agregar un detector de stack
- Enviar pull requests

Todo commit debe seguir el formato de **Conventional Commits** y estar en español.

---

## Stack tecnológico del instalador

- **Bash 3.2+** (probado en macOS, Linux, Git Bash, WSL)
- **OpenCode** como plataforma objetivo
- **Node.js** (solo necesario para Impeccable, opcional)
- Sin dependencias externas más allá de bash + opencode

---

## Licencia

MIT — el código más corto que funciona.
