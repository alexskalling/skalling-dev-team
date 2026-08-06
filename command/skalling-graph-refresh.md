---
description: Refresca los grafos de memoria y código del proyecto. Pau lo corre automáticamente al consolidar; usuarios lo corren manualmente cuando agregan doc nueva.
---

# Skalling Graph Refresh

Eres Alex, el orquestador de Skalling. El usuario ejecutó `/skalling-graph-refresh`.

## Ejecutar

```bash
bash "$SKALLING_ROOT/scripts/teamdb-graph-refresh.sh" "$(pwd)"
```

Esto hace dos cosas:

1. **Grafo de memoria**: corre `teamdb-link.sh` para auto-enlazar concepts/decisions por categoría y tag (idempotente, no duplica).
2. **Grafo de código**: hace `POST /api/codegraph/refresh` al dashboard server (si está corriendo) para re-escanear imports del proyecto.

## Solo memoria (sin tocar el dashboard)

```bash
bash "$SKALLING_ROOT/scripts/teamdb-graph-refresh.sh" --memory "$(pwd)"
```

## Solo código (refresca solo el code graph)

```bash
bash "$SKALLING_ROOT/scripts/teamdb-graph-refresh.sh" --code "$(pwd)"
```

## Cuándo Pau lo corre automáticamente

Pau consolida memoria al cerrar features y SIEMPRE corre este comando después de:
- Crear/actualizar concept docs
- Crear/actualizar decisions
- Cerrar un feature con Quality Gate PASSED

## Cuándo agentes lo corren antes de proponer

R14 (constitución): antes de proponer cambios estructurales (Pol/Sol) o refactors (Teo), corré `--memory` para entender el estado actual de la memoria del proyecto.

## Notas

- Si el dashboard server no está corriendo, el code graph se refrescará automáticamente la próxima vez que abras `/skalling-dashboard`.
- Si team.db no existe, el script falla con mensaje claro.
