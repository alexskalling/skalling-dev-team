# Spec 04: Paso 5 opt-in en `/skalling-init`

> **Status**: Draft
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then (BDD)
> **Cubre**: Punto 4 del scope (opt-in en `command/skalling-init.md`).

---

## Escenario 1: El opt-in aparece al final del flujo de init

**Given** que el usuario corrió `/skalling-init` y completó los pasos 1–4.5 existentes
**When** el flujo llega al final del init
**Then** se muestra el nuevo paso 5 con el texto: "¿Querés instalar codebase-memory-mcp? (Sí/No)"
**Y** se ofrece con formato A/B/C consistente con otros pasos del init
**Y** el paso 5 está **después** del paso 4.5 (find-skills) y **antes** del resumen final del init

---

## Escenario 2: Si el usuario dice Sí — se muestra el comando antes de ejecutar

**Given** que el opt-in se mostró
**When** el usuario responde Sí
**Then** el init imprime el comando exacto que va a ejecutar: `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash`
**Y** pregunta confirmación explícita: "¿Ejecuto este comando? (Sí/No)"
**Y** solo si confirma, ejecuta el comando
**Y** si dice No, el init sigue normal sin instalar

---

## Escenario 3: Después de instalar, se verifica la configuración MCP

**Given** que el usuario confirmó la instalación
**When** el comando `curl ... | bash` terminó
**Then** el init verifica que codebase-memory-mcp aparece en `~/.config/opencode/opencode.jsonc` usando `grep -q codebase-memory-mcp`
**Y** si la verificación pasa, imprime: "codebase-memory-mcp registrado como MCP server"
**Y** si la verificación falla, imprime warning: "El binario se instaló pero no aparece en opencode.jsonc — revisá manualmente"

---

## Escenario 4: Si verificó OK, se recuerda que el snippet ya está activo

**Given** que la verificación de opencode.jsonc pasó
**When** el init muestra el resumen final
**Then** el resumen incluye una línea recordatoria: "✓ Code Intelligence snippet activo en los 8 agentes (ya estaba habilitado por tasks 1–3)"
**Y** esta línea aparece solo si la verificación pasó (no si falló o si el usuario eligió No)

---

## Escenario 5: Si el usuario dice No — el init sigue normal sin cambios

**Given** que el opt-in se mostró
**When** el usuario responde No
**Then** el init sigue con el resumen final normal
**Y** NO se instala nada relacionado a codebase-memory-mcp
**Y** NO se modifica `~/.config/opencode/opencode.jsonc`
**Y** el resumen final **NO** menciona Code Intelligence (porque el usuario eligió no activarlo)

---

## Escenario 6: El opt-in es una sola pregunta, no un flujo largo

**Given** que el init ya tiene varios pasos
**When** el paso 5 se ejecuta
**Then** es **una sola pregunta** Sí/No
**Y** no se hacen preguntas adicionales sobre configuración (no se pregunta versión, ruta, etc.)
**Y** el paso entero toma menos de 30 segundos si el usuario dice No

---

## Reglas MUST (obligatorias)

1. El archivo `command/skalling-init.md` **MUST** contener un nuevo paso 5 (después del 4.5 find-skills) que pregunta sobre codebase-memory-mcp.
2. El paso 5 **MUST** ser opt-in (Sí/No), NO automático.
3. Si el usuario dice Sí, el init **MUST** mostrar el comando completo antes de ejecutarlo y pedir confirmación.
4. El comando ejecutado **MUST** ser exactamente: `curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash`.
5. Después de instalar, el init **MUST** verificar que `codebase-memory-mcp` aparece en `~/.config/opencode/opencode.jsonc`.
6. Si el usuario dice No, el init **MUST** continuar sin cambios y sin instalar nada.

## Reglas SHOULD (recomendadas)

1. La pregunta Sí/No **SHOULD** seguir el formato A/B/C/D consistente con otros pasos del init (ej: A) Sí, instalar / B) No, saltar).
2. La verificación de opencode.jsonc **SHOULD** hacerse con `grep -q` (silencioso) y reportar el resultado en una sola línea.
3. Si la verificación falla (binario instalado pero no en config), el init **SHOULD** dar instrucciones mínimas al usuario para arreglarlo manualmente.

## Reglas MAY (opcionales)

1. El init **MAY** verificar primero si el binario ya está instalado (`which codebase-memory-mcp`) y, si lo está, saltar la pregunta y pasar directo a verificar la configuración MCP.
2. El init **MAY** ofrecer un comando de desinstalación si el usuario quiere revertir (`codebase-memory-mcp uninstall` o equivalente).

---

## Criterios de Aceptación (resumen)

- [ ] `command/skalling-init.md` tiene un paso 5 nuevo
- [ ] El paso 5 está después del 4.5 find-skills y antes del resumen final
- [ ] El paso 5 pregunta Sí/No sobre instalar codebase-memory-mcp
- [ ] Si Sí: muestra comando, pide confirmación, ejecuta, verifica
- [ ] Si Sí + verificado OK: aparece línea recordatoria en el resumen final
- [ ] Si No: init sigue normal, no se instala nada
- [ ] El formato de la pregunta es consistente con otros pasos del init
- [ ] Lectura humana del flujo confirma que el opt-in no rompe los pasos previos

---

## Out of Spec (explícitamente NO incluido)

- Instalación automática sin opt-in (rompe la promesa "zero deps").
- Configuración avanzada del MCP (timeout, índice inicial, paths custom, etc.).
- Auto-update del binario.
- Verificación de que el binario funciona (probar `codebase-memory-mcp --help` después de instalar).
- Manejo de errores de red durante `curl` (si falla, fallback a mensaje "reintentá manualmente").
- Integración con `find-skills` para ofrecer el MCP como skill comunitaria — codebase-memory-mcp no es una skill, es un binario externo.
- Tests automatizados del init (el init es un agente conversacional, no un script bash testeable).
