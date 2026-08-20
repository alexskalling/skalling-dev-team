---
name: skalling-memory
description: "Trigger: memory, context, remember, project history, past decisions, previous work, learned, known. DB is the ONLY source of truth — SQLite via team.db, NOT files."
license: MIT
metadata:
  author: skalling-team
  version: "2.0"
---

# Skalling Memory — DB as ONLY Source of Truth

## Overview

**REGLA DURA: La única fuente de verdad es `team.db` (SQLite).**
Los archivos en `.opencode/context/` son EXPORTS derivados de la DB, nunca la fuente.
El pre-commit hook bloquea commits que escriban `.md` o `.jsonl` como fuente en esas rutas.

## Hard Rules

1. **DB first.** Cada decisión, concepto, preferencia o problema conocido va a una tabla de `team.db`, no a un archivo.
2. **Archivos son exports.** Los `.md` en `.opencode/context/` se regeneran de la DB con `teamdb-export-md.sh`.
3. **Pre-commit blocks violations.** Si un commit intenta escribir `.md` o `.jsonl` nuevo en `.opencode/context/` sin INSERT previo en la DB, el hook rechaza con exit 1.
4. **Memory nunca reemplaza verificación.** Decisiones guardadas pueden sobrescribirse con nueva evidencia.

## DB Schema (source of truth)

| Tabla | Uso |
|---|---|
| `decisions` | Decisiones arquitectónicas (ADR) |
| `concepts` | Conceptos del proyecto (stack, módulo, API, tabla) |
| `preferences` | Preferencias del equipo / del usuario |
| `known_problems` | Workarounds activos |
| `memory_links` | Relaciones entre concepts/decisions |
| `memory_tags` | Tags transversales |

## Memory Operations

### SAVE — Adding to memory

```bash
# Decision arquitectónica
teamdb_query_project "INSERT INTO decisions (slug, title, body_md, status, updated_at)
  VALUES ('jwt-auth', 'JWT over sessions', '# Why\nStateless, better for APIs.\n\n## Tradeoffs\n...', 'accepted', datetime('now'))"

# Concepto del proyecto
teamdb_query_project "INSERT INTO concepts (slug, title, body_md, category, updated_at)
  VALUES ('api-rest', 'REST API design', '# REST\n...', 'api', datetime('now'))"

# Preferencia del equipo
teamdb_query_project "INSERT INTO preferences (slug, title, body_md, updated_at)
  VALUES ('no-else', 'No else statements', 'Early return only. eslint-plugin.', datetime('now'))"

# Problema conocido
teamdb_query_project "INSERT INTO known_problems (slug, title, workaround_md, status, updated_at)
  VALUES ('prod-timeout', 'Production timeout', 'Set DB timeout to 30s in prod.', 'open', datetime('now'))"

# Enlazar concepts/decisions
teamdb_query_project "INSERT INTO memory_links (from_table, from_id, to_table, to_id, link_type)
  VALUES ('concepts', (SELECT id FROM concepts WHERE slug='api-rest'),
          'decisions', (SELECT id FROM decisions WHERE slug='jwt-auth'), 'uses')"
```

### RECALL — Loading context

```bash
# Buscar decisions aceptadas
teamdb_query_project "SELECT slug, title FROM decisions WHERE status='accepted'"

# Buscar concept por categoría
teamdb_query_project "SELECT slug, title FROM concepts WHERE category='api'"

# Buscar con full-text search
sqlite3 .opencode/context/team.db "SELECT slug, title FROM decisions_fts WHERE decisions_fts MATCH 'JWT'"

# Cargar preferencias del equipo
teamdb_query_project "SELECT slug, title FROM preferences"

# Buscar problemas abiertos
teamdb_query_project "SELECT slug, title, workaround_md FROM known_problems WHERE status='open'"
```

### SEARCH — Finding related

```bash
# Ver concepts enlazados a una decision
teamdb_query_project "SELECT c.slug, c.title FROM memory_links ml
  JOIN concepts c ON c.id=ml.from_id
  WHERE ml.to_table='decisions'
  AND ml.to_id=(SELECT id FROM decisions WHERE slug='jwt-auth')"

# Buscar decisions por topic
teamdb_query_project "SELECT slug, title FROM decisions WHERE title LIKE '%auth%'"
```

## Agent Context Loading Protocol

Cada agente DEBE cargar contexto de la DB al arrancar:

```bash
# 1. Decisiones aceptadas del dominio
teamdb_query_project "SELECT slug, title FROM decisions WHERE status='accepted'"

# 2. Preferences (siempre)
teamdb_query_project "SELECT slug, title FROM preferences"

# 3. Problemas abiertos del proyecto
teamdb_query_project "SELECT slug, title FROM known_problems WHERE status='open'"

# 4. Si trabaja en un módulo específico, cargar sus concepts
teamdb_query_project "SELECT slug, title FROM concepts WHERE category='$MODULE'"
```

## Memory Anti-Patterns

| Anti-pattern | Problem | Correct |
|---|---|---|
| Guardar en `.jsonl` | viola la regla DB-first | `INSERT INTO` en la tabla correspondiente |
| Guardar en `.md` como fuente | el hook lo bloquea | `INSERT INTO` → luego export |
| Guardar todo | noise | Solo decisiones que afectan otras decisiones |
| No cargar al arrancar | context loss | `teamdb_query_project` al inicio |
| Sobrescribir hechos sin evidencia | confusión | Nueva fila + link, no UPDATE destructivo |

## Integración con el Ciclo

- **Pol** valida con el usuario → INSERT en `proposals` (vía `teamdb-plan.sh`)
- **Sol** planifica → INSERT en `plans` + `tasks` (vía `teamdb-plan.sh`)
- **Teo** ejecuta → solo código, no guarda memoria
- **Pau** consolida al cerrar → INSERT en `decisions`/`concepts`/`preferences`/`known_problems`
- **Todos** consultan → `teamdb_query_project` SELECT

## Quick Reference

```bash
# Guardar una decisión
teamdb_query_project "INSERT INTO decisions (slug, title, body_md, status, updated_at)
  VALUES ('api-rest', 'REST over GraphQL', '# Why...', 'accepted', datetime('now'))"

# Cargar contexto para una tarea
teamdb_query_project "SELECT slug, title FROM decisions WHERE status='accepted'"
teamdb_query_project "SELECT slug, title FROM preferences"

# Buscar en todo
sqlite3 .opencode/context/team.db "SELECT slug, title FROM decisions_fts WHERE decisions_fts MATCH 'JWT OR auth'"
```

---

**Memory es un segundo cerebro, no un diario. Guardá decisiones que afectan otras decisiones, no eventos.**
