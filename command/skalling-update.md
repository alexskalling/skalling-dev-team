---
description: Comprueba y aplica actualizaciones de Skalling con confirmación y backup.
---

# Skalling Update

Para comprobar sin cambiar nada:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/update.sh" --check-only
```

Si hay una versión nueva, muestra los commits y el changelog. Solo después de la
confirmación del usuario, ejecuta `bash "$SK_ROOT/scripts/update.sh"`. El
actualizador debe conservar el backup automático del instalador.
