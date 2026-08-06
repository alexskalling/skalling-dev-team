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
- [Si frontend] design-system.md en bundle OKF (cumple REGLA #13)

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

### 4.5 — Generar bundle (legacy deshabilitado)

**A partir de v0.7.0, los archivos `.md` del bundle OKF ya NO se crean.** La DB libSQL es la fuente única de verdad.

Si necesitás leer el bundle en formato markdown, exportá desde la DB:

```bash
# Exportar todos los concepts a markdown (one-liner)
sqlite3 .opencode/context/team.db "SELECT body_md FROM concepts" > /tmp/concepts.md

# O usar export estándar:
bash ~/.config/opencode/scripts/teamdb-export.sh .
```

Los archivos legacy (si quedaron de una versión anterior) se preservan en `.opencode/context/legacy/` para referencia histórica.

**Skipping:** NO crear:
- PRODUCT.md
- DESIGN.md
- README.md, index.md, log.md
- design.json, project.yaml
- context/stack/, context/proyecto/, context/decisiones/, etc.

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

### 4.3 — REGLA #13: design-system.md obligatorio si hay UI

Si el stack detectado incluye UI (React, Vue, Svelte, Next.js, Astro, Flutter, React Native, SwiftUI, etc.):

1. Preguntar: *"Detecté stack frontend. R13 exige `design-system.md` en el bundle OKF. ¿Cómo lo creamos?"*
   - A) Con Impeccable: instala el skill y usa `/impeccable init` + `/impeccable document` (requiere Node 22+)
   - B) Template manual (siempre funciona)
   - C) Ya tengo uno, lo copio después

2. **Si A**: El flujo correcto de Impeccable es:
   a. **`npx impeccable install`** — instala el skill de Impeccable en el AI harness
   b. **`/impeccable init`** — escanea el proyecto, hace 2-3 preguntas y crea `PRODUCT.md` (estrategia: plataforma, usuarios, posicionamiento)
      - Al final, Impeccable pregunto si querés correr `/impeccable document`
   c. **Si acepta** → `/impeccable document` escanea colores, tipografía, componentes del proyecto y genera `DESIGN.md` (formato Google Stitch, 6 secciones fijas). Para proyectos sin código todavía, usar `/impeccable document --seed`
   d. Copiar `DESIGN.md` a `.opencode/context/proyecto/design-system.md` (fuente de verdad del proyecto)
   e. Opcional: copiar datos relevantes de `PRODUCT.md` a `.opencode/context/proyecto/que-es.md`
   f. Si install o init fallan (no Node 22+, no hay red) → avisar y fallback a B

3. **Si B** → crear `.opencode/context/proyecto/design-system.md` con estructura mínima según R13.

### 4.4 — Instalar skills stack-specific

Consultá `~/.config/opencode/skills-by-stack.yaml`:

Para cada match:
1. Preguntar UNA sola vez: *"Detecté estas skills para tu stack: [lista]. ¿Las instalo todas, las manejo on-demand, o querés elegir cuáles?"*
2. Si acepta → copiar de `~/.config/opencode/skills/<nombre>/` a `.opencode/skills/<nombre>/`
3. Loggear en `.opencode/context/log.md`

Después de decidir las skills, indexarlas en la DB (indice, no contenido):
```bash
bash "$SK_ROOT/scripts/teamdb-skills-sync.sh" "$(pwd)"
```
Esto puebla `skills_registry` (proyecto) y `skills_active` (global) con la ficha
de cada skill (name/description/version/source/load_path) leída del frontmatter
de `SKILL.md`. Idempotente, se puede re-correr en cualquier momento.

### 4.5 — Buscar skills adicionales con find-skills

Después de instalar las skills stack-specific, ejecutá `/skalling-find-skills` para buscar skills de la comunidad que puedan servir para el stack detectado:

