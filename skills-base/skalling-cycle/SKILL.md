---
name: skalling-cycle
description: How the Skalling cycle works — when each agent activates, what handoffs look like, when to use fast-track vs full cycle. Trigger: starting work, unclear which agent to invoke, planning a feature.
---

# Skalling Cycle

The Skalling cycle is a disciplined handoff between 8 agents. This skill teaches you (any agent) how to navigate it correctly.

## When to Use This Skill

Load this skill when:
- You're about to start work on a feature and don't know which agent does what.
- You're an agent receiving a handoff and need to understand the cycle.
- The user asks "who does X" or "what's the next step".
- You're in the middle of a cycle and need to validate the phase.

## The Cycle (canonical order)

```
Usuario → Alex → Pol → Sol → Teo ↔ Jhon (per task)
                                ↓ (regresión completa)
                              Jhon → Luz → Pau
```

### Phase 0 — Alex (intent classification)
- Classifies the user's intent (Aprender / Construir / Fix / Estado).
- Routes to the right entry point.
- **Fast-track** for trivial changes (skip Pol, Sol).

### Phase 1 — Pol (spec author)
- Interrogates the user with questions-one-at-a-time.
- Writes `proposal.md` and validates with user.
- NEVER advances without explicit user confirmation.

### Phase 2 — Sol (planner)
- Receives validated `proposal.md` from Pol.
- Writes `design.md` (architecture, ADRs).
- Writes `tasks.md` (granular breakdown).
- Saves to `.opencode/changes/<feature>/`.

### Phase 3 — Teo (implementer) ↔ Jhon (test verifier)
- Teo executes each task with TDD: RED → GREEN → REFACTOR.
- For each task: Teo writes code + test, handoffs to Jhon.
- Jhon runs tests, validates coverage, approves or rejects.
- If Jhon rejects → back to Teo. Max 3 iterations.

### Phase 4 — Jhon (regression)
- When ALL tasks complete: Jhon runs full regression suite.
- Only after full regression approval does Luz start.

### Phase 5 — Luz (auditor)
- ONE TIME per plan, after Jhon approves regression.
- Static analysis, security, clean code audit.
- For frontend: runs `npx impeccable detect src/`.
- If rejects → back to Teo, then re-pass Jhon.

### Phase 6 — Pau (documentalist)
- ONE TIME per plan, after Luz passes.
- Updates `docs/` (public) and `.opencode/context/` (OKF bundle).
- Actualiza design-system.md en OKF bundle si frontend.

## Fast-Track (when to skip)

Apply fast-track when:
- UI minor changes (color, text, spacing).
- Typo fixes or config tweaks.
- Single-line adjustments.

In fast-track: Alex → Teo directly. No Pol, no Sol, no plan.
Teo still applies TDD (test first) and the Ponytail ladder.

## Handoff Format

Every agent-to-agent transition uses a JSON handoff. See `skalling-handoff` skill for full schema.

Minimal handoff:
```json
{
  "from": "TEO",
  "to": "JHON",
  "task": "Verificar tests del módulo auth",
  "summary": "Implementado LoginUseCase. 8 tests verdes.",
  "artifacts": ["/src/auth/application/login.ts"],
  "tests_passed": true,
  "next_action": "Ejecutar suite de regresión completa"
}
```

## Iteration Limits

| Phase | Max iterations |
|---|---|
| Teo ↔ Jhon | 3 |
| Jhon (regression) ↔ Luz | 3 |
| Luz ↔ Pau | 2 |

If exhausted, Alex notifies user with options.

## Pipeline Mode (Parallelization)

**Para acelerar desarrollos, Sol puede planificar la SIGUIENTE feature mientras Teo ejecuta la actual.**

```
Fase 3 (Teo↔Jhon)     Fase 2 (Sol planificando)
─────────────────     ─────────────────────────
Tarea 1 → Jhon        Sol recibe proposal de Pol
Tarea 2 → ...         Sol escribe design/tasks
Tarea 3 → ...
```

**Reglas del Pipeline:**
1. Sol puede planificar `feature_N+1` mientras Teo ejecuta `feature_N`
2. Alex activa a Sol para siguiente feature SOLO si:
   - Teo está en fase 3 o superior (ya pasó Sol para feature actual)
   - Pol ya validó el proposal de la siguiente feature
3. El pipeline NO salta fases — cada feature sigue: Pol → Sol → Teo ↔ Jhon → Luz → Pau
4. Teo recibe el plan completo de Sol con project_context antes de empezar

**Activación del pipeline:**
```
Usuario pide "feature B" mientras "feature A" está en desarrollo
↓
Alex detecta: Teo ocupado en A, Pol idle
↓
Alex invoca a Pol para validar feature B (si no está validado)
↓
Pol valida → Alex invoca a Sol para planear B
↓
Sol planifica B → guarda en .opencode/changes/feature-b/
↓
Cuando A termina → Teo recibe plan de B con project_context
```

## What You (any agent) Should Never Do

- Skip the cycle without fast-track justification.
- Auto-respond (Pol especially — never answer your own question).
- Override another agent's decision.
- Close the cycle without all approvals.
- Invoke Pau directly (always goes through Luz).
- Derivar a Teo/Luz sin project_context en el handoff (causa: Teo responde vacío).
