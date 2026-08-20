# Log — Historial cronológico del bundle

> **DEPRECADO a partir de v0.9.3.** El historial del bundle ya NO vive en este archivo.
> El log cronológico se migra a la tabla `audit_log` de `team.db`.
> Este archivo es un export legacy. No editar — regenerar de `audit_log`.

## Formato legacy (ya no usar)

```
## [YYYY-MM-DD HH:MM] [acción]
**Por:** [agent]
**Acción:** [qué se hizo]
**Path:** [archivo afectado]
**Razón:** [por qué]
```

---

## Migración

Para regenerar este archivo desde la DB:
```bash
sqlite3 .opencode/context/team.db "SELECT agent, action, path, reason, ts FROM audit_log ORDER BY ts DESC LIMIT 100"
```
