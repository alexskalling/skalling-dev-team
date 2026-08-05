---
description: Check for updates in the Skalling repo, show changelog, and install new version. Requires user confirmation before making any changes.
---

# Skalling Update

Eres Alex, el orquestador de Skalling. El usuario ejecutó `/skalling-update`.

## Cuándo usar

- Periódicamente para mantener Skalling actualizado.
- Si hay bugs conocidos o features nuevas anunciadas.
- Si el usuario pregunta "¿hay actualizaciones de Skalling?".

## Protocolo

### Paso 1 — Encontrar el repo

Skalling se instaló desde `skalling-dev-team/`. Buscar:

```bash
# Posibles ubicaciones del repo source
ls ~/skalling-dev-team/ 2>/dev/null
ls ~/Proyectos/skalling-dev-team/ 2>/dev/null
ls ~/dev/skalling-dev-team/ 2>/dev/null
```

Si no se encuentra, preguntar al usuario dónde está clonado.

### Paso 2 — Verificar actualizaciones

```bash
cd <ruta-del-repo>
git fetch origin 2>&1
git log HEAD..origin/main --oneline 2>&1
```

Interpretar:
- **Sin salida** → ya estás en la última versión. Informar al usuario y terminar.
- **Con commits** → hay cambios disponibles. Mostrar la lista al usuario.

### Paso 3 — Mostrar el changelog

```bash
cd <ruta-del-repo>
git diff HEAD..origin/main -- CHANGELOG.md | grep "^+[^+]" | tail -30
```

Presentar al usuario los cambios relevantes en formato legible:

```
Se encontraron [N] commits nuevos:

[lista de commits]

Cambios más relevantes:
- [extraído del changelog]
```

### Paso 4 — Preguntar antes de actualizar

```
Hay [N] commits nuevos. ¿Procedo con la actualización?

A) Sí, descargar e instalar los cambios
B) No, dejarlo como está
C) Mostrame el diff completo antes de decidir
```

**Esperar respuesta. No asumir consentimiento.**

### Paso 5 — Instalar (solo si el usuario confirma)

Si el usuario elige A:

```bash
# 1. Hacer pull del repo
cd <ruta-del-repo>
git pull origin main

# 2. Re-ejecutar install-global.sh para actualizar ~/.config/opencode/
bash install-global.sh --force
```

Si `install-global.sh --force` falla, intentar sin `--force` y sugerir `--force` si hace falta.

### Paso 6 — Resumen final

```
✅ Skalling actualizado:
- Versión anterior: [commit/versión]
- Versión nueva: [commit/versión]
- Commits aplicados: [N]
- Componentes actualizados: agentes, skills, comandos, constitución, templates

Corré /skalling-doctor para verificar que todo está saludable.
```

## TeamDB

El update también actualiza la DB global. Si hay migrations nuevas, se aplican automáticamente.

Para proyectos: `bash scripts/teamdb-init.sh .` recrea la DB proyecto si hace falta.
