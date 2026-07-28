# Tasks: [Nombre de la feature]

> **Granularidad**: cada tarea ejecutable en 2-5 minutos de implementación.
> **Agrupación**: por fase (infraestructura, implementación, testing).
> **Numeración**: jerárquica (1.1, 1.2, 2.1).
> **TDD**: cada tarea de implementación tiene su test correspondiente.

---

## Fase 1: Infraestructura

> Setup de la base — sin lógica de negocio todavía.

- [ ] **1.1** Crear migración de tabla `usuarios`
  - Archivo: `database/migrations/20260728_create_usuarios.sql`
  - Valida con Jhon ✓

- [ ] **1.2** Crear migración de tabla `tokens`
  - Archivo: `database/migrations/20260728_create_tokens.sql`
  - Valida con Jhon ✓

- [ ] **1.3** Setup de conexión a DB en módulo auth
  - Archivo: `src/auth/infrastructure/db.ts`
  - Test: `tests/auth/infrastructure/db.test.ts`
  - **RED primero**, luego GREEN
  - Valida con Jhon ✓

- [ ] **1.4** Setup de JWT secret management
  - Archivo: `src/auth/infrastructure/jwt-config.ts`
  - Lee de `process.env.JWT_SECRET`
  - Test: `tests/auth/infrastructure/jwt-config.test.ts`
  - Valida con Jhon ✓

---

## Fase 2: Dominio (entities + value objects)

> Lógica pura, sin dependencias externas.

- [ ] **2.1** Crear entity `Usuario`
  - Archivo: `src/auth/domain/usuario.ts`
  - Validaciones: email formato, password >= 8 chars
  - Test: `tests/auth/domain/usuario.test.ts`
  - Valida con Jhon ✓

- [ ] **2.2** Crear value object `Email`
  - Archivo: `src/auth/domain/email.ts`
  - Normaliza a lowercase, valida formato
  - Test: `tests/auth/domain/email.test.ts`
  - Valida con Jhon ✓

- [ ] **2.3** Crear value object `Password`
  - Archivo: `src/auth/domain/password.ts`
  - Hashea con bcrypt al construir, valida longitud
  - Test: `tests/auth/domain/password.test.ts`
  - Valida con Jhon ✓

- [ ] **2.4** Crear error types (`AuthError`, `InvalidCredentialsError`, `UserAlreadyExistsError`)
  - Archivo: `src/auth/domain/errors.ts`
  - Test: `tests/auth/domain/errors.test.ts`
  - Valida con Jhon ✓

---

## Fase 3: Application (use cases)

> Orquestación de la lógica de dominio.

- [ ] **3.1** Implementar `LoginUseCase`
  - Archivo: `src/auth/application/login.ts`
  - Inputs: email, password
  - Outputs: { token, user } | AuthError
  - Test: `tests/auth/application/login.test.ts` (con mocks de repo y hasher)
  - Cubre todos los escenarios de specs/specs.md
  - Valida con Jhon ✓

- [ ] **3.2** Implementar `ValidateTokenUseCase`
  - Archivo: `src/auth/application/validate-token.ts`
  - Inputs: jwt string
  - Outputs: user_id | AuthError
  - Test: `tests/auth/application/validate-token.test.ts`
  - Valida con Jhon ✓

- [ ] **3.3** Implementar `LogoutUseCase` (revoca refresh token)
  - Archivo: `src/auth/application/logout.ts`
  - Test: `tests/auth/application/logout.test.ts`
  - Valida con Jhon ✓

---

## Fase 4: Infrastructure (adapters)

> Implementaciones concretas de las interfaces.

- [ ] **4.1** Implementar `PostgresUserRepository`
  - Archivo: `src/auth/infrastructure/postgres-user-repo.ts`
  - Implementa interface `UserRepository`
  - Test integración: `tests/auth/integration/postgres-user-repo.test.ts` (con testcontainers)
  - Valida con Jhon ✓

