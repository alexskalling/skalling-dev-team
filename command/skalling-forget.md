---
description: Purge obsolete concept docs from the OKF memory bundle. Identifies stale entries, asks confirmation, archives or deletes.
---

# Skalling Forget

Purgar concept docs obsoletos del bundle OKF. Es el "olvido" de la memoria persistente.

## Cuándo usar

- Después de muchos meses, hay muchos concept docs sin referenciar.
- Decisiones superseded por otras (ya tienen `supersedes:` linkeando a la nueva).
- Concept docs que ya no aplican (feature removida, tecnología migrada, etc.).
- Como parte de mantenimiento semestral.

## Política de olvido (de la constitución)

- Cada 6 meses, Pau revisa entries sin referenciar.
- `supersedes` linkea a versiones anteriores (la vieja queda pero marcada).
- Pau purga duplicados cuando los detecta.

## Pasos

### 1. Identificar candidatos

Buscar concept docs que matcheen estos criterios:

```bash
# 1. Marcados como superseded
grep -l "^supersedes:" .opencode/context/**/*.md 2>/dev/null

# 2. Workarounds con "Cómo removerlo" completo
grep -l "^- \[x\]" .opencode/context/problemas-conocidos/*.md 2>/dev/null

# 3. WorkInProgress con todas las tareas marcadas
# (todos los checkboxes en [x])

# 4. Concept docs sin referenciar en 6+ meses
# (heurística: timestamp anterior a 6 meses)
find .opencode/context -name "*.md" -newer /tmp/6months_ago.txt 2>/dev/null
```

### 2. Presentar al usuario

Por cada candidato, mostrar:

```
Candidato a purga:

📄 .opencode/context/decisiones/2025-01-15-usar-mongodb.md
   Tipo: Decision
   Creado: 2025-01-15 (hace 18 meses)
   Superseded by: 2026-06-20-usar-postgres.md
   Estado: marcado como superseded

A) Archivar (mover a .opencode/context/archive/)
B) Borrar definitivamente
C) Conservar (no purgar)
D) Ver contenido antes de decidir
```

### 3. Aplicar decisión

**A) Archivar**:
```bash
mkdir -p .opencode/context/archive/YYYY-MM/
mv .opencode/context/decisiones/2025-01-15-usar-mongodb.md \
   .opencode/context/archive/2025-01/
```

**B) Borrar**:
```bash
rm .opencode/context/decisiones/2025-01-15-usar-mongodb.md
```

**C) Conservar**: no hacer nada, pasar al siguiente.

### 4. Loggear la purga

Append a `.opencode/context/log.md`:

```markdown
## YYYY-MM-DD HH:MM — Purga de memoria
**Por:** alex (forget)
**Archivados:** [lista]
**Borrados:** [lista]
**Conservados:** [lista]
**Razón:** mantenimiento semestral / superseded / ...
```

### 5. Actualizar índices

Si alguna carpeta queda vacía después de la purga, marcar en su `index.md`:

```markdown
> ⚠ Esta carpeta está vacía. Pau la llenará en próximos bootstraps.
```

### 6. Validar

Correr doctor para confirmar estructura sana:

```bash
bash setup-team-doctor.sh --strict
```

## Advertencias

- **Nunca** borrar concept docs sin confirmación del usuario.
- **Nunca** borrar la constitución (es universal, no es memoria del proyecto).
- **Nunca** borrar `index.md`, `README.md`, `log.md`.
- **Preferir archivar sobre borrar** (la historia es valiosa).

## Lo que NO hace

- No toca `.opencode/changes/` (los SDD son tuyos).
- No toca `docs/` (la doc pública es tuyos).
- No toca `.opencode/state/` (es el estado del workflow, no memoria).
