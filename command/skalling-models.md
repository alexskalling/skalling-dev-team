---
description: Asigna un modelo de OpenCode a cada agente de Skalling, individualmente.
---

# Skalling Models

Cada uno de los 8 agentes (Alex, Jes, Jhon, Luz, Pau, Pol, Sol, Teo) puede usar un
modelo distinto — por ejemplo, los agentes que piensan más (Pol, Sol) con un modelo
más potente, y los agentes rápidos/administrativos (Teo, Jhon) con uno más liviano.
Un agente sin asignación explícita usa el modelo default de la sesión de OpenCode,
como siempre.

Este comando NO inventa nombres de modelo. Corré `opencode models` para ver los IDs
disponibles en tu instalación antes de asignar.

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/skalling-models.sh" "$@"
```

Uso:
- `/skalling-models` o `/skalling-models show` — modelo actual de cada agente.
- `/skalling-models set Alex anthropic/claude-opus-5` — asigna un modelo a un agente.
- `/skalling-models reset Alex` — vuelve ese agente al default de la sesión.
- `/skalling-models reset` — vuelve los 8 agentes al default de la sesión.

La asignación queda en `model-overrides.json`, en tu instalación global (no en el
repo de Skalling) — sobrevive a un `/skalling-update` o reinstalación, porque
install-global.sh la vuelve a aplicar después de regenerar los agentes.
