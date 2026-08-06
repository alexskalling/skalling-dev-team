---
description: Visualiza la memoria del proyecto como grafo. Auto-enlaza conceptos por categoría/tag y muestra la red. Alterna con /skalling-status.
---

# Skalling Graph Protocol

Eres Alex, el orquestador de Skalling. El usuario ejecutó `/skalling-graph`.

## Paso 1 — Enlazar memoria automáticamente

Corre el auto-linker (idempotente, no duplica links):

```bash
bash "$SKALLING_ROOT/scripts/teamdb-link.sh" "$(pwd)"
```

Esto crea:
- `related` — conceptos que comparten **categoría**
- `related` — conceptos/decisiones que comparten **tag**
- `uses` — conceptos no-stack → conceptos de categoría `stack`

Si el usuario quiere ver qué se va a crear sin tocar nada:

```bash
bash "$SKALLING_ROOT/scripts/teamdb-link.sh" "$(pwd)" --dry-run
```

## Paso 2 — Mostrar el grafo

```bash
bash "$SKALLING_ROOT/scripts/teamdb-graph.sh" "$(pwd)" text
```

Si el usuario quiere mermaid (para pegar en un renderer tipo mermaid.live) o dot (Graphviz):

```bash
bash "$SKALLING_ROOT/scripts/teamdb-graph.sh" "$(pwd)" mermaid
bash "$SKALLING_ROOT/scripts/teamdb-graph.sh" "$(pwd)" dot
```

## Paso 3 — Profundizar en un nodo

Para ver tags + relaciones entrantes y salientes de un concepto/decisión:

```bash
bash "$SKALLING_ROOT/scripts/teamdb-related.sh" <slug> concept
bash "$SKALLING_ROOT/scripts/teamdb-related.sh" <slug> decision
```

## Paso 4 — Buscar memoria

```bash
bash "$SKALLING_ROOT/scripts/teamdb-search.sh" "<query>" concept
bash "$SKALLING_ROOT/scripts/teamdb-search.sh" "<query>" decision
```

## Notas

- Si el grafo sale vacío de links, el proyecto no tiene memoria enlazada (o no hay conceptos con categoría/tag). El paso 1 lo resuelve.
- `$SKALLING_ROOT` se resuelve igual que en `/skalling-init`: variable si está definida, si no `$HOME/.config/opencode`.
