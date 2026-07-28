# Constitución Universal de Skalling

> **Esta constitución aplica a todos los proyectos que usen Skalling.**
> Es leída por Alex al inicio de cada sesión y consultada por el resto del equipo.
> Las reglas son universales — aplican a cualquier stack o lenguaje.

---

## 🏛️ Reglas Base (universales)

### R1 — Idioma
Todo el código (variables, funciones, clases, archivos, commits) en **ESPAÑOL**.

Excepciones:
- Nombres de librerías externas y sus APIs.
- Comentarios en código (no permitidos — ver R2).
- Mensajes de error al usuario final (pueden ser en el idioma del usuario).

### R2 — Cero Comentarios en Código
El código es autodocumentado. El "por qué" vive en `.opencode/context/` o en `docs/`.

Excepciones:
- Docstrings públicos en APIs (JSDoc, docstrings Python) solo cuando documentan comportamiento, no implementación.
- Anotaciones de tipo (no son comentarios, son contratos).

### R3 — Tipado Estricto
Sin tipos implícitos ni `any` (o equivalentes) en el lenguaje del proyecto.

### R4 — TDD Obligatorio (Iron Law)
**NO HAY CÓDIGO DE LÓGICA DE NEGOCIO SIN UN TEST QUE FALLE PRIMERO.**

```
RED:    escribí el test → verificá que falla correctamente
GREEN:  escribí el código mínimo para pasar el test
REFACTOR: mejorá el código con el test como red de seguridad
```

Violaciones:
- Escribir código antes del test → **borrar y empezar de nuevo**.
- "Lo dejo como referencia" → no. Borrar.
- "Lo adapto mientras escribo tests" → no. Borrar.

Excepciones (consultar con el equipo):
- Prototipos descartables.
- Código generado automáticamente.
- Archivos de configuración.

### R5 — Calidad Total
Ningún código está terminado sin pasar el flujo completo:
**Teo → Jhon (por tarea + regresión) → Luz (quality gate) → Pau (documentación).**

### R6 — SDD Formal
Features nuevas siguen Spec-Driven Development:
1. **Proposal**: qué, por qué, rollback.
2. **Specs**: Given/When/Then + keywords MUST/SHALL/SHOULD/MAY (RFC 2119).
3. **Design**: arquitectura, decisiones, diagramas.
4. **Tasks**: desglose 1.1, 1.2 por fase.

Ubicación: `.opencode/changes/<feature-slug>/`. Archivado en `.opencode/changes/archive/` al terminar.

### R7 — Clean Architecture
Las dependencias apuntan hacia el centro:
```
ui → infrastructure → application → domain
```

Reglas:
- `domain/` no importa nada externo.
- `application/` solo importa `domain/`.
- `infrastructure/` importa `application/` y `domain/`.
- `ui/` puede importar `application/` y `domain/`, nunca `infrastructure/` directo.

Vertical Slicing es alternativa válida: organizar por feature, no por capa técnica.

### R8 — Nombres Descriptivos
Sin abreviaciones crípticas. Si un nombre necesita comentario para explicarse, está mal nombrado.

### R9 — Funciones Pequeñas
Si una función supera 30 líneas o tiene más de 3 niveles de anidación, refactorizar.

### R10 — Manejo de Errores
- Prohibido `try/catch` vacío o genérico.
- Prohibido ignorar errores silenciosamente.
- Toda función que puede fallar debe tener un manejo de error explícito.

### R11 — Sin Código Muerto
Prohibido:
- Código comentado.
- Variables no usadas.
- Funciones no llamadas.
- `console.log` / `print` de debug.

### R12 — Memoria por Proyecto
Cada proyecto tiene su propio bundle OKF en `.opencode/context/`. **Nunca** se comparte entre proyectos.

---

## 🎨 R13 — DESIGN.md Obligatorio para Interfaz Gráfica

> **Todo proyecto con interfaz gráfica debe tener un `DESIGN.md` versionado.**

### Aplicación
Se activa cuando el proyecto tiene:
- Componentes UI (React, Vue, Svelte, etc.).
- Páginas web renderizadas (Next.js, Astro, etc.).
- Apps móviles (React Native, Flutter, Swift, etc.).
- Cualquier interfaz de usuario visible.

### Enforcement
- **Bootstrap** (`/skalling-init`): si detecta frontend y no existe `DESIGN.md`, lo crea (auto-generado con Impeccable `/impeccable document` o template manual).
- **Luz** (quality gate): rechaza cualquier feature visual si el código no es coherente con el `DESIGN.md`.
- **Pau** (documentalista): sincroniza `DESIGN.md` ↔ `docs/design/DESIGN.md` ↔ `.opencode/context/proyecto/design-system.md`.

