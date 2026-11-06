---
description: Inspecciona estructura, dependencias e impacto usando CodeGraph real.
---

# Skalling CodeGraph

Pedido: $ARGUMENTS

Primero valida la raíz y prepara CodeGraph con el helper canónico. Rechaza HOME,
carpetas temporales y ubicaciones sin evidencia de proyecto antes de inicializar:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
PROJECT="$(python3 "$SK_ROOT/scripts/skalling-project-root.py" "$PWD" --codegraph)" || exit
bash "$SK_ROOT/scripts/skalling-codegraph.sh" "$PROJECT"
```

Si falla, informa el motivo sin reintentar la inicialización ni declarar el índice listo.
Después prefiere `codegraph_explore` con `projectPath` explícito, o consultas CLI
de solo lectura desde esa raíz (`explore`, `query`, `callers`, `callees`,
`impact` o `affected`). No sustituyas CodeGraph con el dashboard ni con un escaneo
casero guardado en TeamDB. Si CodeGraph no está instalado, informa esa limitación.
