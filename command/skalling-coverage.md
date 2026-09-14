---
description: Corre la cobertura de tests del proyecto y guarda el resultado real en TeamDB.
---

# Skalling Coverage

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/skalling-coverage.sh" "$(pwd)"
```

Corre el comando de cobertura detectado en `project.yaml` (`testing.coverage.command`).
Si no hay ninguno configurado, dilo con claridad y sugiere `/skalling-refresh` o
agregarlo a mano — nunca inventes un porcentaje. Si el comando corre pero el
formato de salida no se reconoce, igual queda un registro en TeamDB explicando
por qué; muestra esa nota tal cual, sin adivinar el número.

El resultado (y el historial de corridas anteriores) también se ve en el
dashboard, pestaña Sistema.