### Ubicación
- **Fuente de verdad**: `docs/design/DESIGN.md` (commiteado al repo).
- **Mirror bundle OKF**: `.opencode/context/proyecto/design-system.md` (link + resumen).
- **Output Impeccable**: `DESIGN.md` en formato Google Stitch (portable).

### Estructura mínima
```yaml
---
type: Concept
title: Design System del proyecto
description: Sistema visual y reglas de diseño UI
resource: docs/design/DESIGN.md
tags: [design, ui, design-system]
timestamp: YYYY-MM-DDTHH:MM:SSZ
agent: pau
confidence: 1.0
---

# Design System

[Link a docs/design/DESIGN.md]

## Modos de uso (Impeccable)
- Persuade (landing): captar atención
- Operate (dashboard):完成任务
- Read (docs): construir comprensión
- Experience (portfolio): dejar que el trabajo guíe

## Tokens
- Colores: [referencia]
- Tipografía: [referencia]
- Espaciado: [referencia]
- Componentes: [referencia]

## Anti-references
[Qué NO hacer: AI beige, italic serif en h1, side-tabs, status-chip soup, etc.]
```

---

## 🧠 Reglas de Memoria OKF

### Catálogo de tipos de concept docs
| Type | Uso |
|---|---|
| `Concept` | Cosa del proyecto (stack, módulo, API, tabla) |
| `Decision` | Decisión arquitectónica o de scope (ADR) |
| `Preference` | Preferencia del equipo o del usuario |
| `Workaround` | Solución temporal a un problema conocido |
| `WorkInProgress` | Feature o tarea activa |
| `Context` | Información general que no encaja en las anteriores |

### Schema de frontmatter (OKF v0.1 + extensiones)
```yaml
---
type: [uno de los 6 tipos]
title: [título humano]
description: [una línea]
resource: [URL o path al origen]
tags: [array]
timestamp: YYYY-MM-DDTHH:MM:SSZ
agent: [quién lo escribió]
confidence: 0.0-1.0      # opcional, OKF v0.2
supersedes: [path a versión anterior]   # opcional, OKF v0.2
---
```

### Política de olvido
- Concept docs con `supersedes` linkean a versión anterior (la vieja queda pero marcada).
- Pau consolida duplicados cada 6 meses.
- Concept docs sin referenciar por 12 meses → marcados `⚠️ revisar vigencia`.

---

## 🔧 Reglas por Stack (se activan condicionalmente según `project.yaml`)

### Si `stack.language == "typescript"` o `"javascript"`
- TypeScript strict mode, sin `any`.
- Tests: Vitest o Jest + React Testing Library.
- Framework preferido: Next.js App Router con Server Components por defecto.
- Validación: Zod.
- Formato: Prettier.

### Si `stack.language == "python"`
- Type hints obligatorios, sin `Any`.
- Tests: Pytest obligatorio.
- Framework preferido: FastAPI para APIs, Django para full-stack.
- Validación: Pydantic.
- Formato: Black + isort.

### Si `stack.language == "rust"`
- El compilador es la ley.
- Tests unitarios con `#[test]` + tests de integración en `/tests`.
- Validación: `serde` para serialización, `validator` para reglas de negocio.

### Si `stack.language == "go"`
- `gofmt` siempre.
- Tests con `testing` package estándar.
- Errores como valores, no panic.
- Framework preferido: stdlib + `chi` o `gin` solo si hay routing complejo.

### Si `stack.language == "java"` o `"kotlin"`
- Maven o Gradle según convención del proyecto.
- Tests: JUnit 5.
- Validación: Bean Validation.
- Framework preferido: Spring Boot o Quarkus.

### Si `stack.framework == "nextjs"`
- App Router (no Pages Router).
- Server Components por defecto, Client Components solo cuando necesario.
- `next-cache-components` skill se activa automáticamente.

### Si `stack.framework == "react"` (sin Next.js)
- Vite como bundler preferido.
- shadcn/ui como sistema de componentes base.
- Tailwind CSS para estilos.

### Si `stack.framework == "vue"`
- Composition API (no Options API).
- Pinia para estado.
- Vite.

### Si el stack tiene UI (cualquier framework frontend)
- **REGLA #13 activa**: `DESIGN.md` obligatorio.
- Impeccable se recomienda (Fase 12).
- `npx impeccable detect <src>` corre como quality gate.

---

