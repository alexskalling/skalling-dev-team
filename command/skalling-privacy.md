---
description: Marca un proyecto como interno (memoria compartida vía git) o externo (memoria nunca sale de la máquina local).
---

# Skalling Privacy

Por diseño, Skalling commitea una fotografía completa de TeamDB
(`db/teamdb/team.dump.sql`: tareas, planes, decisiones) para que un equipo la
comparta vía git. En un proyecto ajeno (de un cliente, no de la propia
empresa), eso es exactamente lo que no se quiere.

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/skalling-privacy.sh" "$@"
```

Uso (acepta `interno`/`externo` o `internal`/`external`, indistinto):
- `/skalling-privacy` o `/skalling-privacy status` — modo actual del proyecto.
- `/skalling-privacy externo` — agrega `.opencode/` y `db/teamdb/` a
  `.gitignore` (bloque marcado, no toca el resto del archivo). De ahí en más,
  nada de la memoria de Skalling se commitea ni se pushea. Si algo de eso ya
  estaba commiteado de antes, lo avisa explícitamente — no lo borra solo del
  historial de git, eso requiere una decisión aparte del usuario.
- `/skalling-privacy interno` — vuelve al comportamiento de siempre (memoria
  compartida vía git), quitando el bloque agregado.

No inventar excepciones a mano en `.gitignore`: si alguien pide ajustar qué
se ignora, usar este comando, no editar el archivo directamente.
