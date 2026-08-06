# /skalling-codegraph

Actualiza y consulta el grafo de imports del proyecto.

## Protocolo

El grafo de código se almacena en la DB del proyecto:
- `code_graph_cache` — nodos (archivos del proyecto)
- `code_imports` — edges (relaciones de import)

El LLM tiene acceso a esta información para entender la estructura del proyecto.

## Uso

```bash
# Refrescar el grafo (escanea todos los archivos del proyecto)
curl -X POST http://localhost:3741/api/codegraph/refresh

# Consultar el grafo actual (desde cache)
curl http://localhost:3741/api/codegraph
```

## Para agentes

Cuando el proyecto cambie significativamente (nuevos módulos, refactors):
1. Ejecutá `POST /api/codegraph/refresh` para actualizar el cache
2. Usá el grafo para entender las dependencias antes de proponer cambios
3. Mantené la documentación del proyecto sincronizada con la estructura real

## Para Pau (documentador)

Cuando documentés el proyecto:
1. Consultá `/api/codegraph` para ver la estructura real de archivos
2. Usá esa info para mantener `docs/` o `SPEC.md` alineados con el código
3. Si la estructura cambió, corré `/api/codegraph/refresh` antes de documentar
