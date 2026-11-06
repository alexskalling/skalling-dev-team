# Skalling

Skalling es un equipo de **8 agentes de IA** que trabajan juntos adentro de [OpenCode](https://opencode.ai). Cada agente tiene un rol específico y siguen un ciclo ordenado para construir software bien hecho.

**Versión actual: 0.19.0** — disponible en el checkout local; publicación pendiente.

La versión 0.19.0 añade compactación nativa acotada de conversaciones grandes,
conservando el workflow en TeamDB, y un carril declarativo sin preparación TDD ni
Ponytail rutinaria. Mantiene las revisiones por riesgo y las pruebas de comportamiento.
Ver [notas de versión](docs/releases/0.19.0.md).

Desde 0.15.1 hay respaldos de modelo configurables ante errores del proveedor,
timeouts y salida inválida en OpenCode 2.0.18. Ver [configuración y límites](command/skalling-models.md).

Desde 0.15.0 cada funcionalidad conserva el pedido original y sus resultados
observables hasta la entrega. Aprobar exige relacionarlos con evidencia; el contexto
avisa si sus fuentes cambiaron y permite reutilizar lecturas y pruebas idénticas.
Las correcciones humanas se registran explícitamente, separadas de nuevas tareas.
[Contratos, medición y límites](docs/agent-effectiveness-plan.md#entrega-0150-objetivo-contexto-repetición-y-medición).


---

## Los 8 agentes

**Alex** — Orquestador. Es tu punto de entrada (el agente por defecto del proyecto). Lee los archivos pertinentes, decide la ruta con evidencia y delega; no escribe código.

Toda implementación pasa por la herramienta `skalling_workflow`, que es la **única autoridad** del flujo. Clasifica (`start`), registra la evidencia de cada rol y sella la aprobación que Git exige al commitear. La ruta depende del riesgo, no de la cantidad de archivos:

| Pedido | Ejemplo | Ruta |
|---|---|---|
| Trivial (`low`): local, claro, reversible | cambiar una mayúscula o un texto | **Alex → Teo**, más la verificación configurada del proyecto que corre el motor (Jhon si no hay comando) |
| Local y claro (`medium`): cambio reversible sin plan ni decisión | ajustar un componente conocido | **Alex → Teo → Jhon** |
| De módulo o con dependencias (`medium`) | feature con varios pasos | **Alex → Sol → Teo → Jhon** |
| Complejo o sensible (`high`) | feature transversal, auth, datos, CI/CD | **Alex → Teo → Jhon → Luz** si el alcance está claro; Pol/Sol cuando falta aclaración/plan y Pau cuando hay conocimiento durable nuevo. `staged` conserva el recorrido completo. |

Investigación → Jes. Auditoría → Luz. Con una decisión tuya pendiente o un pedido ambiguo, el motor no deja implementar: Alex te pregunta primero.

Carga memorias relevantes al inicio de sesión (`skalling-memory`).

TeamDB conserva el foco del pedido, sus restricciones y la evidencia. Si se pierde
el id al retomar, `skalling_workflow resume` con `{}` recupera el trabajo asociado
a la sesión o muestra candidatos para contrastar con el pedido actual. Las mejoras
opcionales se registran con `defer`, sin bloquear la entrega ni ampliar el alcance.
Ver [foco, recuperación y límites](docs/execution-efficiency.md#foco-recuperable-en-teamdb).

**Pol** — Spec Author. Te hace preguntas para entender bien qué necesitás. Una por una, no avanza sin tu confirmación. Su objetivo: evitar que el equipo construya cualquier cosa incorrecta o innecesaria.

**Jes** — Teacher/Researcher. Si necesitás entender un concepto o investigar un tema, Jes te lo explica al nivel que pidas. Busca en internet antes de responder.

**Sol** — Strategist/Planner. Toma lo que vos y Pol acordaron y lo convierte en un plan detallado: qué archivos tocar, en qué orden, cómo probarlo. Sin ambigüedades.

**Teo** — Principal Engineer. Escribe código aplicando TDD: primero escribe el test, después el código mínimo para que pase, después refactoriza. No codea lógica sin un test que falle antes.

**Jhon** — Test Verifier. En riesgo medio y alto arma un oráculo independiente, ejecuta comprobaciones proporcionales al riesgo (el motor las corre y registra) y aprueba o rechaza. La suite completa, solo en riesgo alto o impacto transversal. Sin su aprobación no se avanza.

**Luz** — QA & Security Auditor. Revisa el código terminado: calidad, seguridad, rendimiento, duplicación, complejidad. Si encuentra problemas lo devuelve a Teo.

**Pau** — Documentalist / Memory Keeper. Registra conocimiento durable autorizado cuando se necesita, incluso antes de revisar una entrega. Tras la aprobación cierra la etapa documental; registrar una decisión y cerrar esa etapa son operaciones distintas.

Si un workflow agota sus tres entregas, Alex puede usar `recover` una sola vez con
feedback humano registrado, el error observado y un plan concreto. Permite una
entrega adicional sin reiniciar el historial ni los límites de pruebas o tiempo
del usuario. Las restricciones corregidas deben corresponder a esa instrucción;
las omitidas se conservan. No habilita commits sin revisión ni autoriza un push.
Si Git detecta una decisión sin fila en TeamDB, el error identifica tabla, slug
y helper para que Pau registre el contenido autorizado y se verifique antes de reintentar.

---

## Instalación

### Compatibilidad con OpenCode

Este bundle requiere **OpenCode 2 >= 2.0.21 y < 3.0.0**. Usa únicamente plugins
con `setup`; no instala adaptadores ni herramientas de OpenCode 1. El mínimo
incluye el formato de plugin de directorio usado por ejecución eficiente.
Ambos instaladores rechazan versiones incompatibles o ilegibles antes de cambiar
la instalación. Sin el binario en PATH permiten preparar los archivos; eso no
verifica el runtime ni habilita una versión anterior.

El flujo se inicia con Alex y persiste foco, estado y evidencia en TeamDB.
No incluye continuación autónoma entre turnos. `skalling_workflow` ejecuta checks
configurados o permitidos por la política del agente; un plugin no puede solicitar
aprobación nativa desde esa herramienta. `teamdb_destructive` previsualiza y devuelve
un comando exacto que solicita aprobación por la terminal. Sin identidad atribuible,
los helpers de TeamDB rechazan la operación.

Al actualizar, el instalador retira el plugin, comando y helpers antiguos de
`skalling-goal`, las plantillas Markdown sin uso de OKF/SDD y dos scripts de prueba
antiguos. Los formatos SDD vigentes están definidos en sus skills. Conserva las bases y los plugins del usuario. La memoria se inicializa
y mantiene en TeamDB; las exportaciones Markdown siguen disponibles. Se aplican las opciones
habituales de backup (`--force` global y `--skip-backup` local lo omiten).
Reiniciá OpenCode después de instalar para cargar los plugins nuevos.

**Verificación del instalador (02-11-2026).** Instalaciones aisladas global/local,
rechazo de versiones incompatibles, retiro de artefactos y dry-run sin mutación.
Plugins verificados con pruebas unitarias y política de eficiencia probada en
OpenCode 2.2.5 con proveedor local sintético; no implica una evaluación de calidad
con modelos reales.

**Cómo se verificó (27-09-2026).** Pruebas de la integración de OpenCode 2 y, además,
sesiones históricas con el binario de OpenCode 2.0.18 (anterior al mínimo actual) y modelos MiniMax (M3 para Alex, M2.7
para el resto), en un proyecto de prueba aislado:

| Escenario | Resultado observado |
|---|---|
| Trivial (mayúscula) | Alex → Teo; verificación automática del proyecto; `complete` selló y Git aceptó el commit. 30 s, 1 handoff, 1 pedido de permiso. |
| Decisión pendiente | Alex presentó opciones antes de crear el workflow; no tocó código. |
| Restricción en memoria (sesión nueva) | Alex recuperó la decisión guardada, detectó la contradicción y preguntó; no tocó código. |
| Mediano (módulo nuevo) | Alex → Sol (plan aprobado) → Teo (`rescope`, `deliver`) → Jhon (oráculo, check, aprobación) → `complete`; Git aceptó el commit. 3 min 26 s, 3 handoffs. |
| Complejo y sensible (datos personales) | Ruta completa: Pol (`clarify`) → Sol (plan y `ready`) → Teo → Jhon → Luz (veredicto de riesgo) → Pau (`document`) → `complete`; 17 tests del candidato verdes y Git aceptó el commit. 10 min 46 s, 6 handoffs. Pol detectó una decisión de producto faltante y se preguntó antes de seguir. |
| Memoria del equipo | Una decisión y un problema conocido quedaron guardados y versionados para el merge. |

**Consumo medido por el propio motor** (v0.13.0, 27-09-2026). Al completar cada pedido,
`skalling_workflow` suma de la base de OpenCode los tokens de la sesión y sus subagentes y los
guarda en `workflow_metrics` (`skalling-metrics.sh report|summary`). MiniMax Token Plan es tarifa
plana, así que el costo figura 0:

| Pedido | Duración del workflow | Agentes | Handoffs | Reintentos | Entrada | Salida | Leídos de caché |
|---|---|---|---|---|---|---|---|
| Trivial (docstring) | 30 s | Alex, Teo | 1 | 0 | 15 mil | 1,4 mil | 77 mil |
| Mediano (módulo nuevo) | 4 min | Alex, Sol, Teo, Jhon | 3 | 0 | 81 mil | 14 mil | 626 mil |
| Complejo y sensible | 14 min | los 7 | 9 | 1 | 262 mil | 55 mil | 2,45 millones |

Son corridas puntuales en un proyecto chico, no un promedio: sirven para comparar tamaños de
pedido, no para prometer un costo. En la misma tanda, un pedido trivial que contradecía una
decisión guardada no se ejecutó: Alex detectó el conflicto y preguntó. El mínimo son dos agentes
(Alex y Teo); el motor automatiza solo `testing.fast`. Sin ese comando, Jhon elige una prueba
focal y usa `testing.unit` completo cuando el impacto lo justifica.

Esas corridas destaparon y corrigieron defectos que ningún test unitario veía (plugins que
2.0.x no cargaba, herramienta escondida en code mode, booleanos como texto, Jhon sin forma de
registrar evidencia, triggers de versión que bloqueaban toda escritura de memoria). No hay todavía una matriz de CI con binarios reales de OpenCode: una
versión nueva del binario puede romper algo. Si hay varias instalaciones, comprobar
`command -v opencode` y `opencode --version` en la terminal del proyecto;
`bash setup-team-doctor.sh` informa la versión detectada.

Los ocho agentes tienen lecturas y helpers de TeamDB permitidos según su rol, también fuera
de Goal. Usar rutas canónicas de los helpers; no envolverlos en `python -c`, `bash -c` o SQL libre.
Operaciones desconocidas, destructivas o de publicación mantienen aprobación. Configuraciones
locales de proyectos pueden reemplazar los agentes globales: deben actualizarse por separado.

### Protección de datos

Los helpers normales permiten consultas, altas y cambios aditivos, pero rechazan borrados,
reemplazos destructivos y vaciados de contenido durable. Las actualizaciones de conocimiento
guardan la versión anterior en `data_revisions` en la misma TeamDB; ese historial local no
se publica automáticamente en el dump de Git. Añadir tablas o columnas sigue permitido.

Cuando sea necesario eliminar datos, el agente usa `teamdb_destructive`. OpenCode muestra
la base, SQL y parámetros y pide aprobación para esa operación concreta. Antes de ejecutarla,
se crea un respaldo SQLite en `.opencode/context/.backups/approved-data-changes/`; si la base
cambió durante la aprobación, se rechaza y debe presentarse nuevamente. Rechazar o cancelar
no ejecuta la operación. El respaldo no autoriza borrarla: la aprobación sigue siendo obligatoria.

No hay permiso general para `cp`, `rm`, SQL libre o restauraciones. Los programas de terceros
y otras bases requieren sus propios controles: esto no es un sandbox del sistema operativo.
Las pruebas del proyecto deben usar bases aisladas, nunca datos reales. Reiniciar OpenCode
después de instalar para cargar los tres plugins. La herramienta requiere el SDK de plugins
que OpenCode instala en su configuración; si falta, no usar el backend Python para eludirlo.

Requisitos esenciales: **SQLite 3** y **Python 3**. El instalador los valida antes de escribir archivos y muestra el comando adecuado si falta alguno. OpenCode y Git también son recomendados para usar el equipo completo.

### Instalar, actualizar y reiniciar (receta única)

Instalar **siempre un release publicado** (`vX.Y.Z`), nunca `main`. La lista está en
[releases](https://github.com/alexskalling/skalling-dev-team/releases).

**1. Instalar (una vez por máquina)**

El tag `v0.19.0` todavía está pendiente de publicación. Hasta entonces, desde
el checkout local actualizado usa `bash install-global.sh`; los ejemplos de
clonación de abajo requieren que ese tag ya se haya publicado.

```bash
VERSION=v0.19.0   # requiere publicar este tag; también puede instalarse desde el checkout local
git clone --branch "$VERSION" --depth 1 https://github.com/alexskalling/skalling-dev-team.git ~/skalling-dev-team
bash ~/skalling-dev-team/install-global.sh
```

**2. Preparar cada proyecto** (una vez por proyecto, y de nuevo después de cada actualización)

```bash
cd ~/Proyectos/mi-proyecto
bash ~/skalling-dev-team/setup.sh
```

Esto instala hooks, plugins y la config de OpenCode del proyecto: Alex queda como agente
por defecto, junto con **Build** y **Plan** en el selector. Los siete especialistas de
Skalling son subagentes de Alex. Elegir Build o Plan permite trabajar fuera del flujo
de Skalling, conservando las restricciones nativas de Plan. Los commits desde
agentes nativos no necesitan un workflow ni un receipt Skalling; los controles de
secretos y la autorización de push siguen vigentes.
`/skalling-init`, dentro de OpenCode, aplica la misma config y además crea la memoria.

**3. Reiniciar OpenCode** para cargar agentes y plugins. Después: `bash ~/skalling-dev-team/setup-team-doctor.sh`.

**Actualizar:** `/skalling-update` (o `bash ~/skalling-dev-team/scripts/update.sh`). Cambia al
último release e instala; luego repetir el paso 2 en cada proyecto (actualiza agentes y
config locales, que reemplazan a los globales) y el paso 3.

**Windows** (Git Bash o WSL2, no nativo; en CI solo tiene smoke test):

```powershell
git clone --branch v0.19.0 --depth 1 https://github.com/alexskalling/skalling-dev-team.git $HOME\skalling-dev-team
.\skalling-dev-team\install-global.ps1
```

- `-Runtime GitBash` instala para herramientas ejecutadas desde Windows/Git Bash.
- `-Runtime WSL` instala dentro del `HOME` de Linux; en ese caso ejecutá también **OpenCode dentro de WSL**.
- Sin `-Runtime`, se elige Git Bash si está disponible y, en caso contrario, WSL2.
- Ubicación no estándar: `.\install-global.ps1 -SkallingDir "C:\ruta con espacios\skalling-dev-team"`.

### Code Intelligence (opt-in, v0.4.0+)

**Code Intelligence (opt-in)**: Skalling usa CodeGraph para responder preguntas estructurales como “¿quién llama a X?” o “¿qué afecta Y?” antes de recorrer muchos archivos. Su índice `.codegraph/` es independiente de TeamDB: TeamDB conserva conocimiento del proyecto; CodeGraph representa el código. Si CodeGraph no está disponible, los agentes informan la limitación y usan búsquedas normales.

### Límites de seguridad

Los hooks y receipts son controles locales de calidad, no una frontera de
seguridad frente a quien controla el checkout. Las decisiones críticas requieren
permisos del runtime y la integración confiable requiere CI y ramas protegidas.
Ver el [modelo de seguridad](docs/security-model.md).

### Uso en equipo

- **Permisos en lista blanca:** todo comando no listado pide autorización,
  incluido instalar paquetes, `gh`, herramientas de nube e infraestructura y
  cualquier comando que nombre rutas de credenciales.
- **Instalar solo releases:** `/skalling-update` ofrece el último tag `vX.Y.Z`,
  nunca `main`. Publicar un release solo desde un commit con CI en verde.
- **Commits desde tu terminal o IDE (sin OpenCode):** el hook exige que el
  candidato staged esté verificado. Después de `git add`, corré
  `bash .opencode/scripts/skalling-approve.sh` (proyecto preparado con `setup.sh`)
  o `bash ~/.config/opencode/scripts/skalling-approve.sh` (con `/skalling-init`):
  ejecuta los tests del proyecto sobre lo staged y, si pasan, habilita el
  `git commit`. El mensaje del hook indica la ruta correcta. Nunca `--no-verify`.
  La primera vez, para commitear la instalación misma, es el mismo paso.
- **CI y CODEOWNERS del proyecto:** `bash ~/skalling-dev-team/setup.sh --with-ci`
  agrega `.github/workflows/skalling-verify.yml` (re-corre los tests en la
  plataforma, donde no se pueden falsificar) y un `CODEOWNERS` de ejemplo.
  Reemplazá `@OWNER` y activá en GitHub el check obligatorio y la revisión de
  Code Owners en la rama principal.
- **En cada repositorio del equipo:** rama principal protegida y revisión
  obligatoria de `.opencode/**` y `db/teamdb/**`. Los hooks y plugins de
  Skalling ejecutan código de esas rutas en la máquina de cada integrante.
- **Memoria compartida:** `setup.sh` ignora la DB local (`team.db`) y
  configura el merge por fila del dump. `git pull` y `git pull --rebase`
  fusionan la memoria de los demás. Las entidades se emparejan por slug, así
  que dos personas pueden crear memoria a la vez sin pisarse.
- **Merges y rebases:** el gate de push acepta un merge automático o un rebase
  de trabajo ya verificado. Un merge con conflictos resueltos a mano necesita
  su propia verificación.

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

2. La primera vez Alex te va a sugerir `/skalling-init`. Ese comando prepara el proyecto completo: detecta el lenguaje y los tests, crea la memoria, instala agentes, plugins, scripts y hooks de Git dentro del proyecto (viajan por git: todo el equipo usa la misma versión) y deja a Alex como agente por defecto. Después, reiniciá OpenCode. Cada integrante que clone el repo corre `/skalling-init` una vez en su copia para activar los hooks (Git no los copia al clonar).

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
| `/skalling-help` | Indica rápidamente qué comando usar |
| `/skalling-init` | Prepara el proyecto por primera vez (detecta lenguaje, crea memoria) |
| `/skalling-status` | Muestra el estado del proyecto y el trabajo en curso |
| `/skalling-resume` | Recupera una cápsula mínima para continuar el trabajo |
| `/skalling-memory` | Busca, relaciona, grafica y revisa la memoria desde un solo lugar |
| `/skalling-metrics` | Reporta mediciones reales del flujo, sin estimar ahorros |
| `/skalling-coverage` | Corre la cobertura de tests del proyecto y guarda el resultado real |
| `/skalling-codegraph` | Analiza estructura, dependencias e impacto del código |
| `/skalling-dashboard` | Abre la vista local de TeamDB |
| `/skalling-refresh` | Vuelve a detectar el lenguaje y herramientas |
| `/skalling-doctor` | Revisa que la instalación esté sana |
| `/skalling-recover` | Recupera TeamDB desde el dump con backup y confirmación |
| `/skalling-merge` | Ayuda a resolver conflictos cuando trabajan varios |
| `/skalling-update` | Busca versiones nuevas de Skalling y las instala si confirmás |
| `/skalling-models` | Asigna un modelo de OpenCode a cada agente, individualmente |
| `/skalling-privacy` | Elige memoria compartida o instalación externa con exclusiones locales y controles de commit/push |

En un repositorio ajeno, usa `/skalling-init externo` desde el comienzo (CLI:
`bash setup.sh --target /ruta/proyecto --privacy external`). Las exclusiones se
guardan en `.git/info/exclude`; la instalación no añade reglas a `.gitignore`,
`.gitattributes`, `AGENTS.md` ni CI compartidos. Las actualizaciones conservan
ese modo. Si encuentra configuración ajena que tendría que sobrescribir,
se detiene. `/skalling-privacy externo` permite convertir una instalación
anterior: respalda y retira sus bloques marcados, pero no elimina archivos
rastreados ni reescribe el historial; los pendientes se informan explícitamente.

Los antiguos `/skalling-forget`, `/skalling-graph` y
`/skalling-graph-refresh` fueron consolidados en `/skalling-memory`.

---

## Ciclo de trabajo

El ciclo completo (riesgo alto) sigue este orden, cada paso registrado en `skalling_workflow`:

```
start     Alex clasifica con evidencia (archivos, aceptación, reutilización)
clarify   Pol acuerda alcance y criterios con vos
plan      Sol arma y aprueba el plan; ready habilita a Teo
deliver   Teo implementa (TDD) y entrega el candidato
check     Jhon verifica con un oráculo independiente; approve / reject
check     Luz revisa calidad y seguridad; approve con veredicto de riesgo
document  Pau guarda decisiones y memoria durable
complete  Alex cierra: prepara en Git lo revisado y sella la aprobación
```

Para cosas chicas (un typo, un color, un texto) la ruta es Alex → Teo y el motor corre `testing.fast` si el proyecto lo declara. Si no existe, Jhon escoge una verificación focal y amplía a `testing.unit` cuando el impacto lo justifica. Para auditorías, Alex manda a Luz directo.

### Flujo adaptativo y contexto económico

Teo, Jhon y Luz pueden crear commits locales cuando una unidad de trabajo está
verificada y conviene dejarla organizada, sin pedirte permiso por cada commit.
`commit` crea la unidad verificada conservando el staging ajeno. `complete` puede
cerrar sin commit: `commit_policy` es `allowed` por defecto, `required` si lo pide
el usuario y `forbidden` si lo prohíbe. Incluyen código, pruebas y
documentación relacionados y respetan cualquier instrucción de no commitear.
El usuario decide cuándo autorizar el push. Commitear no autoriza publicación.

Alex clasifica cada pedido por riesgo, no solo por cantidad de archivos:

- Bajo: Alex → Teo; el motor corre `testing.fast` si existe. Sin él, Jhon elige una verificación focal y recurre a la suite completa solo cuando el impacto lo justifica.
- Medio local, claro y reversible: Alex → Teo → Jhon. Si requiere varios pasos o dependencias: Alex → Sol → Teo → Jhon.
- Alto local y claro: Alex → Teo → Jhon/Luz; planificación si hace falta y Pau si hay conocimiento durable. Las decisiones pendientes se resuelven antes de implementar.

Antes del primer handoff se crea una cápsula de hasta 8 KB: resumen general, memoria relacionada y ubicaciones obtenidas con Code Intelligence. Esa cápsula se reutiliza; los agentes amplían contexto solo bajo demanda. Pau participa cuando hay conocimiento duradero que registrar. Markdown sigue siendo documentación o export explícito, nunca transporte entre agentes.

`skalling-metrics.sh` registra ruta, agentes, handoffs, solicitudes de permiso, bytes de contexto, duración y resultado. No inventa consumo de tokens: si el runtime no expone tokens reales, reporta bytes de contexto como métrica verificable.

---

## Reglas del equipo (R1 a R17)

| # | Regla |
|---|---|
| R1 | Código según las convenciones del proyecto; comunicación y commits en español |
| R2 | Comentarios solo para decisiones, restricciones o riesgos no evidentes |
| R3 | Tipado y validación proporcionales al lenguaje y al riesgo |
| R4 | TDD para comportamiento y bugs; verificación equivalente para configuración |
| R5 | Verificación independiente proporcional al riesgo |
| R6 | SDD para features que cruzan módulos, requieren decisiones/dependencias o tienen riesgo alto; los cambios locales, claros y reversibles usan focused. Lo ambiguo se aclara antes de implementar. |
| R7 | Clean Architecture cuando el proyecto adopta arquitectura por capas |
| R8 | Nombres descriptivos — nada de abreviaciones crípticas |
| R9 | Revisar funciones extensas por responsabilidad, no por una cifra aislada |
| R10 | Manejo de errores explícito — nada de try/catch vacíos |
| R11 | Sin código muerto — nada de console.log, variables sin usar |
| R12 | Cada proyecto tiene su propia memoria |
| R13 | Si hay interfaz gráfica, necesita un `design-system.md` en `.opencode/context/proyecto/` |
| R15 | Siempre la solución más simple posible (Escalera de Ponytail) |
| R16 | Reglas para trabajar en equipo sin pisarse |
| R17 | Teo, Jhon y Luz pueden crear commits locales de unidades verificadas; push y publicación requieren tu autorización |

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
│   └── constitucion.md               # Las 17 reglas
├── command/                          # Los 17 comandos /skalling-*
├── skills-base/                      # Habilidades de los agentes (7 skalling-* core)
├── templates/                        # Plantillas
├── data/                             # Detectores de lenguajes
└── tests/
    ├── setup.test.sh                 # 200+ comprobaciones
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
| WSL2 | ⚠️ Capa de compatibilidad; OpenCode debe ejecutarse dentro del mismo WSL. Solo smoke test en CI |
| Git Bash | ⚠️ Capa de compatibilidad; requiere SQLite 3 y Python 3. Solo smoke test en CI |
| PowerShell | ⚠️ Solo wrapper: delega en Git Bash o WSL (no hay implementación nativa) |
| cmd.exe | ❌ |

---

## Tests

```bash
cd ~/skalling-dev-team
bash tests/setup.test.sh
bash tests/scripts-parity.test.sh   # bundle local scripts/ ↔ .opencode/scripts/
```

268+ pruebas que verifican agentes, reglas, comandos, scripts, detección de lenguajes, instalación completa, helpers de memoria y doctor.

El test `scripts-parity.test.sh` garantiza que la copia local
`.opencode/scripts/` no diverge de `scripts/`. Si drift, regenerá con:

```bash
bash scripts/build-local-snapshot.sh --apply   # sincroniza
bash scripts/build-local-snapshot.sh --check   # exit 0 si sin drift
```

Más detalle en [`AGENTS.md`](./AGENTS.md#bundle-local-opencodescripts).

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

Los receipts (`skalling-receipt`) formalizan cada verificación con evidence antes de claims.

**Memoria del proyecto**: Los agentes organizan los conceptos en TeamDB con 4 secciones (What/Why/Where/Learned), un snippet de Memory Protocol en cada agente que fuerza el guardado de decisiones y marcado de contradicciones, detección de conflictos en Pol antes de cerrar proposals, y herramientas de salud (`mem-review`, sección de memoria en el doctor) que detectan huérfanos, WIP zombie, duplicados y docs stale o superseded.

---

## TeamDB (SQLite)

Skalling usa **SQLite** como fuente de verdad para memoria y seguimiento del trabajo.

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

# Importación manual de exports legacy data_*.sql → DB
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

> **Legacy de solo lectura**: `work_in_progress` y `wip-tree.sh` se conservan únicamente para consultar instalaciones antiguas. El inicio de sesión, el contexto y el ciclo operativo usan `proposals`/`plans`/`tasks`. Las tablas históricas `code_graph_cache` y `code_imports` no reciben escrituras nuevas; CodeGraph mantiene su propio índice. `task_lock_history` es la misma categoría: la escribía `teamdb-claim-task.sh` (CAS simple, sin lease), removido porque el ciclo de claims real usa `teamdb-claim.sh` (lease/epoch, transiciones verificadas por rol) desde antes de que ese script tuviera algún caller activo.

### Hooks git

- `pre-commit`: valida que lo staged coincida con un receipt aprobado de Jhon o Luz (tree_hash). Todo cambio lo necesita salvo documentación (`.md`, `.txt`…), imágenes y fuentes; los `.md` que definen conducta de agentes (`.opencode/agents`, comandos, skills) sí lo necesitan.
- `pre-push`: la misma validación por cada commit que se publica.
- `post-merge`: importa `.sql` → DB después de hacer pull.

La instalación **no pisa hooks existentes**: un hook previo del proyecto queda como
`<hook>.skalling-prev` y el de Skalling lo ejecuta primero; `setup.sh --uninstall` lo
restaura. Si el proyecto usa `core.hooksPath` (husky, carpeta versionada), no se toca esa
carpeta: el instalador avisa cómo agregar la llamada a `.opencode/hooks/<hook>` y el doctor
marca el gate como inactivo hasta que se haga.

**Qué aprueba un commit.** Dentro de OpenCode, solo la aprobación que sella
`skalling_workflow complete`. Fuera de OpenCode (una persona en su terminal),
`teamdb-seal-receipt.sh <task> jhon` corre el test real del proyecto
(`testing.unit.command`) y sella solo si el candidato staged es el mismo antes y después.
Sin test configurado el receipt queda `not_run` (exit 2) y **no aprueba**: hay que
configurar el test o que la persona apruebe sin tests:

```bash
SKALLING_VERIFY_WAIVER="motivo concreto" bash .opencode/scripts/teamdb-seal-receipt.sh <task> jhon
```

El gate acepta ese receipt `waived` y lo anuncia en cada commit. Un agente no puede fijar
esa variable (el guard lo bloquea).

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

Cada finding se emite con severidad `BLOCKER` (falla el review), `WARNING` o `INFO`. Corrida por una persona en su terminal, al final sella un **receipt inmutable** (`scripts/teamdb-seal-receipt.sh`) con `tree_hash`: el hash SHA-256 (16 chars) del diff staged (`git diff --cached`, que incluye los blobs y modos de cada archivo cambiado). Si semgrep no está o no pudo correr, el resultado dice `PASS (degradado: sin SAST)`; con `SKALLING_REQUIRE_SAST=1` eso es `FAIL`. El `pre-commit` compara ese hash con el árbol staged: si alguien tocó una línea después de la revisión, el commit se bloquea hasta re-sellar o revertir. Dentro de OpenCode la revisión no sella por su cuenta: Luz la corre como `check` de `skalling_workflow`.

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
