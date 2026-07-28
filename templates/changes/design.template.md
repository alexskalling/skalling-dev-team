# Design: [Nombre de la feature]

> **Status**: Draft | Approved | In Progress
> **Decisiones**: con rationale y alternativas consideradas

---

## Arquitectura

### Diagrama de componentes

```
[Cliente]
   ↓ HTTP
[API Gateway]
   ↓
[Auth Service] ← → [User DB]
   ↓
[Token Store]
```

### Diagrama de flujo (sequence)

```
User → API: POST /login {email, password}
API → Auth Service: validate(email, password)
Auth Service → User DB: SELECT * FROM users WHERE email=?
User DB → Auth Service: user record
Auth Service → Token Store: createJWT(user.id, exp=24h)
Token Store → Auth Service: jwt
Auth Service → API: {token, user}
API → User: 200 {token, user}
```

---

## Decisiones Arquitectónicas (ADRs)

### ADR-001: JWT vs sesiones server-side

**Contexto**: Necesitamos autenticar requests. Dos opciones: JWT stateless o sesiones server-side.

**Decisión**: JWT con refresh token.

**Rationale**:
- Stateless escala horizontalmente sin sticky sessions.
- Refresh token permite revocación sin cambiar arquitectura.
- Compatible con microservicios y mobile clients.

**Alternativas consideradas**:
- Sesiones server-side con Redis: más fácil de revocar, pero requiere Redis como dependencia crítica.
- OAuth2 puro: over-engineering para nuestro caso (no third-party).

**Consecuencias**:
- (+) Sin estado en el servidor.
- (+) Funciona para mobile clients naturalmente.
- (-) Refresh token rotation requiere lógica adicional.
- (-) No se puede revocar JWT antes de expiración sin lista negra.

### ADR-002: bcrypt factor 12 vs argon2

**Decisión**: bcrypt factor 12.

**Rationale**:
- Battle-tested (20+ años).
- Ampliamente entendido.
- Suficientemente lento para passwords (factor 12 = ~250ms).
- Librerías maduras en todos los lenguajes.

**Alternativas consideradas**:
- argon2id: técnicamente superior pero menos adopción.
- scrypt: bien pero menos battle-tested.

**Consecuencias**:
- (+) Compatibilidad universal.
- (-) No es memory-hard (vulnerable a GPU attacks si escala).

---

## Modelo de Datos

### User

```typescript
interface Usuario {
  id: string;              // UUID v4
  email: string;           // único, lowercase
  password_hash: string;   // bcrypt
  created_at: Date;
  updated_at: Date;
  last_login_at: Date | null;
  failed_attempts: number; // contador
  locked_until: Date | null;
}
```

### Token

```typescript
interface Token {
  jti: string;             // UUID, identificador único
  usuario_id: string;
  type: 'access' | 'refresh';
  expires_at: Date;
  revoked_at: Date | null;
}
```

---

## Patrones aplicados

### Clean Architecture (capas)

```
domain/         # User entity, AuthError, sin dependencias
application/    # LoginUseCase, ValidateCredentialsUseCase
infrastructure/ # BcryptHasher, JwtTokenStore, PostgresUserRepo
ui/             # /api/auth/login route handler
```

### Dependency Rule
- `domain/` no importa nada.
- `application/` solo importa `domain/`.
- `infrastructure/` importa `application/` y `domain/`.
- `ui/` importa `application/` (no `infrastructure/` directo).

---

## Seguridad

- **OWASP Top 10**: A01 (broken access control), A02 (cryptographic failures), A07 (auth failures) cubiertos.
- **Rate limiting**: 5 intentos por minuto por IP (SHOULD).
- **Account lockout**: 10 intentos fallidos → lock 15 min (SHOULD).
- **Audit log**: cada login (success/fail) registrado con timestamp + IP + user agent.
- **Secret management**: JWT_SECRET desde env var, nunca hardcoded.

---

## Testing Strategy

- **Unit tests**: LoginUseCase, ValidateCredentialsUseCase, BcryptHasher (con mocks).
- **Integration tests**: repo + DB real (testcontainers).
- **E2E tests**: flujo completo via API.
- **Coverage target**: 85% en `application/`, 70% global.

---

## Riesgos conocidos

1. **JWT no revocable fácilmente**: mitigación con refresh token rotation + blacklist.
2. **bcrypt factor 12 vulnerable a GPU**: aceptable por ahora (no high-value targets), revisit en 6 meses.
3. **Lockout DoS**: attacker puede lockear cuentas. Mitigación: lockout por IP, no por account.

---

## Out of design (explícitamente NO incluido)

- Single sign-on (SSO)
- Multi-factor authentication (MFA)
- Password recovery flow
- Email verification
- Captcha / bot protection
