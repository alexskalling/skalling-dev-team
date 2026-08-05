---
description: Re-detect stack of current project and update project.yaml + bundle OKF. Does NOT delete existing memory.
---

# Skalling Refresh

Re-detecta el stack del proyecto y actualiza `project.yaml` + concept docs en `.opencode/context/stack/`.

**NO borra** memoria existente (decisiones, trabajo-en-curso, etc.). Solo actualiza lo auto-detectable.

## Cuándo usar

- Cambiaste de framework o agregaste una dependencia mayor.
- Creaste un nuevo módulo con stack distinto.
- Después de varios meses, el bundle tiene info desactualizada.
- Después de correr `/skalling-init` y querer verificar lo más reciente.

## Pasos

### 1. Ejecutar bootstrap con flag de refresh

```bash
bash skalling-dev-team/bootstrap-context.sh --only-detection
```

Mostrame el output al usuario.

### 2. Confirmar cambios

Compará lo detectado vs lo actual:

```
Stack actual:           Stack detectado:
  language: typescript    language: typescript (igual)
  framework: react        framework: nextjs (¡cambió!)
  test_runner: vitest     test_runner: vitest (igual)
```

### 3. Aplicar cambios

Si hay diferencias, correr bootstrap con `--force` para sobrescribir `project.yaml` y los concept docs de stack:

```bash
bash skalling-dev-team/bootstrap-context.sh --force
```

### 4. Validar

Correr doctor para confirmar que nada se rompió:

```bash
bash skalling-dev-team/setup-team-doctor.sh
```

## Lo que NO hace

- **No borra** decisiones, workarounds, trabajo-en-curso.
- **No borra** concept docs existentes (solo actualiza `stack/*.md` y `project.yaml`).
- **No toca** `.opencode/changes/` (los cambios SDD son tuyos).
- **No toca** `docs/` (la documentación pública es tu responsabilidad).

## Cuándo NO usar

- Si querés regenerar desde cero → usá `/skalling-init` con la opción de regenerar.
- Si querés purgar memoria obsoleta → usá `/skalling-forget`.
- Si querés ver el estado actual → usá `/skalling-status`.

## TeamDB

Refresh re-detecta stack. La DB permanece igual (no se borra), pero se actualiza `stack_cache` en la DB global:

```bash
sqlite3 ~/.config/opencode/team.db "INSERT OR REPLACE INTO stack_cache (project_path, detected_at, language, framework) VALUES ('$(pwd)', datetime('now'), 'LANG', 'FRAMEWORK')"
```

Si la DB proyecto cambió de schema, recreala:
```bash
rm .opencode/context/team.db
bash scripts/teamdb-init.sh .
bash scripts/teamdb-migrate.sh .
```
