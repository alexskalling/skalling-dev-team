---
description: Abre el dashboard local de TeamDB de forma compatible con el sistema.
---

# Skalling Dashboard

Pedido: $ARGUMENTS

Sin argumentos usa `start`. Acepta también `status` (consultar URL sin abrir el
navegador) y `stop` (detener solo este proyecto). Rechaza otras opciones.

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/teamdb-dashboard.sh" <start|status|stop validado> "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

El script encuentra un puerto libre y abre el navegador con el mecanismo disponible
en macOS, Linux, WSL o Git Bash. Si no puede abrirlo, muestra la URL para copiarla.
