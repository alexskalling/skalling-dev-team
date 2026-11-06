---
description: Inicializa Skalling; elige privacidad antes de instalar en un proyecto ajeno.
---

# Skalling Init

Pedido: $ARGUMENTS

Resuelve la raíz y consulta el modo guardado ANTES de escribir:

```bash
SK_ROOT="${SKALLING_ROOT:-${SKALLING_OPENCODE_DIR:-$HOME/.config/opencode}}"
PROJECT="$(python3 "$SK_ROOT/scripts/skalling-project-root.py" "$PWD")" || exit
bash "$SK_ROOT/scripts/skalling-privacy.sh" status "$PROJECT"
```

Usa `external` cuando el usuario indique externo, ajeno o público donde Skalling
no debe versionarse. Usa `internal` cuando quiera compartir agentes y memoria.
Conserva un modo ya elegido; si falta y el pedido no lo aclara, pregunta antes de
instalar. No repitas una pregunta ya respondida.

Ejecuta con el modo elegido (sustituye el marcador por internal o external):

```bash
bash "$SK_ROOT/bootstrap-context.sh" --target "$PROJECT" --install-project --privacy <modo elegido>
```

En externo, los agentes y TeamDB son locales y las exclusiones viven en
`.git/info/exclude`. No crear ni modificar `.gitignore`, `.gitattributes`,
`AGENTS.md`, CI o documentación compartida para Skalling. No añadir referencias
al equipo en archivos ni mensajes de commit del proyecto. Los commits deben
contener únicamente los cambios funcionales solicitados. El instalador conserva
configuración ajena y rechaza colisiones; no lo fuerces ni retires archivos del
índice para saltar esa protección.

Si ya está inicializado, muestra el estado antes de una reparación con `--force`;
úsalo solo con autorización. Para previsualizar, agrega `--dry-run`.
Si devuelve 3, diferencia lo instalado del contexto pendiente y no repitas
`--force` automáticamente. No declares listo un proceso que falló.

Al terminar comprueba `/skalling-privacy status` y pide reiniciar OpenCode.
Solo en interno pueden versionarse los artefactos de Skalling, siguiendo los
gates y receipts del equipo. Nunca crees un commit automáticamente desde init.

Inicializar prepara memoria, agentes, plugins, scripts y hooks; no significa
comprender todo el proyecto. Antes de implementar consulta TeamDB y los archivos
pertinentes. Las reglas visuales están en concepts/design-system.
