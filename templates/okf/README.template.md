---
type: Context
title: [Bundle name]
description: [One-line description of what this OKF bundle captures]
timestamp: YYYY-MM-DDTHH:MM:SSZ
agent: alex
confidence: 1.0
---

# [Project Name] — Memoria del Equipo (OKF Bundle)

Este es el bundle de conocimiento persistente de este proyecto, en formato [Open Knowledge Format (OKF) v0.1](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf) + extensiones de Skalling.

## Cómo navegarlo

- [`index.md`](./index.md) — entrada principal, links a todas las áreas.
- [`log.md`](./log.md) — historial cronológico de cambios al bundle.
- `stack/` — qué usa este proyecto (lenguaje, frameworks, runtime).
- `proyecto/` — qué es este proyecto y para quién.
- `decisiones/` — ADRs (decisiones arquitectónicas tomadas).
- `trabajo-en-curso/` — features activas.
- `preferencias/` — convenciones del equipo en este proyecto.
- `problemas-conocidos/` — workarounds y bugs recurrentes.

## Schema

Cada concept doc tiene frontmatter:

```yaml
---
type: [Concept | Decision | Preference | Workaround | WorkInProgress | Context]
title: [Título humano]
description: [Una línea]
resource: [URL o path al origen]
tags: [array]
timestamp: YYYY-MM-DDTHH:MM:SSZ
agent: [quién lo escribió]
confidence: 0.0-1.0      # opcional
supersedes: [path]       # opcional, linkea versión anterior
---
```

## Quién puede escribir

Cualquier agente (no solo Pau) puede crear o actualizar concept docs. Pau consolida.

## Política de olvido

- Cada 6 meses, Pau revisa entries sin referenciar.
- `supersedes` linkea versiones anteriores (la vieja queda pero marcada).
- Pau purga duplicados cuando los detecta.
