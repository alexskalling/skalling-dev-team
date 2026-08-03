---
name: skalling-routing
description: "Trigger: routing, fast-track, direct, sdd, plan, scope, complexity. Determinates the implementation route based on scope and complexity."
license: MIT
metadata:
  author: skalling-team
  version: "1.0"
---

# Skalling Routing — Organic Implementation Routing

## Activation Triggers

Load when:
- User requests a change
- Unclear which route applies
- Scope ambiguity exists
- "cómo hago esto", "rápido", "simple", "complejo", "plan"

## Hard Rules

1. **Never skip phases without justification.** Fast-track requires explicit scope justification.
2. **Routing decision is final for this request.** Don't re-evaluate mid-implementation.
3. **Scope never grows silently.** If scope increases, re-evaluate routing.
4. **Every route produces a receipt.** No exceptions.

## Decision Gates

| Condition | Route |
| --- | --- |
| 1-3 files, clear scope, understood | **INLINE** — Alex → Teo directly |
| 4+ files, multiple concepts, ambiguous | **SDD** — Full cycle: Pol → Sol → Teo |
| Bug fix, isolated, reproducible | **INTERVENTION** — Alex → Teo (surgical) |
| UI trivial (color, text, spacing) | **FAST-TRACK** — Alex → Teo (no plan) |
| Security/audit request | **DIRECT** — Alex → Luz (skip all) |
| Understanding/research | **RESEARCH** — Alex → Jes |

## Route Definitions

### INLINE Route

**When:** 1-3 files, clear scope, understood.

```
Usuario → Alex → Teo (direct)
Teo: TDD mínimo, 1-2 tests, implementación
Teo → Alex: "Hecho. Receipt: [resumen]"
```

**Receipt format:**
```json
{
  "route": "INLINE",
  "files": ["src/auth/login.ts"],
  "tests": "2 passing",
  "verification": "bun test src/auth/login.test.ts ✓"
}
```

### INTERVENTION Route (Bug Fix)

**When:** Bug aislado, reproducible, scope conocido.

```
Usuario → Alex → Teo (direct, surgical mode)
Teo: RED (test que reproduce) → GREEN (fix) → REFACTOR
Teo → Alex: "Bug corregido. Receipt: [bug + fix + test]"
```

**Receipt format:**
```json
{
  "route": "INTERVENTION",
  "bug": "descripción del bug",
  "fix": "cómo se arregló",
  "test": "test de regresión agregado",
  "verification": "bun test ✓"
}
```

### FAST-TRACK Route

**When:** UI trivial, typo, config, single line.

```
Usuario → Alex → Teo (no plan, no SDD)
Teo: implementación directa, minimal test
```

**Restrictions:**
- No SDD artifacts
- No Pol/Sol
- Max 1 archivo modificado
- Test opcional (si hay regression risk)

### SDD Route (Full Cycle)

**When:** 4+ files, ambiguous scope, new feature, architectural decision.

```
Usuario → Alex → Pol → Sol → Teo ↔ Jhon → Luz → Pau
```

**Stages:**
1. **Pol:** Questions → proposal.md
2. **Sol:** design.md + tasks.md → `.opencode/changes/<slug>/`
3. **Teo:** RED → GREEN → REFACTOR per task
4. **Jhon:** Per-task verification + regression
5. **Luz:** Quality gate
6. **Pau:** Documentation

**Receipt format:**
```json
{
  "route": "SDD",
  "slug": "auth-jwt",
  "tasks": ["task 1.1", "task 1.2", "task 2.1"],
  "coverage": 87,
  "verdict": "PASSED",
  "artifacts": [".opencode/changes/auth-jwt/"]
}
```

### RESEARCH Route

**When:** Learning, investigation, concept clarification.

```
Usuario → Alex → Jes
Jes: Investigate → Explain at requested level
```

---

## Scope Decision Tree

```
START: User request received
  │
  ├─► "¿Es aprendizaje/investigación?"
  │     └─► YES → RESEARCH Route (Jes)
  │
  ├─► "¿Es auditoría/seguridad?"
  │     └─► YES → DIRECT Route (Luz)
  │
  ├─► "¿Bug aislado, reproducible?"
  │     └─► YES → INTERVENTION Route (Teo surgical)
  │
  ├─► "¿Cambio trivial? (UI, typo, config)"
  │     └─► YES → FAST-TRACK Route (Teo, no plan)
  │
  ├─► "¿1-3 archivos, scope claro?"
  │     └─► YES → INLINE Route (Teo direct)
  │
  └─► "¿4+ archivos, scope ambiguo?"
          └─► YES → SDD Route (Pol → Sol → Teo)
```

---

## Routing Anti-Patterns

| Anti-pattern | Detection | Correct Route |
|---|---|---|
| Calling SDD for 1 file | Scope creep | INLINE |
| INLINE for 10 files | Under-scoping | SDD |
| Fast-track for new feature | No validation | SDD |
| Research for bug fix | Wrong route | INTERVENTION |

---

## Output Contract

When routing is complete, return:

```json
{
  "route": "INLINE|INTERVENTION|FAST-TRACK|SDD|DIRECT|RESEARCH",
  "scope": "1-3 files" | "bug fix" | "trivial" | "complex",
  "agents": ["Alex", "Teo"],
  "skip_phases": ["Pol", "Sol"] | [],
  "receipt_required": true
}
```

---

## Triggers para re-evaluación

Re-evaluate routing if:
- Scope increases by 50%+
- New files discovered mid-implementation
- User changes requirements
- 3+ rejections in a row

---

## Examples

**Example 1: "Arreglá el bug del login"**
```
→ INTERVENTION Route
→ Teo surgical mode
→ Receipt: {bug: "login returns 500", fix: "middleware order"}
```

**Example 2: "Cambiá el color del botón a rojo"**
```
→ FAST-TRACK Route
→ Teo direct
→ Receipt: {file: "components/Button.css", change: "background: red"}
```

**Example 3: "Implementá auth con JWT"**
```
→ SDD Route
→ Pol → Sol → Teo → Jhon → Luz → Pau
→ Receipt: {slug: "auth-jwt", coverage: 87, verdict: "PASSED"}
```

**Example 4: "Explicame cómo funciona el auth"**
```
→ RESEARCH Route
→ Jes
→ No receipt required
```
