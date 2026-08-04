# Spec 05: Check informativo en `setup-team-doctor.sh`

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then (BDD)
> **Cubre**: Punto 5 del scope (nueva sección informativa en el doctor).

---

## Escenario 1: El doctor tiene una nueva sección `check_code_intelligence()`

**Given** que el doctor `setup-team-doctor.sh` existe
**When** se agrega la verificación de codebase-memory-mcp
**Then** existe una nueva función `check_code_intelligence()` en el script
**Y** la función es invocada desde `main()` (después de `check_global_install` o `check_project_install`)
**Y** la función imprime su propia sección con `section "Code Intelligence (opt-in)"`

---

## Escenario 2: El check reporta como `info`, NO como error ni warning

**Given** que el doctor corre
**When** la sección de Code Intelligence se ejecuta
**Then** los hallazgos **siempre** se imprimen con el helper `info()` (azul, ℹ)
**Y** **nunca** se usa `warn()` ni `err()` para codebase-memory-mcp
**Y** no se incrementa `WARN_COUNT` ni `ERROR_COUNT`
**Y** el resumen final del doctor (OK / Warnings / Errors) **no se ve afectado** por el estado del MCP

---

## Escenario 3: Verifica si el binario está en PATH

**Given** que el doctor corre la sección de Code Intelligence
**When** ejecuta el primer check
**Then** corre `command -v codebase-memory-mcp` o `which codebase-memory-mcp`
**Y** si está disponible, imprime `info "Binario codebase-memory-mcp instalado en PATH"` con la ruta completa
**Y** si NO está disponible, imprime `info "codebase-memory-mcp no está instalado (opt-in, no requerido)"`

---

## Escenario 4: Verifica si está configurado como MCP server

**Given** que el binario está (o no) en PATH
**When** ejecuta el segundo check
**Then** corre `grep -q codebase-memory-mcp ~/.config/opencode/opencode.jsonc`
**Y** si la configuración lo referencia, imprime `info "Registrado como MCP server en opencode.jsonc"`
**Y** si NO la referencia, imprime `info "No registrado en opencode.jsonc"`

---

## Escenario 5: Combinaciones de estado posibles

**Given** los dos checks (binario + config)
**When** el doctor resume la sección
**Then** las 4 combinaciones posibles se manejan sin warnings/errors:

| Binario | Config | Output |
|---|---|---|
| ✓ en PATH | ✓ en opencode.jsonc | `info "Binario instalado y configurado"` |
| ✓ en PATH | ✗ en opencode.jsonc | `info "Binario instalado pero falta registro en opencode.jsonc"` |
| ✗ no en PATH | ✓ en opencode.jsonc | `info "No instalado pero hay referencia en opencode.jsonc (¿desinstalaste el binario?)"` |
| ✗ no en PATH | ✗ en opencode.jsonc | `info "No instalado (opt-in, no requerido)"` |

**Y** ninguna combinación sale con error o warning.

---

## Escenario 6: El doctor no falla nunca por Code Intelligence

**Given** cualquier estado del MCP
**When** corre `bash setup-team-doctor.sh --strict`
**Then** el exit code es 0 si no hay otros errores en el doctor
**Y** Code Intelligence nunca causa exit 1
**Y** `--strict` solo afecta a `WARN_COUNT`, que Code Intelligence no incrementa

---

## Reglas MUST (obligatorias)

1. El archivo `setup-team-doctor.sh` **MUST** contener una nueva función `check_code_intelligence()`.
2. La función **MUST** ser invocada desde `main()`.
3. Todos los hallazgos de la función **MUST** usar el helper `info()` — nunca `warn()` ni `err()`.
4. La función **MUST** verificar `command -v codebase-memory-mcp` o equivalente.
5. La función **MUST** verificar `grep codebase-memory-mcp ~/.config/opencode/opencode.jsonc`.
6. La función **MUST NOT** incrementar `WARN_COUNT` ni `ERROR_COUNT`.
7. La sección **MUST** tener su propio `section "Code Intelligence (opt-in)"` (o similar) con prefijo identificable.

## Reglas SHOULD (recomendadas)

1. La verificación de opencode.jsonc **SHOULD** manejar gracefully el caso donde `~/.config/opencode/` no existe (no crashear con `set -e`).
2. La sección **SHOULD** explicar brevemente en un comentario arriba qué hace y por qué es info-only.
3. Si el binario está pero la config no, el mensaje **SHOULD** sugerir correr `/skalling-init` o revisar manualmente.

## Reglas MAY (opcionales)

1. La sección **MAY** incluir un link a la documentación externa de codebase-memory-mcp en un comentario.
2. La sección **MAY** recordar que el snippet en los agentes ya está activo (independientemente de si el binario está instalado).

---

## Criterios de Aceptación (resumen)

- [ ] `setup-team-doctor.sh` tiene función `check_code_intelligence()`
- [ ] La función es invocada desde `main()`
- [ ] Todos los hallazgos usan `info()` (azul, ℹ)
- [ ] Ningún hallazgo usa `warn()` ni `err()` para Code Intelligence
- [ ] Verifica binario en PATH
- [ ] Verifica config en opencode.jsonc
- [ ] `WARN_COUNT` y `ERROR_COUNT` no se ven afectados
- [ ] `bash setup-team-doctor.sh --strict` no falla por Code Intelligence
- [ ] El resto de checks del doctor sigue funcionando (no regresión)

---

## Out of Spec (explícitamente NO incluido)

- Auto-instalación del binario si no está (eso es del init, no del doctor).
- Tests automatizados del doctor (no se agregan tests para esta sección específica — el doctor se prueba manualmente).
- Verificación funcional del binario (`codebase-memory-mcp --help`).
- Reporte de versión del binario instalado.
- Comparación con versiones disponibles upstream (no es un update checker).
- Integración con `find-skills` o cualquier sistema de descubrimiento.
