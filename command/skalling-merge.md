---
description: Diagnostica conflictos de Git relacionados con la memoria de Skalling.
---

# Skalling Merge

Ejecuta el asistente canónico:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/merge-helper.sh" --target "$(pwd)"
```

No resuelvas conflictos automáticamente. Explica cada archivo afectado y propón
una resolución concreta; aplica cambios solo cuando el usuario lo autorice.