## 🤖 Recomendación de Modelos por Agente (opcional, sugerencia)

Esta tabla es **sugerencia**, no imposición. El usuario puede overridear por agente en `opencode.json`.

| Agente | Razón | Modelo sugerido |
|---|---|---|
| **Alex** | Razonamiento + clasificación | proveedor-default |
| **Pol** | Cuestionamiento + negociación | proveedor-default |
| **Jes** | Investigación + lectura larga | modelo con contexto largo |
| **Sol** | Planning + descomposición | proveedor-default |
| **Teo** | Implementación + debugging | modelo más capaz disponible |
| **Jhon** | Tests rápidos, ejecución masiva | modelo rápido y barato |
| **Luz** | Análisis estático profundo | modelo más capaz disponible |
| **Pau** | Escritura de prosa, documentación | modelo bueno en lenguaje natural |

Los frontmatter de los agentes **no incluyen `model:`**. Heredan del provider global configurado en `opencode.json`.

---

## 🔄 Handoff entre Agentes

### Formato JSON obligatorio
```json
{
  "from": "TEO",
  "to": "JHON",
  "task": "Verificar tests del módulo auth",
  "summary": "Implementado login con JWT, 5 tests creados",
  "artifacts": ["/src/auth/login.ts", "/tests/auth/login.test.ts"],
  "tests_passed": true,
  "coverage": 85,
  "next_action": "Ejecutar suite de regresión"
}
```

### Reglas
1. El agente receptor debe confirmar recepción.
2. Si hay errores, el handoff incluye razón específica.
3. El handoff se registra en `.opencode/state/workflow.json`.

---

## 🚦 Resolución de Conflictos

| Conflicto | Resolución |
|---|---|
| Pol y usuario no se alinean | Alex presenta opciones con pros/contras al usuario |
| Teo objeta plan de Sol | Sol y Teo replantean; si no hay acuerdo, escala al usuario |
| Luz rechaza algo ya aprobado | Alex notifica al usuario con motivo específico de Luz |
| Jhon y Luz tienen criterios distintos | Jhon prioridad en tests, Luz en seguridad/clean code |

---

## 🔁 Protocolo de Escalación

Si un agente llega al máximo de iteraciones sin resolución:

| Fase | Max iter | Si se agota |
|---|---|---|
| Teo ↔ Jhon | 3 | Alex notifica al usuario |
| Jhon ↔ Luz | 3 | Alex notifica al usuario |
| Luz ↔ Pau | 2 | Alex notifica al usuario |

**Regla**: el ciclo nunca se bloquea silenciosamente. Siempre escala.

---

## 📋 Estándar de Preguntas con Opciones

Todos los agentes usan este formato cuando necesitan información del usuario:
```
[Pregunta concreta]
A) [Opción 1] — [descripción breve]
B) [Opción 2] — [descripción breve]
C) [Opción 3] — [descripción breve]
D) Lo explico yo con mis palabras
```

**Reglas**:
- Una pregunta a la vez.
- Esperar respuesta (nunca autoresponder).
- Máximo 4 opciones.
- Siempre incluir "Otro / lo explico yo" cuando aplique.

---

## 🪜 R14 — Escalera de Ponytail (Lazy Senior Dev)

> Inspirado en [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail).
> Filosofía: "lazy about the solution, never about reading".
> Antes de escribir código, recorrer la escalera hasta el primer peldaño que sirve.

### La Escalera

```
1. ¿Necesita existir?              → NO: skip (YAGNI)
2. ¿Ya está en este codebase?      → SÍ: reusar, no reescribir
3. ¿Stdlib lo hace?                → SÍ: usarlo
4. ¿Feature nativa de la plataforma? → SÍ: usarla
5. ¿Dependencia ya instalada?      → SÍ: usarla
6. ¿Una línea?                     → SÍ: una línea
7. Recién entonces: el mínimo que funcione
```

### Reglas

- **Aplicar ANTES de implementar**, no después.
- **Lazy about solution, never about reading**: leer el código que se toca antes de decidir.
- **Trust boundaries no son negociables**: validación, manejo de errores, seguridad, accesibilidad **nunca** se cortan.
- **Jhon y Luz también la aplican**: si Teo escribió 50 líneas cuando 1 bastaba, fallar el review.

### Anti-patrones explícitos

- Instalar librería externa cuando stdlib lo hace.
- Crear wrapper cuando la feature nativa existe.
- Reescribir código que ya está en el codebase.
- Escribir abstracción para un solo uso.
- Agregar configuración cuando el default sirve.

---

