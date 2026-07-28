# Skalling

Skalling es un equipo de 8 robots que te ayudan a programar. Funciona adentro de OpenCode.

Los robots trabajan en cadena: uno pregunta, otro planea, otro codea, otro revisa, otro documenta. Todo ordenado, nada se salta pasos.

---

## Los 8 robots

**Alex** — El que te recibe cuando hablás. Decide a qué robot mandarte según lo que necesites.

- Si preguntás algo → te responde
- Si querés aprender → llama a Jes
- Si querés construir algo nuevo → arranca el ciclo con Pol
- Si hay un bug → manda a Teo directo
- Si querés una auditoría → manda a Luz directo
- Si querés commit → pide permiso primero
- Si no entiende qué querés → pregunta con opciones

**Pol** — Te hace preguntas para entender bien qué necesitás. Una por una. No avanza hasta que digas "ok". Así no se construyen cosas al pedo.

**Jes** — Si necesitás entender algo, Jes te lo explica. Busca en internet antes de responder.

**Sol** — Toma lo que vos y Pol acordaron y arma un plan paso a paso: qué archivos tocar, en qué orden, cómo probarlo.

**Teo** — El que escribe código. Primero escribe el test, después el código para que pase. No codea nada sin un test que falle antes.

**Jhon** — Revisa que los tests de Teo pasen. También corre todos los tests al final para asegurar que no se rompió nada.

**Luz** — Revisa el código terminado: calidad, seguridad, rendimiento. Si encuentra problemas, lo devuelve a Teo.

**Pau** — Cuando Luz aprueba todo, Pau guarda los cambios en la documentación y en la memoria del proyecto.

---

## Instalación

### Mac / Linux

Abrí la terminal y pegá esto:

```bash
git clone https://github.com/alexskalling/skalling-dev-team.git ~/skalling-dev-team
bash ~/skalling-dev-team/install-global.sh
```

### Windows

```powershell
git clone https://github.com/alexskalling/skalling-dev-team.git $HOME\skalling-dev-team
.\skalling-dev-team\install-global.ps1
```

Necesitás Windows 10+ y Git Bash o WSL2.

---

## Cómo se usa

1. Abrí OpenCode en tu proyecto:

```bash
cd ~/Proyectos/mi-proyecto
opencode
```

2. La primera vez, Alex te va a decir algo como "¿Querés iniciar Skalling?". Decí que sí o escribí `/skalling-init`. Esto prepara el proyecto (crea la memoria, detecta el lenguaje que usás, etc.).

3. Ya podés pedir cosas:

```
"haceme un login con JWT"
"explicame qué es React"
"revisá la seguridad del código de auth"
"cómo vamos con el proyecto?"
```

---

## Comandos

Escribí cualquiera de estos adentro de OpenCode:

| Comando | Qué hace |
|---|---|
| `/skalling-init` | Prepara el proyecto por primera vez |
| `/skalling-status` | Muestra el estado del proyecto |
| `/skalling-refresh` | Vuelve a detectar el lenguaje y herramientas |
| `/skalling-doctor` | Revisa que todo esté bien instalado |
| `/skalling-forget` | Limpia cosas viejas de la memoria |
| `/skalling-merge` | Ayuda a arreglar conflictos cuando trabajan varios |
| `/skalling-update` | Busca versiones nuevas de Skalling y las instala |

---

## Cómo se construyen las cosas (el ciclo)

Cuando pedís algo nuevo, los robots siguen estos pasos en orden:

```
1. Alex te recibe y entiende qué querés
2. Pol te pregunta hasta entender bien
3. Sol escribe un plan
4. Teo codea y Jhon revisa los tests
   (esto se repite hasta terminar todo)
5. Jhon corre todos los tests otra vez
6. Luz revisa calidad y seguridad
7. Pau guarda todo en los documentos
```

Para cosas chicas (un typo, cambiar un color), Teo puede codear directo sin todo el ciclo.

Para auditorías, Luz puede revisar directo sin pasar por Pol/Sol/Teo/Jhon.

---

## Las reglas del equipo (R1 a R16)

Los robots siguen estas reglas siempre:

| # | Regla |
|---|---|
| R1 | Todo el código en español |
| R2 | Nada de comentarios — el código se explica solo |
| R3 | Tipos estrictos — nada de `any` |
| R4 | Test antes de código — siempre |
| R5 | No saltarse pasos del ciclo |
| R6 | Plan escrito antes de construir |
| R7 | Código ordenado en capas |
| R8 | Nombres que se entiendan |
| R9 | Funciones de máximo 30 líneas |
| R10 | Errores manejados explícitamente, nada de try/catch vacíos |
| R11 | Nada de código muerto (console.log, variables sin usar) |
| R12 | Cada proyecto tiene su propia memoria |
| R13 | Si hay interfaz gráfica, necesita un archivo de diseño (no se sube al repo) |
| R14 | Siempre la solución más simple posible |
| R15 | Reglas para trabajar en equipo sin pisarse |
| R16 | No se hace commit sin preguntarte antes |

---

## Archivos del proyecto

### Donde está Skalling (este repo)

```
skalling-dev-team/
├── install-global.sh             # Instalador para Mac/Linux
├── install-global.ps1            # Instalador para Windows
├── setup.sh                      # Para compartir Skalling con tu equipo
├── setup.ps1                     # Lo mismo en PowerShell
├── setup-team-doctor.sh          # Revisa que todo funcione
├── bootstrap-context.sh          # Prepara un proyecto nuevo
├── scripts/
│   ├── merge-helper.sh           # Ayuda con conflictos
│   ├── update.sh                 # Actualiza Skalling
│   └── lib/lib-os.sh             # Detecta el sistema operativo
├── agents-base/                  # Los 8 robots
├── constitution/
│   └── constitucion.md           # Las reglas del equipo
├── command/                      # Los 7 comandos /skalling-*
├── skills-base/                  # Habilidades de los robots
├── templates/                    # Plantillas
├── data/                         # Info para detectar lenguajes
└── tests/
    └── setup.test.sh             # Pruebas del instalador
```

### Lo que se instala en tu compu

```
~/.config/opencode/
├── agents/                       # Los 8 robots
├── skills/                       # Habilidades
├── command/                      # Comandos
├── constitucion.md               # Reglas
├── templates/                    # Plantillas
└── skalling-data/                # Detectores de lenguajes
```

### Lo que se crea en cada proyecto donde lo usás

```
tu-proyecto/.opencode/
├── .gitattributes                # Para trabajar en equipo sin conflictos
├── agents/                       # (opcional) Robots personalizados
├── skills/                       # Habilidades para tu lenguaje
├── context/                      # Memoria del proyecto
├── changes/                      # Planes de las cosas que construís
└── project.yaml                  # Qué lenguaje y herramientas usás
```

---

## Sistemas operativos

| Sistema | Anda? |
|---|---|
| Mac | ✅ |
| Linux | ✅ |
| WSL2 (Windows) | ✅ |
| Git Bash (Windows) | ✅ |
| PowerShell (Windows) | ✅ (usa Git Bash atrás) |
| cmd.exe (Windows) | ❌ |

---

## Verificar que todo funciona

```bash
cd ~/skalling-dev-team
bash tests/setup.test.sh
```

Eso corre 150+ pruebas para asegurar que los robots, las reglas y los comandos están bien.

Si algo anda mal:

```bash
cd ~/skalling-dev-team
bash setup-team-doctor.sh
```

O desde OpenCode: `/skalling-doctor`

---

## Licencia

MIT.
