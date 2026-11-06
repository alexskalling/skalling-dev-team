---
description: Mantiene Skalling local en proyectos externos o permite compartirlo en proyectos internos.
---

Pedido: $ARGUMENTS

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
bash "$SK_ROOT/scripts/skalling-privacy.sh" <acción validada> "$PROJECT"
```

- Sin argumentos o `status`: consulta el modo y la protección actual, sin escribir.
- `externo` / `external`: configura exclusiones locales en `.git/info/exclude`;
  no agrega reglas al `.gitignore` compartido. Se puede elegir antes de init.
  Protege `.opencode/`, `db/teamdb/`, `.skalling-backups/` y `.codegraph/`.
  Guarda el modo en Git local y lo refleja en TeamDB cuando existe.
- `interno` / `internal`: retira únicamente las exclusiones locales administradas;
  permite volver a compartir Skalling. No lo selecciones para un repositorio ajeno.

Al convertir instalaciones antiguas a externo, retira solo los bloques marcados
de Skalling de `.gitignore` y `.gitattributes`, con respaldo dentro de Git local.
Preserva el contenido ajeno. No elimina archivos rastreados, no cambia el índice
ni reescribe historial. Los restos versionados o un AGENTS.md generado requieren
una resolución explícita: no los borres ni los publiques automáticamente.

Una salida 3 significa protección incompleta. No afirmar que está protegido si
quedan artefactos rastreados, restos o exclusiones que no funcionan. No confundir
esta comprobación con una limpieza del historial remoto.

En externo, init y update respetan el modo, no crean instrucciones compartidas
ni CI, y los hooks bloquean artefactos de Skalling preparados para commit/push.
No añadas referencias a Alex o al equipo a los archivos o commits del proyecto.
Esto no controla datos enviados a proveedores de IA ni herramientas que omitan
los hooks o la configuración local de Git.

`verify-internal` sigue disponible para comprobar un bundle interno sin escribir:
`bash "$SK_ROOT/scripts/skalling-privacy.sh" verify-internal "$PROJECT"`.