1. Cargá la skill `find-skills` y ejecutá su flujo de descubrimiento
2. Mostrale al usuario las skills encontradas: *"También encontré estas skills de la comunidad que pueden servir para [stack]: [lista]. ¿Querés ver alguna?"*
3. Si elige alguna → instalarla en `.opencode/skills/<nombre>/`
4. Si dice que no → seguir de largo

### 4.6 — Doctor

Correr mentalmente las validaciones:
- Bundle OKF parseable
- project.yaml válido
- Skills referenciadas existen
- Constitución accesible
- Si frontend: design-system.md en bundle OKF

## TeamDB (libSQL)

A partir de v0.7.0, `/skalling-init` también inicializa la DB libSQL del proyecto:

- Crea `.opencode/context/team.db` con schema proyecto
- Activa hooks git (pre-commit export, post-merge import)
- Si hay `.jsonl` legacy, los migra a la DB

Para verificar: `ls .opencode/context/team.db`

### 4.7 — TeamDB (libSQL)

**SIEMPRE** verificar que la DB del proyecto existe, sin importar el estado (A/B/C):

```bash
# Resolver la raíz de instalación (funciona en repo y en global ~/.config/opencode)
SK_ROOT="${SKALLING_ROOT:-}"
if [ -z "$SK_ROOT" ] || [ ! -f "$SK_ROOT/scripts/teamdb-init.sh" ]; then
  [ -f "$HOME/.config/opencode/scripts/teamdb-init.sh" ] && SK_ROOT="$HOME/.config/opencode"
fi
if [ -z "$SK_ROOT" ] || [ ! -f "$SK_ROOT/scripts/teamdb-init.sh" ]; then
  echo "WARN: teamdb-init.sh no encontrado (ni repo ni ~/.config/opencode)" >&2
fi

# Verificar si team.db existe
if [ ! -f ".opencode/context/team.db" ]; then
  echo "team.db no existe. Creando..."
  bash "$SK_ROOT/scripts/teamdb-init.sh" .
  
  # Si hay .jsonl legacy, migrar
  if [ -f ".opencode/context/DECISIONS.jsonl" ] || [ -d ".opencode/context/concept" ]; then
    bash "$SK_ROOT/scripts/teamdb-migrate.sh" .
  fi
fi

# Migrar y verificar schema (idempotente y NO destructivo: teamdb-init.sh aplica
# las migrations 002/003/004/005/006 y valida version 0.7.6. NUNCA borrar la DB.)
bash "$SK_ROOT/scripts/teamdb-init.sh" .

# Auto-enlazar el grafo de memoria (related por categoría/tag, uses módulo->stack).
# Idempotente: si ya hay links, no duplica. Se puede re-correr con /skalling-graph.
bash "$SK_ROOT/scripts/teamdb-link.sh" . 2>/dev/null || true

# Activar hooks git (el installer los deja en $SK_ROOT/hooks; en el repo viven en scripts/hooks)
if [ -d ".git" ]; then
  HOOKS_SRC="$SK_ROOT/hooks"
  [ -d "$HOOKS_SRC" ] || HOOKS_SRC="$SK_ROOT/scripts/hooks"
  cp "$HOOKS_SRC/pre-commit" .git/hooks/pre-commit 2>/dev/null
  cp "$HOOKS_SRC/post-merge" .git/hooks/post-merge 2>/dev/null
  chmod +x .git/hooks/pre-commit .git/hooks/post-merge 2>/dev/null
fi

# Reportar
echo "TeamDB:"
echo "  - DB: .opencode/context/team.db"
echo "  - Schema: $(sqlite3 .opencode/context/team.db 'SELECT value FROM schema_meta WHERE key="version"')"
echo "  - Conceptos: $(sqlite3 .opencode/context/team.db 'SELECT COUNT(*) FROM concepts')"
echo "  - Decisiones: $(sqlite3 .opencode/context/team.db 'SELECT COUNT(*) FROM decisions')"
echo "  - Hooks: $([ -f .git/hooks/pre-commit ] && echo 'pre-commit OK' || echo 'pre-commit NO')"
```

