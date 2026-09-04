---
description: Inspecciona estructura, dependencias e impacto usando CodeGraph real.
---

# Skalling CodeGraph

Usa primero la herramienta `codegraph_explore`. Si no está disponible, resuelve la
raíz con Git, verifica `.codegraph/` e inicializa una sola vez con el comando oficial:

```bash
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
test -d "$PROJECT/.codegraph" || gentle-ai codegraph init --cwd "$PROJECT"
codegraph status
```

Después usa consultas de solo lectura (`explore`, `query`, `callers`, `callees`,
`impact` o `affected`). No sustituyas CodeGraph con el dashboard ni con un escaneo
casero guardado en TeamDB. Si CodeGraph no está instalado, informa esa limitación.
