# Specs: [Nombre de la feature]

> **Status**: Draft | Approved | In Progress | Completed
> **RFC 2119 keywords**: MUST / SHALL / SHOULD / MAY
> **Format**: Given/When/Then (Behavior-Driven Development)

---

## Escenario 1: [Nombre descriptivo]

**Given** [contexto inicial — qué condición previa existe]
**When** [acción — qué trigger ocurre o qué hace el usuario]
**Then** [resultado esperado — qué debe pasar]

**Y** [resultado adicional 1, opcional]
**Y** [resultado adicional 2, opcional]

---

## Escenario 2: [Otro escenario]

**Given** [contexto]
**When** [acción]
**Then** [resultado]

---

## Escenario N: [Edge case o error]

**Given** [contexto de error]
**When** [acción que dispara el error]
**Then** [resultado de error manejado correctamente — NO panic, NO silent fail]

---

## Reglas MUST (obligatorias)

1. El sistema **MUST** validar que el email sea válido antes de crear el usuario.
2. El sistema **MUST** hashear la contraseña con bcrypt (factor 12).
3. El sistema **MUST** rechazar emails duplicados con error específico.
4. El sistema **MUST** devolver error 401 en credenciales inválidas, NO 500.
5. El sistema **MUST** registrar el intento de login en audit log (éxito y fallo).

## Reglas SHOULD (recomendadas)

1. El sistema **SHOULD** rate-limitar a 5 intentos por minuto por IP.
2. El sistema **SHOULD** bloquear cuenta después de 10 intentos fallidos consecutivos.
3. Los mensajes de error **SHOULD** ser genéricos ("credenciales inválidas") para no filtrar si el email existe.

## Reglas MAY (opcionales)

1. El sistema **MAY** enviar email de notificación en login desde IP nueva.
2. El sistema **MAY** soportar 2FA en el futuro.

---

## Criterios de Aceptación (resumen)

- [ ] Escenario 1 pasa
- [ ] Escenario 2 pasa
- [ ] Escenario N pasa
- [ ] Todas las reglas MUST tienen test
- [ ] Las reglas SHOULD tienen test si están implementadas
- [ ] No hay reglas MUST sin test correspondiente

---

## Out of Spec (explícitamente NO incluido)

- Recuperación de contraseña por email (se hace en otro change)
- SSO / OAuth (no es alcance de este change)
- Multi-factor authentication (es otro change)
- Rate limiting distribuido (solo local por ahora)
