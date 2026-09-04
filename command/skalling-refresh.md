---
description: Vuelve a detectar el stack y actualiza el contexto generado con confirmación.
---

# Skalling Refresh

Primero detecta sin escribir:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/bootstrap-context.sh" --target "$(pwd)" --only-detection
```

Compara esa salida con el contexto actual. Solo tras confirmación del usuario,
actualiza los archivos generados:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/bootstrap-context.sh" --target "$(pwd)" --force
```

TeamDB no se elimina. Informa exactamente qué cambió y conserva cualquier backup
creado por el bootstrap.
