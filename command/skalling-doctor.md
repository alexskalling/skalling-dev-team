---
description: Run health check on Skalling installation. Validates bash, opencode, agents, skills, constitution, project structure and OKF memory.
---

# Skalling Doctor

Wrapper de `setup-team-doctor.sh` para validar la instalación global, el proyecto y la salud del bundle OKF.

## Uso

```bash
bash <path-to>/setup-team-doctor.sh --global-only
bash <path-to>/setup-team-doctor.sh --project "$(pwd)"
bash <path-to>/setup-team-doctor.sh --strict --project "$(pwd)"
```

## Interpretación

- Exit `0` sin warnings: instalación saludable.
- Exit `0` con warnings: findings no bloqueantes cuando no se usa `--strict`.
- Exit `1`: errores, o warnings bajo `--strict`.

## Salida

| Categoría | Estado |
|---|---|
| Ambiente | ✓ OK / ⚠ warning / ✗ error |
| Instalación global | ... |
| Instalación per-project | ... |
| Frontmatter | ... |
| Skills | ... |
| Constitución | ... |
| Templates | ... |
| REGLA #13 (design-system.md) | ... |
| Memoria (bundle OKF) | huérfanos / WIP zombie / stale / superseded / duplicados |

## Acciones sugeridas para memoria

- **Concept docs huérfanos:** agregar la referencia correcta a un `index.md` o revisar el documento con `/skalling-forget`.
- **Trabajo-en-curso zombie:** archivar o consolidar el WIP de más de 30 días con `/skalling-forget`.
- **Concept docs stale:** revisar vigencia de documentos no referenciados durante más de 6 meses.
- **Concept docs superseded:** quitar del `index.md` vigente y archivar cuando corresponda.
- **Duplicados por título:** consolidar los documentos; se reportan como error.

## Otros findings frecuentes

- Falta constitución: ejecutar `install-global.sh`.
- Frontmatter inválido: corregir delimitadores YAML del agente.
- REGLA #13 violada: crear `.opencode/context/proyecto/design-system.md`.
- Instalación parcial: reinstalar agentes, skills, comandos o templates faltantes.
