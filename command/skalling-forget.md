---
description: Revisa y consolida hallazgos del bundle OKF con decisiones supervisadas y trazables.
---

# Skalling Forget

Revisar y consolidar memoria obsoleta sin aplicar cambios automáticos.

## Flujo obligatorio

### PASO 1 — Ejecutar mem-review primero

Antes de presentar o modificar cualquier candidato, ejecutar:

```bash
bash scripts/mem-review.sh --target "$(pwd)" --dry-run
```

Mostrar el resultado completo al usuario en este orden:

1. Duplicados
2. WIP zombie (>30 días)
3. Stale (>6 meses sin referencia)
4. Superseded

Aunque una categoría no tenga hallazgos, mostrar su encabezado vacío.

### PASO 2 — Decidir por cada hallazgo

Presentar cada path individualmente. No decidir categorías en bloque:

```text
A) Archivar (mover a .opencode/context/archive/)
B) Marcar como superseded (agregar superseded: true y superseded_by: <otro>)
C) Consolidar con otro doc (combinar contenido y eliminar el duplicado)
D) Mantener (ignorar el hallazgo)
```

Solicitar confirmación explícita antes de A, B o C. Preferir archivar sobre eliminar. Para B, solicitar y validar el path de `superseded_by`. Para C, mostrar ambos documentos y el contenido consolidado antes de reemplazar o eliminar.

### PASO 3 — Aplicar y registrar

Después de cada decisión, appendar una línea a `.opencode/context/log.md`:

```text
[YYYY-MM-DD] forget action: A on path1.md
```

Reemplazar fecha, letra y path por la decisión real. También registrar D para mantener trazabilidad.

### PASO 4 — Validar

Ejecutar:

```bash
bash setup-team-doctor.sh --strict
```

Si el doctor detecta errores o warnings, advertir al usuario y cerrar con estado condicional: no declarar una consolidación sana hasta resolverlos o hasta que el usuario acepte mantenerlos.

## Protecciones

- Nunca borrar la constitución.
- Nunca borrar `index.md`, `README.md` ni `log.md`.
- Nunca tocar `.opencode/changes/`, `docs/` ni `.opencode/state/`.
- Nunca modificar un candidato sin confirmación individual.
- Preferir archivar sobre borrar porque la historia es valiosa.

## TeamDB

Al olvidar conceptos viejos, también purgá la DB:

```bash
# Ver qué hay en la DB
sqlite3 .opencode/context/team.db "SELECT slug, updated_at FROM concepts ORDER BY updated_at"

# Borrar concepts viejos (no usados en el último año)
sqlite3 .opencode/context/team.db "DELETE FROM concepts WHERE updated_at < datetime('now', '-1 year')"

# Borrar decisions superseded
sqlite3 .opencode/context/team.db "DELETE FROM decisions WHERE status='superseded'"
```

Luego exportá para que el git ignore no se queje:
```bash
bash scripts/teamdb-export.sh .
```
