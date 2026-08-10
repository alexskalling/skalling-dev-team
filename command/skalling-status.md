---
description: Show current Skalling state for this project — bundle OKF, work in progress, stack, recent changes.
---

# Skalling Status

Muestra el estado actual de Skalling en este proyecto.

## Qué reportar

### 1. Conteo del bundle OKF (desde DB)

```bash
DB=".opencode/context/team.db"
if [ -f "$DB" ]; then
    echo "Concept docs por tipo:"
    for type in concept decision preference known_problem work_in_progress; do
        count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM $type" 2>/dev/null || echo 0)
        echo "  ${type}: $count"
    done
    echo ""
    echo "Total concepts: $(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts" 2>/dev/null || echo 0)"
else
    echo "  (team.db no existe — correr /skalling-init)"
fi
```

### 2. Trabajo en curso (desde DB)

```bash
DB=".opencode/context/team.db"
if [ -f "$DB" ]; then
    sqlite3 "$DB" "SELECT slug, type, title, status, owner FROM work_in_progress ORDER BY updated_at DESC LIMIT 20" 2>/dev/null
fi
```

### 3. Cambios SDD activos (desde DB)

```bash
DB=".opencode/context/team.db"
if [ -f "$DB" ]; then
    sqlite3 "$DB" "SELECT p.slug, p.title, p.status, p.agent, pr.title as plan_title, pr.status as plan_status FROM proposals p LEFT JOIN plans pr ON pr.proposal_id = p.id WHERE p.status IN ('draft','active','in_review') ORDER BY p.updated_at DESC LIMIT 20" 2>/dev/null
fi
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

### 6. Frontend check (REGLA #13) — desde DB

```bash
DB=".opencode/context/team.db"
if [ -f "$DB" ] && grep -q "has_ui: true" .opencode/project.yaml 2>/dev/null; then
    ds_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM concepts WHERE slug='design-system' AND category='design-system'" 2>/dev/null || echo 0)
    if [ "$ds_count" -gt 0 ]; then
        echo "  ✓ design-system en DB (REGLA #13 OK)"
    else
        echo "  ⚠ REGLA #13 violada: falta design-system en concepts table"
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
