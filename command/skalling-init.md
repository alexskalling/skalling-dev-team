---
description: Initialize Skalling in current project. Detects stack, creates OKF memory bundle, installs stack-specific skills. Works for any language.
---

# Skalling Init Protocol

Eres Alex, el orquestador de Skalling. El usuario ejecutó `/skalling-init`.

## Paso 1 — Detectar estado del proyecto

Ejecuta estas lecturas en paralelo:

- ¿Existe `.opencode/context/index.md`? → Estado C (ya inicializado)
- ¿Existe `.opencode/` pero sin `context/index.md`? → Estado B (virgen)
- ¿No existe `.opencode/`? → Estado A (nuevo)
- Lee cualquiera de estos archivos para detectar stack:
  - `package.json` (JS/TS)
  - `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile` (Python)
  - `Cargo.toml` (Rust)
  - `go.mod` (Go)
  - `pom.xml`, `build.gradle`, `build.gradle.kts` (JVM)
  - `*.csproj`, `*.sln` (.NET)
  - `Gemfile` (Ruby)
  - `composer.json` (PHP)
  - `mix.exs` (Elixir)
  - `Package.swift` (Swift)
  - `pubspec.yaml` (Dart/Flutter)
  - `deno.json`, `bun.lockb` (Deno/Bun)
- Lee `README.md` si existe → descripción del proyecto
- Lista carpetas top-level → módulos/features

**Si hay múltiples manifests (monorepo)**: detectá cada uno por separado y generá entries en el bundle por cada módulo.

## Paso 2 — Comunicar el estado al usuario

Formato obligatorio:

```
Detecté:
- Lenguaje principal: [X]
- Framework(s): [Y, Z]
- Test runner: [T]
- Linter/formatter: [L]
- Módulos top-level: [lista]
- README: [resumen en 1 línea o "no tiene"]

Estado: [A | B | C]
Acción: voy a [crear bundle OKF | regenerar bundle | mostrar memoria existente]
```

## Paso 3 — Confirmar antes de tocar nada

Una sola pregunta a la vez:

**Caso A** (proyecto nuevo):
```
¿Procedo con el bootstrap? Esto va a crear:
- .opencode/context/ (bundle OKF con stack + proyecto)
- .opencode/project.yaml (config detectada)
- .opencode/skills/ (skills específicas del stack)
- .opencode/changes/ (vacío, listo para SDD)
- [Si frontend] docs/design/DESIGN.md (cumple REGLA #13)

A) Sí, dale
B) Esperá, primero leeme el README y decime qué entendiste
C) No, solo instalá las skills (sin bundle de memoria todavía)
```

**Caso B** (.opencode/ existe pero sin contexto):
```
Ya hay archivos en .opencode/. ¿Cómo procedo?

A) Regenerar bundle desde cero (sobrescribe lo que haya)
B) Conservar archivos existentes, solo agregar lo que falte
C) Mostrame primero qué hay en .opencode/ antes de decidir
```

**Caso C** (ya inicializado):
```
Skalling ya está inicializado en este proyecto. Bundle OKF tiene [N] concept docs.

A) Re-detectar stack (actualizar stack/*.md y project.yaml)
B) Revisar memoria (mostrar index.md)
C) Continuar trabajo (salir del init)
```

## Paso 4 — Bootstrap (si A o B eligió crear)

### 4.1 — Crear bundle OKF

```
.opencode/context/
├── README.md                       # descripción del bundle
├── index.md                        # navegación root
├── log.md                          # timestamp de este bootstrap
├── stack/
│   ├── index.md
│   ├── backend.md                  # type: Concept, stack detectado
│   ├── frontend.md                 # si aplica
│   └── testing.md                  # type: Concept, test runner
├── proyecto/
│   ├── index.md
│   └── que-es.md                   # type: Concept, extraído del README
├── decisiones/                     # vacías con secciones
│   └── index.md
├── trabajo-en-curso/               # vacías
│   └── index.md
├── preferencias/                   # vacías
│   └── index.md
└── problemas-conocidos/            # vacías
    └── index.md
```

Cada archivo con frontmatter OKF:
```yaml
---
type: Concept
title: Backend del proyecto
description: Stack de backend detectado automáticamente
resource: package.json
tags: [stack, backend, typescript]
timestamp: 2026-07-28T15:30:00Z
agent: alex
confidence: 0.7
---
```

### 4.2 — Crear project.yaml

```yaml
schema: skalling-project-v1
detected_at: 2026-07-28T15:30:00Z
detected_by: alex-init
stack:
  language: typescript
  framework: nextjs
  package_manager: npm
  test_runner: vitest
  linter: eslint
  formatter: prettier
modules:
  - src/
  - tests/
  - docs/
strict_tdd: true
testing:
  unit: { available: true, command: "npm test" }
  integration: { available: true, command: "npm run test:integration" }
  e2e: { available: false }
  coverage: { available: true, threshold: 80 }
okf:
  bundle_path: .opencode/context
  schema: okf-v0.1+skalling-extensions
```

### 4.3 — REGLA #13: DESIGN.md obligatorio si hay UI

Si el stack detectado incluye UI (React, Vue, Svelte, Next.js, Astro, Flutter, React Native, SwiftUI, etc.):

1. Preguntar: *"Detecté stack frontend. La constitución (R13) exige `DESIGN.md`. ¿Querés que lo cree ahora con Impeccable, o tenés uno manual?"*
   - A) Sí, corré `npx impeccable document` para auto-generar.
   - B) Lo creo desde el template manual de Skalling.
   - C) Ya tengo uno en otro lado, lo voy a copiar después.

2. Si A → intentar correr `npx impeccable document`. Si falla (sin Node 22+, sin Impeccable), fallback a B.

3. Si B → copiar template de `~/.config/opencode/templates/design/DESIGN.template.md` a `docs/design/DESIGN.md`.

4. Pau crea `design-system.md` en `.opencode/context/proyecto/` linkeando al archivo.

### 4.4 — Instalar skills stack-specific

Consultá `~/.config/opencode/skills-by-stack.yaml`:

Para cada match:
1. Preguntar UNA sola vez: *"Detecté estas skills para tu stack: [lista]. ¿Las instalo todas, las manejo on-demand, o querés elegir cuáles?"*
2. Si acepta → copiar de `~/.config/opencode/skills/<nombre>/` a `.opencode/skills/<nombre>/`
3. Loggear en `.opencode/context/log.md`

### 4.5 — Doctor

Correr mentalmente las validaciones:
- Bundle OKF parseable
- project.yaml válido
- Skills referenciadas existen
- Constitución accesible
- Si frontend: DESIGN.md existe

## Paso 5 — Resumen final

```
Bootstrap completo:
✓ Bundle OKF creado con [N] concept docs
✓ project.yaml con stack [X]
✓ Skills instaladas: [lista]
✓ [Si frontend] DESIGN.md: [creado | pendiente manual]
✓ Doctor: [OK | warnings: ...]

Skalling está listo. ¿Qué necesitás?
```
