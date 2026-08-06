---
type: Decision
slug: grafo-wip-y-decisions-v0.7.6
title: Grafo de memoria ahora incluye WIP y auto-link decisions→concepts
status: accepted
decided_at: 2026-08-05
decided_by: Pau (consolidación v0.7.6)
---

# v0.7.6 — Grafo de memoria con WIP y auto-link decisions→concepts

## Contexto

Antes de v0.7.6, el grafo de memoria (`memory_links` + concepts/decisions) NO incluía features/tasks activas de `work_in_progress`. Pol/Teo no veían si una feature ya estaba en curso y duplicaban trabajo.

Además, las decisions no estaban linkeadas automáticamente a los concepts que referenciaban en su `body_md`. Para entender "por qué elegimos PostgreSQL" había que leer todas las decisions y buscar manualmente.

## Decisión

### 1. Incluir WIP en el grafo

- Cada WIP con `type IN ('feature','task')` y `parent_id IS NOT NULL` aparece como nodo en el grafo
- Link `part_of` entre WIP hijo y su parent (task→feature, feature→plan)
- Visible en `/api/graph` del dashboard

### 2. Auto-link decisions → concepts

- Si el `body_md` de una decision menciona el slug de un concept (substring match), se crea link `decision → concept` con `link_type='references'`, `confidence=0.9`
- Idempotente (no duplica links existentes)
- Riesgo bajo: si un slug contiene `%` o `_` (wildcards de LIKE), podría haber falsos positivos. Por convención los slugs son kebab-case.

### 3. Comando unificado

`teamdb-graph-refresh.sh` corre ambos refreshes (memoria + código) en un solo comando.

### 4. R14 en constitución — ahorro de tokens

R14 ahora formaliza que los 8 agentes DEBEN consultar grafos antes de proponer cambios. Ejemplo cuantificado: Teo ahorra 75% de tokens si consulta el grafo antes de implementar.

## Consecuencias

### Positivas

- Pol/Teo/Jes pueden ver features activas sin abrir la DB
- Pau auto-linkea decisions al consolidar
- Dashboard muestra grafo completo (29 nodos en Infra de muestra)
- Comando `/skalling-graph-refresh` unificado para refresh on-demand

### Negativas / Riesgos

- LIKE substring search es O(n*m) — aceptable porque decisions son pocas
- Schema migration 008 puede ser frágil si se interrumpe a mitad (mitigado por `|| true` en init)
- Link huérfano histórico detectado y limpiado (id=56, preservado en backup)

## Tests

- `tests/teamdb-link.test.sh`: 11/11 PASS
- Caso C10 nuevo: "R4 no crea part_of entre concepts" — invariante R4

## Artefactos

- `sql/migrations/008_extend_link_types.sql`
- `scripts/teamdb-link.sh` (R4 + R5)
- `scripts/teamdb-graph-refresh.sh` (nuevo)
- `scripts/dashboard-server.py` (refactor)
- `command/skalling-graph-refresh.md` (nuevo)
- `constitucion/constitucion.md` (R14 ampliado)
- `agents-base/*.md` (8 archivos con sección de grafos)
