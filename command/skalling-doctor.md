---
description: Run health check on Skalling installation. Validates bash, opencode, agents, skills, constitution, project structure.
---

# Skalling Doctor

Wrapper del comando shell `setup-team-doctor.sh`. Corre validación completa de la instalación de Skalling.

## Cuándo usar

- Después de instalar Skalling.
- Después de actualizar.
- Si algo no funciona y querés diagnosticar.
- Periódicamente (semanalmente) como health check.

## Pasos

### 1. Localizar el script

Buscar `setup-team-doctor.sh` en:
- `skalling-dev-team/setup-team-doctor.sh` (si Skalling vive en un subdirectorio del proyecto).
- `~/.config/opencode/setup-team-doctor.sh` (si se instaló global).
- Cualquier path donde el usuario haya clonado el repo.

### 2. Ofrecer opciones de scope

Preguntar al usuario (opcional, depende del contexto):

```
¿Qué scope querés chequear?

A) Solo instalación global (~/.config/opencode/)
B) Global + este proyecto
C) Solo este proyecto
```

Default: **B** (lo más útil).

### 3. Ejecutar

```bash
# Solo global
bash <path-to>/setup-team-doctor.sh --global-only

# Global + proyecto
bash <path-to>/setup-team-doctor.sh --project "$(pwd)"

# Modo strict (warnings como errors)
bash <path-to>/setup-team-doctor.sh --strict
```

### 4. Interpretar resultado

- **Exit 0 + 0 errors + 0 warnings**: todo OK.
- **Exit 0 + warnings**: issues menores, revisar pero no bloquea.
- **Exit 1 + errors**: problemas críticos, requiere acción.

Errores comunes:
- `bash >= 4 requerido` → sugiere upgrade o usar bash explícito.
- `Falta constitución` → sugiere correr `install-global.sh`.
- `Frontmatter no abre/cierra con ---` → bug en algún agente.
- `REGLA #13 violada` → falta `docs/design/DESIGN.md` en proyecto frontend.
- `Esperados 8 agentes, encontré N` → instalación parcial.

### 5. Sugerir acciones

Por cada error, dar un paso concreto:

```
Errores detectados:

✗ Frontmatter no abre con --- en alexa.md
  → Solución: ese archivo es de una instalación previa. Borrar o renombrar.

✗ Frontend detectado pero falta docs/design/DESIGN.md (REGLA #13)
  → Solución: correr /impeccable document o crear manualmente desde template.

⚠ Bash 3.2 detectado (recomendado >= 4)
  → Solución: bash 3.2 funciona pero algunas features avanzadas no.
```

## Salida

Resumí los findings en una tabla simple:

| Categoría | Estado |
|---|---|
| Ambiente | ✓ OK / ⚠ warning / ✗ error |
| Instalación global | ... |
| Instalación per-project | ... |
| Frontmatter | ... |
| Skills | ... |
| Constitución | ... |
| Templates | ... |
| REGLA #13 (frontend) | ... |

## Exit codes

- `0` → todo OK (o solo warnings si `--strict` no se usó).
- `1` → errors detectados.
