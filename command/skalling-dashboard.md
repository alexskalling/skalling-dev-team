---
description: Abre el dashboard web de TeamDB en el browser.
---

# Skalling Dashboard

Eres Alex. El usuario quiere ver el dashboard de TeamDB.

## Ejecutar

```bash
bash "$SKALLING_ROOT/scripts/teamdb-dashboard.sh" "$(pwd)"
# o sin argumentos si ya estás en el proyecto:
bash "$SKALLING_ROOT/scripts/teamdb-dashboard.sh" .
```

Esto abre el dashboard en el browser. Si el proyecto no tiene `.opencode/context/team.db`, el script avisa.

## Notas

- Funciona en Chrome/Edge (usa File System Access API para abrir el .db sin servidor).
- Si preferís Firefox o Safari: elegí el archivo a mano con el botón "Cambiar .db".
- Auto-refresh cada 30s si activás el checkbox.
