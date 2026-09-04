---
description: Recupera el contexto mínimo para continuar el trabajo activo.
---

# Skalling Resume

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/teamdb-resume.sh" "$(pwd)"
```

Devuelve un resumen pequeño y accionable: objetivo, estado, bloqueos y siguiente
paso. Si no hay trabajo activo, indícalo sin crear planes ni archivos.