## 🤝 R15 — Resolución de Conflictos Colaborativos (Memoria Compartida)

> Cuando dos o más devs trabajan en paralelo y commitean cambios en `.opencode/`,
> git no puede auto-mergear todo. Esta regla define cómo Skalling maneja esos conflictos.

### Estrategias por tipo de archivo (via `.gitattributes`)

| Archivo | Estrategia | Por qué |
|---|---|---|
| `context/log.md` | `merge=union` | Append-only, ambas entradas son válidas |
| `context/index.md` | `merge=union` | Regenerable, Pau deduplica |
| `context/README.md` | `merge=union` | Regenerable |
| `state/workflow.json` | `merge=lock` | Solo UN ciclo activo a la vez |
| `context/constitucion.md` | `merge=lock` | Cambios requieren consenso |
| `decisiones/*.md` | Manual | Concept docs pueden tener contenido distinto |
| `trabajo-en-curso/*.md` | Manual | Features distintas pueden tener mismo slug |
| `preferencias/*.md` | Manual | Preferencias son colectivas |
| `cambios/<feature>/*.md` | Manual | Mismo feature = serializar trabajo |
| `project.yaml` | `merge=union` | Regenerable con `/skalling-refresh` |

### Reglas para devs

1. **Un feature por branch** — minimiza conflictos en `trabajo-en-curso/` y `cambios/`.
2. **Sufijo de autor en ADRs** — `YYYY-MM-DD-titulo-JPM.md` para evitar colisiones.
3. **Lock del ciclo** — si `workflow.json` está en lock, hablar con el otro dev antes de iniciar.
4. **Git worktrees para features grandes** — `git worktree add ../mi-feature feat/auth`.
5. **NO aceptar ours/theirs sin leer** — pérdida silenciosa de información.
6. **Regenerar cuando aplica** — `index.md` y `project.yaml` se pueden borrar y regenerar.

### Reglas para Pau (al resolver conflictos)

1. **Documentar resolución en `log.md`** — append entry con quién, qué, por qué.
2. **Escalar al equipo si la decisión es colectiva** — constitución, preferencias.
3. **Aplicar `supersedes:` cuando una versión reemplaza a otra**.
4. **Nunca forzar merge de constitución** — es lock por diseño.
5. **Usar `/skalling-merge` o `scripts/merge-helper.sh`** para asistencia.

### Conflictos comunes y resolución rápida

| Escenario | Resolución |
|---|---|
| Dos devs crean mismo `2026-XX-XX-titulo.md` | Renombrar uno con sufijo de autor |
| Mismo feature en distintas branches | Serializar o mergear manualmente |
| log.md conflictivo | Verificar `.gitattributes`, regenerar si se rompió |
| workflow.json conflictivo | Decidir quién continúa, el otro toma `theirs` o `ours` |
| Constitución conflictiva | Escalar al equipo, decisión colectiva |
| Preferencias contradictorias | Escalar, son reglas del equipo |

### Workflow recomendado

```
1. Antes de mergear:   bash scripts/merge-helper.sh
2. Detectar conflictos: el script lista archivos y sugiere
3. Resolver manualmente: leer ambas versiones, decidir
4. Documentar:         append al log.md
5. Commitear:          git commit -m "merge: resolver conflicto X"
6. Prevenir futuro:    considerar sufijo de autor, worktree, branch por feature
```

---

## 🛠️ Comandos del Proyecto (referencia)

Los comandos se adaptan al stack detectado en `project.yaml`.

| Acción | JS/TS | Python | Rust | Go |
|---|---|---|---|---|
| Instalar deps | `npm install` | `pip install -r requirements.txt` | `cargo build` | `go mod download` |
| Desarrollo | `npm run dev` | `uvicorn main:app --reload` | `cargo run` | `go run` |
| Tests | `npm test` | `pytest` | `cargo test` | `go test ./...` |
| Build | `npm run build` | `python -m build` | `cargo build --release` | `go build` |

---

## 🔗 Referencias Cruzadas

- Constitución de proyecto: `~/.config/opencode/constitucion.md` (este archivo).
- Constitution de Skalling: `skalling-dev-team/constitucion/constitucion.md` (source).
- Bundle de memoria del proyecto: `.opencode/context/`.
- Cambios SDD: `.opencode/changes/`.
- Skills disponibles: `~/.config/opencode/skills/`.
- Comandos: `/skalling-init`, `/skalling-status`, `/skalling-refresh`, `/skalling-doctor`, `/skalling-forget`.

---

*Última actualización: 2026-07-28*
*Versión: skalling-constitution-v1*