- [ ] **4.2** Implementar `BcryptHasher`
  - Archivo: `src/auth/infrastructure/bcrypt-hasher.ts`
  - Implementa interface `PasswordHasher`
  - Test: `tests/auth/infrastructure/bcrypt-hasher.test.ts`
  - Valida con Jhon ✓

- [ ] **4.3** Implementar `JwtTokenStore`
  - Archivo: `src/auth/infrastructure/jwt-token-store.ts`
  - Implementa interface `TokenStore`
  - Test: `tests/auth/infrastructure/jwt-token-store.test.ts`
  - Valida con Jhon ✓

---

## Fase 5: UI / API (ruta HTTP)

> Capa de presentación.

- [ ] **5.1** Implementar route handler `POST /api/auth/login`
  - Archivo: `src/app/api/auth/login/route.ts` (Next.js App Router)
  - Input validation con Zod
  - Mapea errores a HTTP status codes correctos
  - Test E2E: `tests/e2e/auth/login.test.ts`
  - Valida con Jhon ✓

- [ ] **5.2** Implementar middleware de auth
  - Archivo: `src/middleware.ts` (Next.js middleware)
  - Valida JWT en requests
  - Adjunta `user` al request
  - Test: `tests/middleware/auth.test.ts`
  - Valida con Jhon ✓

---

## Fase 6: Cross-cutting (logging, errors, security)

> Concerns transversales.

- [ ] **6.1** Audit log para eventos de auth
  - Archivo: `src/auth/infrastructure/audit-log.ts`
  - Registra: login success, login fail, token revoked
  - Test: `tests/auth/infrastructure/audit-log.test.ts`
  - Valida con Jhon ✓

- [ ] **6.2** Rate limiter (SHOULD de specs)
  - Archivo: `src/auth/infrastructure/rate-limiter.ts`
  - 5 intentos/minuto por IP
  - Test: `tests/auth/infrastructure/rate-limiter.test.ts`
  - Valida con Jhon ✓

- [ ] **6.3** Account lockout (SHOULD de specs)
  - Archivo: `src/auth/application/lock-account.ts`
  - Después de 10 intentos fallidos → lock 15 min
  - Test: `tests/auth/application/lock-account.test.ts`
  - Valida con Jhon ✓

---

## Fase 7: Validación final

- [ ] **7.1** Regresión completa: suite completa del proyecto en verde
  - `npm test`
  - Coverage >= 85% en `application/`, >= 70% global
  - Handoff a Jhon para regresión completa

- [ ] **7.2** Auditoría Luz: corre `npx impeccable detect src/` (si frontend) + análisis estático
  - 0 findings críticos
  - Handoff a Pau

- [ ] **7.3** Documentación Pau
  - Actualizar `docs/api/auth.md` con nuevos endpoints
  - Actualizar `.opencode/context/decisiones/` con ADRs de design.md
  - Crear changelog entry

---

## Estimación (opcional)

| Fase | Tareas | Tiempo estimado |
|---|---|---|
| 1: Infraestructura | 4 | ~30 min |
| 2: Dominio | 4 | ~45 min |
| 3: Application | 3 | ~1h |
| 4: Infrastructure | 3 | ~1h |
| 5: UI/API | 2 | ~30 min |
| 6: Cross-cutting | 3 | ~1h |
| 7: Validación | 3 | ~30 min |
| **Total** | **22** | **~5h** |

---

## Reglas de ejecución

1. **TDD obligatorio**: RED primero, GREEN después, REFACTOR al final de cada tarea.
2. **Valida con Jhon** después de cada tarea (no solo al final de fase).
3. **Una tarea a la vez**: no avances a la siguiente sin aprobación.
4. **Handoff JSON**: cada entrega a Jhon usa el formato de constitución.
5. **Ladder de Ponytail**: cada implementación pasa por la escalera (stdlib > native > deps > custom).
