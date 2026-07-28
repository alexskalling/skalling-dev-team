---
name: skalling-impeccable-bridge
description: Bridge between Skalling and the Impeccable frontend design skill. Trigger: Teo working on UI components, Luz auditing visual changes, user asks for /polish /impeccable /audit /typeset /distill, project has a DESIGN.md and UI is being touched.
---

# Skalling Impeccable Bridge

This skill is the Skalling wrapper for [Impeccable](https://impeccable.style/), the frontend design skill that detects AI slop and applies design vocabulary.

## When to Activate

- **Teo is creating/modifying UI components** → load this before touching code.
- **Luz is auditing changes with visual impact** → load this for the audit.
- **User says**: `/polish`, `/impeccable`, `/audit`, `/typeset`, `/distill`, `/colorize`, "improve the design", "remove AI tells", "this looks generic".
- **Project has a `docs/design/DESIGN.md`** and UI files are being touched.

## What to Do

### Step 1 — Verify Impeccable is installed

```bash
# Check if Impeccable is installed
ls ~/.config/opencode/skills/impeccable/ 2>/dev/null || \
ls node_modules/impeccable/ 2>/dev/null || \
ls .opencode/skills/impeccable/ 2>/dev/null

# If not installed:
npx impeccable install
```

If install fails (no Node 22+, no network), **degrade gracefully**: continue with Skalling's own design checks, notify user that Impeccable is unavailable.

### Step 2 — Read context from OKF bundle

Before activating any Impeccable command, read:

```yaml
# From .opencode/context/proyecto/que-es.md
- What is this project?
- Who is the audience?

# From .opencode/context/proyecto/publico-objetivo.md (if exists)
- Who uses this UI?

# From docs/design/DESIGN.md (if exists)
- Existing design tokens, components, conventions.

# From .opencode/context/preferencias/*.md
- Team preferences about UI.
```

### Step 3 — Activate the right Impeccable command

| User intent | Impeccable command |
|---|---|
| "Se ve genérico" / "polish this" | `/impeccable polish` |
| "Tiene AI tells" / "remove slop" | `/impeccable audit` or `npx impeccable detect <src>` |
| "Tipografía rara" / "typeset" | `/impeccable typeset` |
| "Muy cargado" / "simplify" | `/impeccable distill` |
| "Colores mal" / "colorize" | `/impeccable colorize` |
| "Reescribilo en X modo" | `/impeccable <mode>` (see Impeccable docs) |

### Step 4 — Pass Skalling context to Impeccable

When invoking Impeccable, inject:
- The PRODUCT.md brief (or extract from `.opencode/context/proyecto/que-es.md`).
- The DESIGN.md rules (or note "no DESIGN.md exists — create one").
- The team's preferences from `.opencode/context/preferencias/`.

### Step 5 — Log + sync DESIGN.md

After Impeccable finishes:
1. Append to `.opencode/context/log.md` what was changed.
2. If `DESIGN.md` was created or modified by Impeccable:
   - Copy to `docs/design/DESIGN.md` (committed, source of truth).
   - Update `.opencode/context/proyecto/design-system.md` with summary + link.

## REGLA #13 — DESIGN.md enforcement

If the project has UI but no `docs/design/DESIGN.md`:

1. Tell the user: *"Detecté stack frontend pero no hay DESIGN.md. La constitución R13 lo exige."*
2. Suggest: *"¿Lo creo con Impeccable (`/impeccable document`) o desde el template manual?"*
3. If user agrees, run the creation and apply Impeccable afterwards.

## When NOT to Activate

- Project has no UI (backend, scripts, docs only).
- Impeccable already ran and there are no new visual changes.
- Task is purely backend (API, tests, infrastructure).
- User explicitly opts out.

## Anti-Patterns

- ❌ Don't use Impeccable commands blindly — match them to actual intent.
- ❌ Don't skip reading OKF context — Impeccable works better with product brief.
- ❌ Don't modify DESIGN.md without informing the user (it's the source of truth).
- ❌ Don't run Impeccable on non-UI code — it's wasted tokens.

## Degraded Mode (no Impeccable available)

If Impeccable can't be installed:

1. Notify user clearly: "Impeccable no disponible. Continúo sin detector automático de AI slop."
2. Apply Skalling's manual design checks:
   - Code is consistent with DESIGN.md (if exists).
   - No generic UI patterns (status-chip soup, italic serif h1, etc.).
   - Visual hierarchy clear.
3. Recommend user install Impeccable later for better coverage.
