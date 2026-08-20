---
name: skalling-impeccable-bridge
description: Bridge between Skalling and the Impeccable frontend design skill. Trigger: Teo working on UI components, Luz auditing visual changes, user asks for /polish /impeccable /audit /typeset /distill, project has a design-system.md in OKF bundle and UI is being touched.
---

# Skalling Impeccable Bridge

This skill is the Skalling wrapper for [Impeccable](https://impeccable.style/), the frontend design skill that detects AI slop and applies design vocabulary.

## When to Activate

- **Teo is creating/modifying UI components** → load this before touching code.
- **Luz is auditing changes with visual impact** → load this for the audit.
- **User says**: `/polish`, `/impeccable`, `/audit`, `/typeset`, `/distill`, `/colorize`, "improve the design", "remove AI tells", "this looks generic".
- **Project has a `design-system.md` en el bundle OKF** and UI files are being touched.

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

### Step 2 — Read context from DB (NOT .md files)

Before activating any Impeccable command, query the DB:

```bash
# Project concept (what is this project, audience)
teamdb_query_project "SELECT slug, title, body_md FROM concepts WHERE category IN ('proyecto', 'project', 'context') LIMIT 5"

# Design system (existing tokens, components)
teamdb_query_project "SELECT slug, title, body_md FROM concepts WHERE category='design-system' LIMIT 1"

# Team preferences about UI
teamdb_query_project "SELECT slug, title, body_md FROM preferences WHERE title LIKE '%ui%' OR title LIKE '%design%' OR title LIKE '%frontend%'"

# Target audience from decisions
teamdb_query_project "SELECT slug, title, body_md FROM decisions WHERE title LIKE '%audiencia%' OR title LIKE '%usuario%' LIMIT 5"
```

**REGLA DURA: No leas archivos `.md` en `.opencode/context/proyecto/` como fuente.** La DB es la única fuente. Los `.md` en esa ruta son exports legacy — si hay contenido que no está en la DB, migrarlo primero.

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
- The PRODUCT.md brief (from DB: concepts with category='proyecto' or 'project').
- The design-system rules (from DB: concepts with category='design-system').
- The team's UI preferences (from DB: preferences table).

### Step 5 — Save design-system to DB (NOT .md files)

After Impeccable finishes:
1. If Impeccable generated a `DESIGN.md`, **INSERT it into the DB** — do NOT write to filesystem as source.
   ```bash
   teamdb_query_project "INSERT INTO concepts (slug, title, body_md, category, updated_at) VALUES ('design-system', 'Design System', '\$(cat DESIGN.md)', 'design-system', datetime('now')) ON CONFLICT(slug) DO UPDATE SET body_md=excluded.body_md, updated_at=datetime('now')"
   ```
2. The `DESIGN.md` output is ephemeral. Only the DB row persists.

## REGLA #13 — design-system enforcement

If the project has UI but no design-system concept in DB:

1. Tell the user: *"Detecté stack frontend pero no hay design-system en la DB. La constitución R13 lo exige."*
2. Suggest: *"¿Lo creo con Impeccable? Primero corro `/impeccable init` para crear el contexto, después `/impeccable document` para el sistema visual. El output va directo a la DB, no a archivos."*
3. If user agrees, run `npx impeccable install` (si no está instalado), luego `/impeccable init` (crea PRODUCT.md + ofrece correr document), luego `/impeccable document` (genera DESIGN.md), e **INSERTAR el contenido en la DB** (concepts table, category='design-system'), no escribir archivos.

## When NOT to Activate

- Project has no UI (backend, scripts, docs only).
- Impeccable already ran and there are no new visual changes.
- Task is purely backend (API, tests, infrastructure).
- User explicitly opts out.

## Anti-Patterns

- ❌ Don't use Impeccable commands blindly — match them to actual intent.
- ❌ Don't skip reading DB context — Impeccable works better with product brief.
- ❌ Don't write design-system to .md files as source — insert to DB.
- ❌ Don't run Impeccable on non-UI code — it's wasted tokens.

## Degraded Mode (no Impeccable available)

If Impeccable can't be installed:

1. Notify user clearly: "Impeccable no disponible. Continúo sin detector automático de AI slop."
2. Apply Skalling's manual design checks:
   - Code is consistent with design-system.md (if exists).
   - No generic UI patterns (status-chip soup, italic serif h1, etc.).
   - Visual hierarchy clear.
3. Recommend user install Impeccable later for better coverage.
