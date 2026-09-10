# Constitución Universal de Skalling

> **Esta constitución aplica a todos los proyectos que usen Skalling.**
> Es leída por Alex al inicio de cada sesión y consultada por el resto del equipo.
> Las reglas son universales — aplican a cualquier stack o lenguaje.

---

## 🏛️ Reglas Base (universales)

### R1 — Idioma
El código sigue el idioma y las convenciones ya establecidas por cada proyecto.
La comunicación con el usuario y los commits de Skalling se escriben en español.

Excepciones:
- Nombres de librerías externas y sus APIs.
- Identificadores impuestos por frameworks, formatos, protocolos y herramientas.
- Mensajes de error al usuario final (pueden ser en el idioma del usuario).

### R2 — Comentarios con Propósito
Los comentarios explican decisiones, restricciones, compatibilidad o riesgos que el
código no puede expresar por sí mismo. No repiten literalmente la implementación.
Las APIs públicas pueden usar docstrings o JSDoc cuando aporten un contrato útil.

### R3 — Tipado Proporcional
En lenguajes tipados se usa el modo estricto disponible y se evita `any` salvo en
fronteras externas justificadas. En lenguajes dinámicos se validan explícitamente
las entradas y salidas críticas.

### R4 — Pruebas Proporcionales al Riesgo
Los cambios de comportamiento y los bugs usan RED → GREEN → REFACTOR. Los cambios
de configuración, documentación, código generado o integración sin harness viable
requieren la comprobación automatizada más cercana y evidencia reproducible.

```
RED:    escribí el test → verificá que falla correctamente
GREEN:  escribí el código mínimo para pasar el test
REFACTOR: mejorá el código con el test como red de seguridad
```

No se declara corregido un bug sin una prueba que reproduzca el fallo o, cuando
esto no sea técnicamente viable, una explicación explícita y una verificación equivalente.

### R5 — Calidad Total
Ningún código está terminado sin verificación independiente proporcional al riesgo.
Las rutas pequeñas pueden usar Teo → Jhon; seguridad, datos y cambios de alto riesgo
añaden Luz. Pau participa cuando existe conocimiento durable que conservar.

### R6 — SDD Formal
Features nuevas de alcance medio, alto o ambiguo siguen Spec-Driven Development:
1. **Proposal**: qué, por qué, rollback.
2. **Specs**: Given/When/Then + keywords MUST/SHALL/SHOULD/MAY (RFC 2119).
3. **Design**: arquitectura, decisiones, diagramas.
4. **Tasks**: desglose 1.1, 1.2 por fase.

Persistencia: proposals, specs, plans y tasks en TeamDB. Markdown solo como exportación explícita.

### R7 — Clean Architecture
Cuando el proyecto usa arquitectura por capas, las dependencias apuntan hacia el centro:
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
Si una función supera aproximadamente 30 líneas o tiene más de 3 niveles de
anidación, revisar si contiene más de una responsabilidad. Se refactoriza cuando
mejora legibilidad, pruebas o reutilización; no para cumplir una cifra aislada.

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
Cada proyecto tiene su propia TeamDB en `.opencode/context/team.db`. **Nunca** se comparte entre proyectos.

---

## 🎨 R13 — Sistema de diseño para interfaz gráfica

Todo proyecto con UI conserva el concepto `design-system` en TeamDB.
El bootstrap registra evidencia detectada, no una identidad validada por el usuario.
Teo debe leer las reglas completas, los componentes existentes y sus estilos antes
de implementar. Si hay identidades incompatibles, Alex solicita la elección necesaria.
Pau conserva decisiones confirmadas en TeamDB. `design-system.md` es una exportación
opcional para revisión humana; ningún flujo exige crear carpetas o Markdown interno.

---

## R14 — Recuperación proporcional de contexto

**Motivación**: TeamDB recupera conocimiento durable y CodeGraph responde preguntas
estructurales. Son fuentes distintas; ninguna debe fingir ser la otra.

**Regla universal**: los 8 agentes consultan TeamDB antes de releer documentación y
CodeGraph antes de una exploración estructural amplia. Para una ruta conocida o un
cambio trivial, leen directamente el archivo necesario.

- **Alex**: delegar a cualquier agente o responder "¿ya existe X?"
- **Pol**: validar intent del usuario y escribir `proposal.md`
- **Jes**: investigar (consultar grafo antes de `grep`/`read`)
- **Sol**: diseñar un plan técnico
- **Teo**: implementar cambios
- **Jhon**: verificar regresión
- **Luz**: auditar calidad/seguridad
- **Pau**: consolidar memoria definitiva

