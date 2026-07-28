# Log — Historial cronológico del bundle

> Append-only. Cada cambio al bundle se registra acá.
> Pau mantiene este archivo. Lo actualiza en cada consolidación.

## Formato

```
## [YYYY-MM-DD HH:MM] [acción]
**Por:** [agent]
**Acción:** [qué se hizo]
**Path:** [archivo afectado]
**Razón:** [por qué]
```

---

## YYYY-MM-DD HH:MM — Bootstrap inicial

**Por:** alex
**Acción:** Bundle OKF creado con detección automática de stack.
**Path:** `.opencode/context/` completo
**Razón:** Primer arranque de Skalling en este proyecto.
