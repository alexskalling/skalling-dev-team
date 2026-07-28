---
name: skalling-handoff
description: Write and validate JSON handoffs between Skalling agents. Trigger: handing off work to another agent, receiving a handoff, validating handoff schema.
---

# Skalling Handoff Protocol

Every agent-to-agent transition in Skalling uses a structured JSON handoff. This skill teaches the schema and how to use it.

## When to Use This Skill

- You're about to hand off work to another agent (Teo → Jhon, Jhon → Luz, etc.).
- You received a handoff and need to validate it.
- You need to debug a cycle that broke at the handoff stage.

## Minimal Handoff (always required)

```json
{
  "from": "TEO",
  "to": "JHON",
  "task": "Verificar tests del módulo auth",
  "summary": "Implementado LoginUseCase con TDD. 8 tests verdes.",
  "next_action": "Ejecutar suite de regresión"
}
```

## Full Handoff (recommended)

```json
{
  "from": "TEO",
  "to": "JHON",
  "task": "Verificar tests módulo auth/login",
  "summary": "Implementado LoginUseCase con TDD. 8 tests pasan, 0 fallan.",
  "artifacts": [
    "/src/auth/application/login.ts",
    "/tests/auth/application/login.test.ts"
  ],
  "tests_passed": true,
  "coverage": 92,
  "ladder_rung_used": 4,
  "ladder_reason": "Usé bcrypt porque stdlib no tiene hashing seguro de passwords",
  "next_action": "Ejecutar suite de regresión del módulo completo",
  "timestamp": "2026-07-28T16:30:00Z"
}
```

## Approval Handoff (Jhon → Luz, Luz → Pau)

```json
{
  "from": "JHON",
  "to": "LUZ",
  "task": "Auditoría final del plan auth",
  "summary": "Regresión completa en verde. 22 tests, coverage 87%.",
  "tests_passed": true,
  "coverage": 87,
  "verdict": "APPROVED",
  "next_action": "Auditar clean code + seguridad + Impeccable (frontend)"
}
```

## Rejection Handoff

```json
{
  "from": "JHON",
  "to": "TEO",
  "task": "Corregir tests antes de avanzar",
  "summary": "Tests del módulo auth fallan en edge cases.",
  "verdict": "REJECTED",
  "rejection_reasons": [
    "Test 'login con email vacío' no existe",
    "Test 'login con password > 100 chars' no existe",
    "Coverage de LoginUseCase es 72% (objetivo 85%)"
  ],
  "next_action": "Agregar 3 tests faltantes, corregir coverage, re-handoff"
}
```

## Validation (how to verify a handoff)

The full schema is at `templates/handoff.schema.json`. Required fields:
- `from`, `to` (agent names in {ALEX, POL, JES, SOL, TEO, JHON, LUZ, PAU})
- `task`, `summary` (non-empty strings)
- `next_action` (non-empty string)

Optional but recommended:
- `artifacts` (array of file paths)
- `tests_passed`, `coverage` (when work involved tests)
- `ladder_rung_used`, `ladder_reason` (when work involved implementation)
- `verdict`, `rejection_reasons` (for approval gates)

## Common Mistakes

- ❌ Missing `next_action` — the receiving agent doesn't know what to do.
- ❌ Empty `summary` — no context for the receiving agent.
- ❌ Handing off with `tests_passed: true` but no actual test run.
- ❌ Skipping `ladder_reason` when rung is 1-3 (lazy choices need justification).
- ❌ Self-handoff (TEO → TEO) — never happens, always different agents.

## Validation Tools

To validate against schema:
```bash
# If you have Python with jsonschema
python3 -c "
import json, jsonschema
schema = json.load(open('templates/handoff.schema.json'))
data = json.load(open('my-handoff.json'))
jsonschema.validate(data, schema)
print('valid')
"
```

Or use any JSON Schema validator (ajv, jsonschema, etc.).
