---
description: Diagnostica la instalación global y el proyecto sin modificar nada.
---

# Skalling Doctor

Este comando responde “qué está roto o desactualizado”. Ejecuta el diagnóstico
canónico en modo de solo lectura:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/setup-team-doctor.sh" --project "$(pwd)"
```

Usa `--strict` solo si el usuario pide que los avisos también fallen. Explica cada
hallazgo en lenguaje sencillo y separa errores bloqueantes de recomendaciones.

Drift detection de ejecución manual: `bash "$SK_ROOT/scripts/skalling-drift.sh"
<plan-archivado>` revisa deriva contra una especificación. También puedes ejecutar `bash
"$SK_ROOT/scripts/spec-memory-link.sh" <origen> <destino>` para enlazar exports históricos.
