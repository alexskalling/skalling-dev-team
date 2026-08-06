# Comandos de Skalling

## /skalling-dashboard

Abre el dashboard web de TeamDB en el browser. No necesita servidor — es un HTML estático que conecta directo a SQLite via WebAssembly.

Muestra: stats generales, grafo de memoria (Mermaid), planes con % de avance, tareas, concepts, decisiones, problemas y preferences.

## Uso

```
/skalling-dashboard
```

## /skalling-graph

Visualiza la memoria del proyecto como grafo y busca en ella:

1. Auto-enlaza la memoria (`teamdb-link.sh`): `related` por categoría/tag, `uses` módulo→stack. Idempotente.
2. Dibuja el grafo (`teamdb-graph.sh`) en `text`, `mermaid` o `dot`.
3. Profundiza en un nodo (`teamdb-related.sh <slug>`): tags + relaciones entrantes y salientes.
4. Busca memoria (`teamdb-search.sh "<query>"`).

## Uso

```
/skalling-graph
```

Para más detalle, ver `command/skalling-graph.md` o `command/skalling-dashboard.md` después de instalar.
