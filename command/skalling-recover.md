---
description: Diagnostica y recupera TeamDB desde su dump versionado con backup previo.
---

# Skalling Recover

Primero comprueba de forma no destructiva si existen TeamDB, dump y backups. Muestra
las rutas encontradas. No restaures mientras la base actual sea legible.

Si el usuario confirma restaurar el dump versionado:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/teamdb-restore.sh" "$(pwd)" --force
```

Usa `--full-reset` únicamente para corrupción confirmada y con autorización explícita.
El script crea un backup antes de reemplazar una base existente; informa su ruta.
