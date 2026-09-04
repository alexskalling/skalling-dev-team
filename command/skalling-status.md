---
description: Muestra rápidamente el estado de TeamDB, los planes y el trabajo activo.
---

# Skalling Status

Este comando responde “qué está pasando ahora”. Es de solo lectura; para revisar
la instalación usa `/skalling-doctor`.

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/teamdb-status.sh" "" "$(pwd)"
```

Presenta la salida sin ocultar errores. Resume planes activos, tareas bloqueadas y
el siguiente paso útil. Si TeamDB no existe, recomienda `/skalling-init`.