**Si team.db no se puede crear** (no hay sqlite3 o falla), avisar al usuario pero no abortar el init.

### 4.8 — Poblar teamdb con estado inicial

Después de crear la DB, poblar con los datos detectados del proyecto:

```bash
DB=".opencode/context/team.db"
TS=$(date +%Y-%m-%dT%H:%M:%SZ)

# 1. Stack como concept (si no existe)
sqlite3 "$DB" "INSERT OR IGNORE INTO concepts (slug, title, body_md, category, updated_at) VALUES (
  '$(cat project.yaml | yq -r '.language' 2>/dev/null | tr ' ' '-' || echo "stack")',
  'Stack detectado',
  '# Stack\n\n' || char(10) || 'Lenguaje: ' || char(10) || 'Framework: ...',
  'stack',
  '$TS'
)" 2>/dev/null || true

# 2. Módulos como concepts (uno por carpeta top-level)
for module in app componentes lib tipos tests public docs; do
  [ -d "$module" ] || continue
  sqlite3 "$DB" "INSERT OR IGNORE INTO concepts (slug, title, body_md, category, updated_at) VALUES (
    'modulo-$module',
    'Módulo $module',
    'Directorio del módulo $module del proyecto',
    'modulo',
    '$TS'
  )" 2>/dev/null
done

# 3. Reglas del proyecto como preferences
sqlite3 "$DB" "INSERT OR IGNORE INTO preferences (slug, scope, body_md, source, confidence) VALUES (
  'tdd-obligatorio',
  'workflow',
  'TDD: escribir test antes que código (RED → GREEN → REFACTOR)',
  'project.yaml',
  1.0
)"

sqlite3 "$DB" "INSERT OR IGNORE INTO preferences (slug, scope, body_md, source, confidence) VALUES (
  'nombres-espanol',
  'code-style',
  'Variables, funciones, archivos en español (excepto APIs públicas)',
  'project.yaml',
  1.0
)"

sqlite3 "$DB" "INSERT OR IGNORE INTO preferences (slug, scope, body_md, source, confidence) VALUES (
  'test-coversor',
  'tooling',
  'Hay un typo conocido: el script se llama test:coversor (debería ser test:coverage). Workaround: usar directamente vitest run --coverage',
  'consolidado',
  0.8
)"

# 4. ADR base si no existe (memory_links no requiere esto, solo lo dejo de ejemplo)
sqlite3 "$DB" "INSERT OR IGNORE INTO decisions (slug, title, body_md, status, decided_at, decided_by) VALUES (
  'adr-001',
  'Spec-Driven Development',
  'Toda feature sigue: Pol → Sol → Teo ↔ Jhon → Luz → Pau',
  'accepted',
  '$TS',
  'pau'
)"

# 5. Reportar cuántos concepts/decisions se insertaron
echo ""
echo "Datos insertados en teamdb:"
echo "  Concepts: $(sqlite3 $DB 'SELECT COUNT(*) FROM concepts')"
echo "  Decisiones: $(sqlite3 $DB 'SELECT COUNT(*) FROM decisions')"
echo "  Preferencias: $(sqlite3 $DB 'SELECT COUNT(*) FROM preferences')"
```

**NO abortar si falla** — la DB debe seguir funcionando aunque yq no exista.

## Paso 5 — Resumen final

```
Bootstrap completo:
✓ Bundle OKF creado con [N] concept docs
✓ project.yaml con stack [X]
✓ Skills instaladas: [lista]
✓ Skills comunitarias revisadas: [encontradas | no encontradas]
✓ [Si frontend] design-system.md: [creado | pendiente manual]
✓ Doctor: [OK | warnings: ...]
✓ TeamDB: [inicializado | regenerado | ya existe]

Estado del teamdb:
- DB: .opencode/context/team.db
- Schema: v0.7.2
- Conceptos: [N]
- Decisiones: [N]
- Hooks git: [activos | no aplica]

Skalling está listo. ¿Qué necesitás?
```
