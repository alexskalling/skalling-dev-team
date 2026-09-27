---
description: Comprueba y aplica actualizaciones de Skalling con confirmación y backup.
---

# Skalling Update

Para comprobar sin cambiar nada:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
bash "$SK_ROOT/scripts/update.sh" --check-only
```

Por defecto solo se ofrecen **releases publicados** (tags `vX.Y.Z`), nunca el
último push a `main`. Si hay una versión nueva, muestra los commits y el
changelog. Solo después de la confirmación del usuario, ejecuta
`bash "$SK_ROOT/scripts/update.sh"`. El actualizador conserva el backup
automático del instalador y, si la instalación falla, vuelve a la versión
anterior.

`--channel main` sigue la rama principal y es solo para mantenedores; no
proponerlo al usuario. Con `SKALLING_REQUIRE_SIGNED_TAGS=1` el release debe
tener una firma válida.
