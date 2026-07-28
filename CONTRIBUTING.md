# Contributing to Skalling

## Conventional Commits

Todos los commits deben seguir [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional-scope>): <description>
```

### Tipos permitidos

| Tipo | Cuándo | Ejemplo |
|---|---|---|
| `feat` | Nueva feature | `feat: agregar comando /skalling-forget` |
| `fix` | Bug fix | `fix: bash 3 compatibility en bootstrap-context.sh` |
| `docs` | Solo documentación | `docs: actualizar README con quickstart` |
| `refactor` | Cambio de código sin feature | `refactor: simplificar detección de stack` |
| `chore` | Mantenimiento | `chore: bump versión a 0.2.0` |
| `test` | Agregar o modificar tests | `test: agregar e2e de bootstrap` |
| `build` | Build system | `build: agregar CI workflow` |
| `ci` | CI config | `ci: correr tests en push` |
| `style` | Formatting | `style: shfmt en scripts` |
| `perf` | Performance | `perf: cachear detección de manifest files` |

### Breaking changes

Marcar con `!` después del scope:

```
feat!: cambiar a OKF v0.2 schema
```

## Reglas de PR

- **Budget**: 400 líneas (`additions + deletions`). Si excede, dividir.
- **Un `type:` label** en el PR (un solo `feat`, `fix`, etc.).
- **Tests pasan**: `bash tests/setup.test.sh` debe dar 0 errors.
- **Doctor pasa**: `bash setup-team-doctor.sh --strict` debe dar 0 errors.

## Cómo agregar un agente

1. Crear `agents-base/NuevoAgente.md` con frontmatter:

```yaml
---
description: [Una línea clara de qué hace]
mode: subagent
permission:
  edit: [allow | ask | deny]
  bash: [allow | ask | deny | glob-pattern]
---
```

2. Definir su rol, fase en el ciclo, y handoff format.
3. Agregar el agente a `agents-base/` (convención: nombre sin sufijo).
4. Actualizar la constitución si cambia el ciclo.
5. Agregar a `tests/setup.test.sh` en `expected=(...)`.
6. Actualizar README con el nuevo agente.

## Cómo agregar una skill

Si es **propia de Skalling** (prefijo `skalling-*`):

1. Crear `skills-base/skalling-nombre/SKILL.md` con frontmatter:

```yaml
---
name: skalling-nombre
description: [Qué hace y cuándo activarla, con trigger explícito]
---
```

2. Documentar protocolo, ejemplos, anti-patrones.
3. Si reemplaza una upstream, marcar la upstream como deprecated.

Si es **upstream**:

- Dejar con su nombre original.
- Documentar en `data/skills-by-stack.yaml` cuándo se recomienda.

## Cómo agregar un comando `/skalling-*`

1. Crear `command/skalling-nombre.md` con frontmatter:

```yaml
---
description: [Una línea]
---
```

2. Documentar el protocolo, los pasos, las opciones de scope.
3. Actualizar `setup-team-doctor.sh` si querés que valide el comando.
4. Actualizar README con el nuevo comando.

## Cómo agregar un detector de stack

1. Editar `data/stack-detectors.yaml`.
2. Agregar entry en `detectors:` con el formato:

```yaml
- id: mi-stack
  files: [mi-manifest.ext]
  language: ruby
  framework:
    - pattern: 'rails'
      value: rails
  test_runner:
    - default: minitest
```

3. Si querés que sea custom del usuario, agregar en `custom:`.

## Estilo de código

### Bash

- `set -euo pipefail` al inicio de cada script.
- `#!/usr/bin/env bash` shebang.
- Comentar **solo** cuando es no obvio. El código se explica solo.
- Nombres de variables en español (consistente con el resto del proyecto).
- Sin `declare -A` (arrays asociativos no existen en bash 3.2 de macOS).
- Usar `local` en funciones.
- Pipeline failures: usar `{ cmd || true; }` o `cmd || true` para evitar que `pipefail` mate el script.

### Markdown

- Títulos: `#` para h1, `##` para h2, `###` para h3 (jerarquía respetada).
- Listas: `-` para bullets (no `*` ni números, salvo cuando el orden importa).
- Code blocks: usar lenguaje (`\`\`\`bash`, `\`\`\`yaml`, `\`\`\`typescript`).
- Frontmatter YAML en archivos de skill/comando/agente (entre `---`).

### YAML

- 2 spaces de indent.
- Sin tabs.
- Comentarios cuando aclaran, no cuando redundan.

## Pre-commit checks

Antes de hacer commit, corré:

```bash
bash tests/setup.test.sh
bash -n install-global.sh setup.sh setup-team-doctor.sh bootstrap-context.sh
```

Si todo pasa, podés commitear.

## Proceso de release

1. Merge a main.
2. Tag con semver: `git tag -a v0.2.0 -m "Release 0.2.0"`.
3. Push tags: `git push --tags`.
4. Update CHANGELOG.md.

## Filosofía

> "El código más corto que funciona."

Inspirado en [ponytail](https://github.com/DietrichGebert/ponytail) — lazy about solution, never about reading.

> "Memoria estándar abierto, no silos privados."

Inspirado en [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf) — formato portable.

## Código de conducta

Sé amable. Sé claro. Sé honesto. Es un proyecto chico, no necesitamos reglas formales — solo sentido común.
