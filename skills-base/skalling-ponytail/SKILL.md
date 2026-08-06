---
name: skalling-ponytail
description: Apply the Ponytail ladder before writing any code — lazy about solution, never about reading. Trigger: Teo about to implement, Jhon reviewing, Luz auditing, code complexity check.
---

# Skalling Ponytail Integration

The Ponytail ladder is a 7-step decision framework that prevents over-engineering. It's a **constitution rule (R15)** in Skalling. This skill makes it actionable.

## When to Activate

- **Teo** is about to write code → load before implementing.
- **Jhon** is reviewing code → apply to detect over-engineering.
- **Luz** is auditing → apply for code quality issues.
- **User says**: "less code", "simplify", "is this necessary", "YAGNI", "KISS".

## The Ladder

Run through these 7 rungs. **Stop at the first one that holds**.

```
1. ¿Necesita existir?               → NO: skip (YAGNI)
2. ¿Ya está en este codebase?       → SÍ: reusar, no reescribir
3. ¿Stdlib lo hace?                 → SÍ: usarlo
4. ¿Feature nativa de la plataforma? → SÍ: usarla
5. ¿Dependencia ya instalada?       → SÍ: usarla
6. ¿Una línea?                      → SÍ: una línea
7. Recién entonces: el mínimo que funcione
```

## Lazy about Solution, Never about Reading

**Reading before writing** is non-negotiable. Before picking a rung:

1. Read the code this change touches.
2. Trace the real flow of data.
3. Identify what exists, what's used, what can be reused.
4. Only then: apply the ladder.

## How to Apply (Teo)

Before writing each task:

```markdown
## Ladder check for [task name]

**Read first**: What does the code currently do? [1-2 sentence trace]

**Rung 1**: Does this need to exist?
  → [Yes/No, why]

**Rung 2**: Is there code in this codebase that already does this?
  → [Yes/No, what to reuse]

**Rung 3**: Does stdlib do this?
  → [Yes/No, what to use]

**Rung 4**: Is there a native platform feature?
  → [Yes/No, what to use]

**Rung 5**: Is there an installed dependency?
  → [Yes/No, what to use]

**Rung 6**: Can this be one line?
  → [Yes/No, the line]

**Rung 7**: Only now: the minimum that works.
  → [Final approach]

**Trust boundaries preserved**:
- Validation: [yes/no, how]
- Error handling: [yes/no, how]
- Security: [yes/no, how]
- Accessibility (if UI): [yes/no, how]
```

## How to Apply (Jhon)

When reviewing a PR or task:

1. For each new function or feature: ask "which rung of the ladder?"
2. If Teo picked rung 7 but rung 3 would have worked → reject with: "Reimplement using stdlib. Rung 3 applies here."
3. If Teo created a new abstraction for one use → reject: "YAGNI. Inline it."
4. If Teo added config for something that has a sensible default → reject: "Use the default."

## How to Apply (Luz)

In Quality Gate audit:

- LOC count inflated without justification → reject.
- New dependencies added that aren't used elsewhere → reject.
- Abstractions with single implementations → reject.
- Hand-rolled solutions to solved problems → reject.

**Always cite the rung**: "Rechazado. Rung 3 aplica: stdlib lo hace en X líneas."

## Anti-Patterns Explicitly Banned

| Anti-pattern | Rung violated | Fix |
|---|---|---|
| Install flatpickr for date picker | 4 (native `<input type="date">`) | Use native |
| Custom UUID generation library | 3 (stdlib `crypto.randomUUID()`) | Use stdlib |
| Re-implement debounce | 3 (lodash is already installed) | Use existing |
| New abstraction for one use | 1 (YAGNI) | Inline |
| Add config for default value | 1 (YAGNI) | Hardcode default |
| Write tests for unused function | 7 (shouldn't exist) | Delete function |

## Examples

### Good (rung 4 — native)

User: "Add a date picker to the form."

```typescript
// Teo picked rung 4
<input type="date" name="fecha" />

// NOT: install flatpickr, write wrapper component, add stylesheet, discuss timezones.
```

### Good (rung 6 — one line)

User: "Generate a unique ID for this entity."

```typescript
const id = crypto.randomUUID();
// NOT: install uuid library, write generator class, add config.
```

### Bad (rung 7 — full custom when rung 3 would do)

User: "Parse this JSON safely."

```typescript
// BAD: hand-rolled parser
function parsearJsonSeguro<T>(input: string): T | null {
  // 20 lines of try/catch with custom error handling
}

// GOOD: rung 3, stdlib
const data = JSON.parse(input) as Schema;
if (!Schema.safeParse(data).success) throw new ValidationError();
```

## Trade-offs Accepted

Ponytail can:
- Make code harder to extend later (rung 1 sacrifices flexibility).
- Force explicit error handling over silent defaults.

These are **features, not bugs**. Extension is rarely needed; explicit error handling is a constitution rule (R10).

## Failure Mode

If you apply the ladder and end up at rung 7 with significant custom code, **question the requirement**. Maybe rung 1 says "skip it entirely". If the user really wants rung 7, you build it slowly and correctly. But you confirm.

## References

- Original: https://github.com/DietrichGebert/ponytail
- Constitution: R15 — Escalera de Ponytail
- Companion skills: `skalling-cycle` (when to apply), `skalling-impeccable-bridge` (UI-specific).
