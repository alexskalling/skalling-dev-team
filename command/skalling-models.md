---
description: Configura modelos por agente en OpenCode. Detecta providers disponibles y recomienda según rol.
---

# Skalling Models

Configura qué modelo usa cada agente de Skalling.

## Uso

```
/skalling-models
```

Sin argumentos: muestra estado actual + recomendación.

## Sub-comandos

| Comando | Qué hace |
|---|---|
| `/skalling-models` | Mostrar estado + recomendación |
| `/skalling-models apply` | Aplicar recomendación automática |
| `/skalling-models custom <agente> <modelo>` | Custom: asignar modelo a 1 agente |
| `/skalling-models reset [agente]` | Reset: volver al default global |

## Lógica de recomendación

| Rol | Agentes | Modelo |
|---|---|---|
| Thinking (necesita reasoning) | Pol, Sol, Luz | Más capaz disponible (sonnet, gpt-4o) |
| Admin (ejecuta, no inventa) | Alex, Teo, Jhon, Pau, Jes | Más barato disponible (haiku, gpt-4o-mini) |

## Detección de modelos

Lee `~/.config/opencode/opencode.json` y extrae los providers con API key configurada. Solo sugiere modelos que están realmente disponibles.

## Backup

Antes de modificar, hace backup automático en `~/.config/opencode/.skalling-backups/`.
