# AGENTS.md — Índice de Skalling para este proyecto

Este proyecto usa [Skalling](https://github.com/tu-usuario/skalling-dev-team). El equipo agentico completo (Alex + 7 especialistas) vive en `.opencode/agents/`.

## Reglas Universales

Ver `.opencode/context/constitucion.md` (o `~/.config/opencode/constitucion.md`).

## Skills Disponibles

| Skill | Trigger |
|---|---|
| `skalling-tdd` | Implementar lógica con TDD (red-green-refactor) |
| `skalling-debug` | Debugging sistemático |
| `skalling-verify` | Antes de declarar completo, verificar |
| `skalling-planning` | Escribir planes de implementación |
| `skalling-code-review` | Code review excellence |
| `skalling-doc-coauthoring` | Co-escribir documentación |
| `skalling-brainstorming` | Lluvia de ideas estructurada |
| `skalling-find-skills` | Buscar skills adicionales |

## Comandos

- `/skalling-init` — bootstrap del proyecto
- `/skalling-status` — ver estado de memoria
- `/skalling-refresh` — re-detectar stack
- `/skalling-doctor` — health check
- `/skalling-forget` — purgar memoria obsoleta

## Memoria

Bundle OKF en `.opencode/context/`. Cada concept doc tiene frontmatter YAML.
