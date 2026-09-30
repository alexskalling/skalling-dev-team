---
description: Diagnostica la instalación global y el proyecto sin modificar nada.
---

# Skalling Doctor

Este comando responde “qué está roto o desactualizado”. Ejecuta el diagnóstico
canónico en modo de solo lectura:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/setup-team-doctor.sh" --project "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

Usa `--strict` solo si el usuario pide que los avisos también fallen. Explica cada
hallazgo en lenguaje sencillo y separa errores bloqueantes de recomendaciones.

Revisa también skills, registro y versión del runtime local. No llames saludable
al proyecto si quedan errores o comprobaciones sin ejecutar. Sin opciones de reparación es de solo lectura. Para actualizar usa /skalling-refresh o /skalling-update.

Drift detection: `skalling-drift.sh <plan-archivado>` admite ejecución manual de solo lectura.
`spec-memory-link.sh <origen> <destino>` es una operación de escritura separada:
no ejecutarla durante doctor; requiere una petición explícita de enlazar exports.

`--reconcile` muestra reparaciones seguras y registros que necesitan revisión.
`--reconcile --apply` aplica únicamente las reparaciones demostrables, con backup.
Solo usar `--apply` cuando el usuario haya pedido reparar. No marca tareas hechas
por antigüedad ni por existir una release. Si hay incertidumbre, devuelve fallo y
la explica; no repetir `--apply` esperando que desaparezca.
