---
description: Show current Skalling state for this project — bundle OKF, work in progress, stack, recent changes.
---

# Skalling Status

Muestra el estado actual de Skalling en este proyecto.

## Qué reportar

### 1. Conteo del bundle OKF

```bash
echo "Concept docs por tipo:"
for type in Concept Decision Preference Workaround WorkInProgress Context; do
    count=$(find .opencode/context -name "*.md" -not -name "index.md" -not -name "log.md" -not -name "README.md" -exec grep -l "^type: $type" {} \; 2>/dev/null | wc -l | tr -d ' ')
    echo "  $type: $count"
done

echo ""
echo "Total concept docs: $(find .opencode/context -name "*.md" -not -name "index.md" -not -name "log.md" -not -name "README.md" | wc -l | tr -d ' ')"
```

### 2. Trabajo en curso

```bash
ls .opencode/context/trabajo-en-curso/*.md 2>/dev/null | grep -v index.md
```

### 3. Cambios SDD activos

```bash
find .opencode/changes -name "proposal.md" 2>/dev/null | head -10
```

### 4. Stack detectado

```bash
if [ -f .opencode/project.yaml ]; then
    grep -E "^  (language|framework|runtime|test_runner|package_manager):" .opencode/project.yaml
fi
```

### 5. Últimas entradas del log

```bash
tail -30 .opencode/context/log.md
```

### 6. Frontend check (REGLA #13)

```bash
if grep -q "has_ui: true" .opencode/project.yaml 2>/dev/null; then
    if [ -f .opencode/context/proyecto/design-system.md ]; then
        echo "  ✓ design-system.md presente"
    else
        echo "  ⚠ REGLA #13 violada: falta design-system.md en bundle OKF"
    fi
fi
```

### 7. Health check rápido

```bash
bash ~/.config/opencode/command/../setup-team-doctor.sh 2>&1 | tail -10 || \
bash setup-team-doctor.sh 2>&1 | tail -10
```

## Formato de salida

Presentá los resultados en este formato, una sección a la vez:

```
📊 Skalling Status

📁 Bundle OKF
   Concept: [N]
   Decision: [N]
   Preference: [N]
   Workaround: [N]
   WorkInProgress: [N]
   Context: [N]
   Total: [N]

🚀 Trabajo en curso
   - [feature-1.md] — [título]
   - [feature-2.md] — [título]

📐 Cambios SDD activos
   - [feature-slug] — [estado]

⚙️  Stack detectado
   Lenguaje: [X]
   Framework: [Y]
   Runtime: [Z]
   Test runner: [T]

🎨 Frontend (REGLA #13)
   [✓ design-system.md presente | ⚠ falta]

📋 Últimas 5 entradas del log
   [fecha] — [acción]
   ...

🏥 Health check
   [OK | warnings | errors]
```

## Si algo está mal

Si detectás errores o warnings:
1. Sugerí correr `/skalling-doctor` para detalle completo.
2. Si el bundle OKF está vacío, sugerí `/skalling-init` o `/skalling-refresh`.
3. Si design-system.md falta en frontend, sugerí crearlo con `/impeccable document`

## TeamDB

El estado del proyecto incluye la DB libSQL:

- `team.db` presente en `.opencode/context/`
- Conteos: `sqlite3 .opencode/context/team.db "SELECT COUNT(*) FROM concepts"`
- Jerarquía WIP: `bash scripts/wip-tree.sh .`
