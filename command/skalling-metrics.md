---
description: Muestra mediciones reales de tiempo, rutas, agentes, permisos y contexto.
---

# Skalling Metrics

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/skalling-metrics.sh" report "$(pwd)"
```

Resume únicamente los datos existentes. Si todavía no hay muestras, dilo con
claridad; no calcules porcentajes ni ahorros hipotéticos.
