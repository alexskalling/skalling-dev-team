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

The single source of truth for the cycle is the TeamDB (`<project>/.opencode/context/team.db`, tables `proposals` → `plans` → `tasks` + `task_claims`). Agents pass DB identifiers (`slug`, `plan_id`, `task`) between phases, never file paths. Markdown under `.opencode/changes/<feature>/` is only a human-readable export regenerated with `teamdb-export-md.sh` — never the source.

### Phase 1 — Pol (spec author)
- Interrogates the user with questions-one-at-a-time.
- Registers the proposal in the `proposals` table (slug, title, intent_md, status=`draft`, agent=`pol`) and validates with the user.
- NEVER advances without explicit user confirmation.

### Phase 2 — Sol (planner)
- Receives the validated proposal by `slug` from Pol.
- Creates plan + design + tasks in ONE atomic pass with `teamdb-plan.sh <project> <slug> <title> <tasks.md> [--by=sol] [--purpose=<text>] [--acceptance=<text>]` (writes proposals/plans/tasks + DAG + plan_history).
- Adjusts the plan afterwards with `teamdb-amend.sh <plan-slug>` (add/modify/deprecate tasks).
- Does NOT handcraft `proposal.md`/`design.md`/`tasks.md`; exports are regenerated from the DB.

### Phase 3 — Teo (implementer) ↔ Jhon (test verifier)
- Teo claims each `pending` task with `teamdb-claim.sh <plan-slug> <task-slug> --actor=teo [project]` (CAS + lease).
- Executes each task with TDD: RED → GREEN → REFACTOR.
- Teo releases the claim when done: `teamdb-claim.sh --release <claim-id> --status=done --by=teo [project]` → task moves to `in_review`.
- Jhon runs tests, validates coverage, then advances: `teamdb-claim.sh --advance <plan-slug> <task-slug> --to=approved --by=jhon [project]` and seals the evidence with `teamdb-seal-receipt.sh <task_id> <agent> [project]` (tree_hash).
- If Jhon rejects → back to Teo (release `--status=failed`). Max 3 iterations.
- Any agent can check state read-only with `teamdb-status.sh <plan-slug> [project]`.

### Phase 4 — Jhon (regression)
- When ALL tasks are `approved`: Jhon reads the plan state from the DB and runs the full regression suite.
- Only after full regression approval does Luz start.

### Phase 5 — Luz (auditor)
- ONE TIME per plan, after Jhon approves regression.
- Audits with read-only access: `teamdb-status.sh <plan-slug> [project]`, `teamdb-search.sh <query> <type>`, `teamdb_query_project` SELECTs. Never mutates the cycle.
- Static analysis, security, clean code audit.
- For frontend: runs `npx impeccable detect src/`.
- If rejects → back to Teo, then re-pass Jhon.

### Phase 6 — Pau (documentalist)
- ONE TIME per plan, after Luz passes.
- Updates `docs/` (public) and `.opencode/context/` (OKF bundle).
- Closes the final transition: `teamdb-claim.sh --advance <plan-slug> <task-slug> --to=resolved --by=pau [project]`.
- Actualiza design-system.md en OKF bundle si frontend.

## Fast-Track (when to skip)

Apply fast-track when:
- UI minor changes (color, text, spacing).
- Typo fixes or config tweaks.
- Single-line adjustments.

In fast-track: Alex → Teo directly. No Pol, no Sol, no plan.
Teo still applies TDD (test first) and the Ponytail ladder.

## Handoff Format

Every agent-to-agent transition uses a JSON handoff. See `skalling-handoff` skill for full schema. The handoff MUST carry DB identifiers (`plan_slug` / `task` / `claim_id`) — not markdown paths. Check the current state with `teamdb-status.sh <plan-slug> [project]` before handing off.

Minimal handoff:
```json
{
  "from": "TEO",
  "to": "JHON",
  "plan_slug": "auth-jwt",
  "task": "task-login-endpoint",
  "summary": "Implementado LoginUseCase. 8 tests verdes.",
  "artifacts": ["/src/auth/application/login.ts"],
  "tests_passed": true,
  "next_action": "Advance a approved con teamdb-claim.sh --advance y sellá el receipt"
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
Sol crea el plan de B en la DB (teamdb-plan.sh, slug distinto de A)
↓
Cuando A termina → Teo recibe el plan de B (por slug) con project_context
```

## What You (any agent) Should Never Do

- Skip the cycle without fast-track justification.
- Auto-respond (Pol especially — never answer your own question).
- Override another agent's decision.
- Close the cycle without all approvals.
- Invoke Pau directly (always goes through Luz).
- Mutate cycle tables (`proposals`/`plans`/`tasks`) with raw SQL when a cycle script exists — use `teamdb-plan.sh`, `teamdb-amend.sh`, `teamdb-claim.sh`, `teamdb-seal-receipt.sh`.
- Derivar a Teo/Luz sin project_context en el handoff (causa: Teo responde vacío).
