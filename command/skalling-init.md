---
description: Inicializa la memoria TeamDB y detecta el stack del proyecto actual.
---

# Skalling Init

Inicializa Skalling usando el bootstrap canónico instalado. No reimplementes la
detección ni escribas directamente en la base de datos.

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/bootstrap-context.sh" --target "$(pwd)"
```

Si el proyecto ya está inicializado, muestra primero el estado y pide confirmación
antes de usar `--force`. Al terminar, resume stack detectado, ubicación de TeamDB y
avisos reales del comando. No afirmes que algo se instaló si el proceso falló.

El éxito significa memoria inicializada, no comprensión completa del proyecto. No crear carpetas ni Markdown manualmente. Las reglas visuales se consultan en concepts/design-system. Antes de implementar, investigar los archivos pertinentes y completar el contexto del pedido.
