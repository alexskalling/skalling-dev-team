---
description: Reconcilia contexto, skills y registro; detecta runtime local desactualizado.
---

# Skalling Refresh

Pedido: $ARGUMENTS

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
bash "$SK_ROOT/scripts/skalling-refresh.sh" --check "$PROJECT"
```

Si se pidió actualizar, ejecutar el mismo helper con `--apply`. La invocación de
refresh autoriza reparar contexto generado, skills core administradas y registro.
No pedir otra confirmación por esas operaciones. Preservar personalizaciones;
mostrar conflictos pendientes. Para una consulta de diagnóstico, usar solo --check.

El reporte distingue core faltantes, metadatos inválidos, registro desactualizado,
recomendaciones externas y runtime local. No instalar skills externas sin una
selección explícita, ni confundir recomendación con requisito bloqueante.
Para runtime desactualizado usar /skalling-update --project. Una salida distinta
de cero significa revisión/reparación incompleta: nunca decir que todo está listo.
