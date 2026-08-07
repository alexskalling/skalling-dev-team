---
name: skalling-models
description: Configura modelo por agente. Detecta providers, recomienda según rol, custom override.
---

# Skalling Models Skill

Configura qué modelo usa cada agente de Skalling en OpenCode.

## Activar cuando

- Querés cambiar el modelo que usa un agente
- Querés aplicar recomendación automática (Thinking vs Admin)
- Querés reset a default global

## Cómo funciona

1. Lee `~/.config/opencode/opencode.json`
2. Detecta providers con API key
3. Lista modelos disponibles
4. Recomienda según rol:
   - Thinking (Pol, Sol, Luz): modelo más capaz
   - Admin (Alex, Teo, Jhon, Pau, Jes): modelo más barato
5. Aplica cambios con backup automático

## Comandos

- `bash scripts/skalling-models.sh` → muestra estado + recomendación
- `bash scripts/skalling-models.sh apply` → aplica recomendación
- `bash scripts/skalling-models.sh custom Teo claude-haiku-4` → custom 1 agente
- `bash scripts/skalling-models.sh reset` → reset todos
- `bash scripts/skalling-models.sh reset Teo` → reset 1

## Mapeo agente → key en opencode.json

| Agente | Key |
|---|---|
| Alex | primary |
| Pol | plan |
| Sol | plan |
| Teo | build |
| Jhon | explore |
| Luz | explore |
| Pau | explore |
| Jes | explore |