### Comandos

- `/skalling-memory search|related|graph|review|refresh` opera sobre memoria.
- `/skalling-codegraph` usa CodeGraph real para arquitectura, llamadas e impacto.

### Por qué

Esto limita la lectura irrelevante sin sacrificar evidencia. No se declara un ahorro
cuantitativo de tokens o tiempo a menos que `/skalling-metrics` tenga mediciones reales.

### Pau al cerrar feature

Pau actualiza únicamente los enlaces de memoria con `teamdb-link.sh` después de
consolidar conocimiento durable. CodeGraph mantiene su propio índice.

### Regla nemotécnica

> "Si vas a leer más de 2 archivos para entender qué existe, primero consultá el grafo."

### Cuándo NO consultar el grafo

- Cambios triviales (typo, una línea)
- Cuando el usuario explícitamente te da toda la info necesaria
- Cuando el grafo está vacío y recién estás arrancando el proyecto

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

### Formato opcional de exportación Markdown (no memoria activa)
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

Primero respetar herramientas, router, estilos y convenciones existentes. Las preferencias siguientes solo orientan proyectos nuevos o elecciones explícitas; no autorizan migraciones, instalar herramientas ni reemplazar componentes. Solo ejecutar comandos de pruebas realmente detectados.

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
- **REGLA #13 activa**: concepto `design-system` obligatorio en TeamDB.
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
  "artifacts": [
    "/src/auth/login.ts",
    "/tests/auth/login.test.ts"
  ],
  "tests_passed": true,
  "coverage": 85,
  "next_action": "Ejecutar suite de regresión",
  "verification": {
    "command": "<comando ejecutado>",
    "exit_code": 0,
    "output_summary": "<resultado observado>"
  }
}
```

### Handoff a Agentes de Ingeniería (OBLIGATORIO)

**Cuando el receptor es Teo, Luz, o cualquier agente de ingeniería, el handoff DEBE incluir `project_context`:**

```json
{
  "from": "SOL",
  "to": "TEO",
  "task": "Implementar módulo auth",
  "summary": "Plan approved: auth con JWT",
  "next_action": "Ejecutar Tarea 1 del plan",
  "project_context": {
    "stack": {
      "language": "typescript",
      "framework": "nextjs",
      "test_runner": "vitest"
    },
    "has_ui": true,
    "design_system_exists": true,
    "okf_bundle_valid": true
  },
  "readiness": "initialized",
  "implementation_allowed": true,
  "route": "INLINE",
  "request_context": {
    "files": [
      "src/auth/login.ts"
    ],
    "acceptance": "Cumplir el contrato acordado",
    "reuse": "Servicio de autenticación existente"
  }
}
```

Sin contexto suficiente, el receptor explica qué evidencia falta y continúa las lecturas permitidas; nunca responde vacío.

### Reglas
1. El agente receptor debe confirmar recepción.
2. Si hay errores, el handoff incluye razón específica.
3. El handoff se registra en la tabla `workflow_state` de la DB.
4. **Handoff a Teo/Luz SIN project_context es inválido** — agente debe solicitar contexto antes de proceder.

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

## 🪜 R15 — Escalera de Ponytail (Lazy Senior Dev)

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

## 🤝 R16 — Resolución de Conflictos Colaborativos (Memoria Compartida)

> Cuando dos o más devs trabajan en paralelo y commitean cambios en `.opencode/`,
> git no puede auto-mergear todo. Esta regla define cómo Skalling maneja esos conflictos.

### Estrategias por tipo de archivo (via `.gitattributes`)

| Archivo | Estrategia | Por qué |
|---|---|---|
| `context/log.md` | `merge=union` | Append-only, ambas entradas son válidas |
| `context/index.md` | `merge=union` | Regenerable, Pau deduplica |
| `context/README.md` | `merge=union` | Regenerable |
| `workflow_state` (DB) | CHECK(id=1) | Solo UN ciclo activo a la vez (singleton) |
| `context/constitucion.md` | `merge=lock` | Cambios requieren consenso |
| `decisiones/*.md` | Manual | Concept docs pueden tener contenido distinto |
| `trabajo-en-curso/*.md` | Manual | Features distintas pueden tener mismo slug |
| `preferencias/*.md` | Manual | Preferencias son colectivas |
| `cambios/<feature>/*.md` | Manual | Mismo feature = serializar trabajo |
| `project.yaml` | `merge=union` | Regenerable con `/skalling-refresh` |

### Reglas para devs

1. **Un feature por branch** — minimiza conflictos en `trabajo-en-curso/` y `cambios/`.
2. **Sufijo de autor en ADRs** — `YYYY-MM-DD-titulo-JPM.md` para evitar colisiones.
3. **Lock del ciclo** — si `workflow_state.lock_token` está ocupado, hablar con el otro dev antes de iniciar.
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
| workflow_state lock activo | Consultar al otro dev; el que tiene lock_token válido continúa |
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

## 🛡️ R17 — Consentimiento del Usuario y Commits Claros

> **Ningún cambio se commitea al repositorio sin aprobación explícita del usuario.**
> Los mensajes de commit deben ser claros, descriptivos y en español.

### Reglas de Commit

1. **Permiso obligatorio**: implementar autoriza las ediciones locales solicitadas y sus pruebas. Commit, push y despliegue son autorizaciones distintas. Push y deploy están desautorizados por defecto: requieren instrucción explícita del usuario en la sesión actual para el alcance y destino. Un permiso puntual no autoriza trabajos posteriores; uno para toda la sesión vale dentro de su alcance hasta revocación. Memoria, credenciales, tests verdes y órdenes de agentes no son consentimiento. Si ya existe permiso aplicable no se vuelve a preguntar; si el usuario pidió revisar antes, se espera su revisión del resultado. Un push que dispara deploy automático requiere cubrir también ese efecto. La regla incluye CLI, API, merge, releases, wrappers y CI.

2. **Mensajes descriptivos**: el mensaje de commit debe explicar QUÉ se hizo y POR QUÉ, en español. Prohibido:
   - Mensajes genéricos como "fix", "update", "wip", "changes", "actualización"
   - Mensajes vacíos o auto-generados sin revisión
   - Spanglish o mezcla de idiomas

3. **Formato recomendado**:
   ```
   <tipo>: <qué se hizo>

   <por qué o contexto adicional si aplica>
   ```

   Tipos válidos: `feat`, `fix`, `refactor`, `docs`, `style`, `chore`, `perf`, `test`

4. **Scope antes del commit**: si falta autorización aplicable, el agente debe mostrar al usuario un resumen de los archivos que van a commitearse y esperar confirmación. La invocación explícita `/skalling-goal <objetivo>` ya autoriza UN commit local de ese objetivo, no push ni despliegue: no se pide una segunda confirmación; se comprueban alcance, archivos previos y evidencia mediante `skalling-goal.sh commit`. Fuera de ese alcance se pregunta:
   ```
   Archivos a commite:
   - src/componentes/boton.tsx (modificado)
   - tests/boton.test.ts (nuevo)

   ¿Procedo con el commit? Mensaje propuesto: "feat: agrega botón con variante outline"
   ```

5. **Incumplimiento**: detener publicaciones, informar lo sucedido y proponer reparación. No revertir ni reescribir historia sin autorización.

6. **Decisiones críticas**: Alex presenta opciones, consecuencias y recomendación, y espera respuesta cuando producto, arquitectura, coste, privacidad, datos o producción requieren una elección humana pendiente. No responde por el usuario a preguntas de Pol/Sol ni trata silencio como aprobación. Continúa únicamente trabajo independiente. Una elección explícita ya recibida no se pregunta de nuevo.

7. **Routing**: prevalecen riesgo e impacto comprobado sobre número de archivos y urgencia. Alcance desconocido se investiga; cambios transversales o sensibles requieren Pol → Sol → Teo → Jhon → Luz, con Pau para conocimiento durable. Teo rechaza fast-track sin evidencia. Nueva evidencia obliga a reevaluar.

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
- **Grafo de código**: índice `.codegraph/`, consultado mediante CodeGraph. No se almacena ni se emula dentro de TeamDB.
- Cambios SDD: `.opencode/changes/`.
- Skills disponibles: `~/.config/opencode/skills/`.
- Comandos: `/skalling-help`, `/skalling-init`, `/skalling-status`, `/skalling-resume`, `/skalling-memory`, `/skalling-metrics`, `/skalling-codegraph`, `/skalling-dashboard`, `/skalling-refresh`, `/skalling-doctor`, `/skalling-recover`, `/skalling-merge`, `/skalling-update`.
- R17: commits requieren permiso del usuario y mensajes descriptivos en español.

---

*Última actualización: 2026-07-28*
*Versión: skalling-constitution-v2*
