---
name: sdd-design
description: "Create the SDD technical design and architecture approach. Trigger: orchestrator launches design for a change."
disable-model-invocation: true
user-invocable: false
license: MIT
metadata:
  author: gentleman-programming
  version: "2.0"
  delegate_only: true
---

> **ORCHESTRATOR GATE**: If you loaded this skill via the `skill()` tool, you are
> the ORCHESTRATOR — STOP. Do NOT execute these instructions inline. Delegate to
> the dedicated `sdd-design` sub-agent using your platform's delegation primitive
> (e.g., `task(...)`, sub-agent invocation, etc.). This skill is for EXECUTORS
> only.

## Executor Override

If you ARE the `sdd-design` sub-agent (NOT the orchestrator), the gate above does NOT apply to you. Continue with the phase work below. Do NOT delegate. Do NOT call the Skill tool. You are the executor — execute.


## Language Domain Contract

Generated technical artifacts default to English. Do not inherit the user's conversational language or the active persona's regional voice for SDD artifacts unless the user explicitly requests that artifact language or the project convention requires it.

If technical artifacts are explicitly requested in another language, use a neutral/professional register unless the user explicitly requests a different tone or regional variant.

Public/contextual comments follow the target context language by default. Explicit user language or tone overrides win; otherwise use a neutral/professional register unless the target context clearly calls for another tone or regional variant.

## Purpose

You are a sub-agent responsible for TECHNICAL DESIGN. You take the proposal and specs, then produce a `design.md` that captures HOW the change will be implemented — architecture decisions, data flow, file changes, and technical rationale.

## What You Receive

From the orchestrator:
- Change name
- Artifact store mode (`engram | openspec | hybrid | none`)

## Execution and Persistence Contract

> Follow **Section B** (retrieval) and **Section C** (persistence) from `skills/_shared/sdd-phase-common.md`.

- **engram**: Read `sdd/{change-name}/proposal` (required) and `sdd/{change-name}/spec` (optional — may not exist if running in parallel with sdd-spec). Save as `sdd/{change-name}/design`.
- **openspec**: Read and follow `skills/_shared/openspec-convention.md`.
- **hybrid**: Follow BOTH conventions — persist to Engram AND write `design.md` to filesystem. Retrieve dependencies from Engram (primary) with filesystem fallback.
- **none**: Return result only. Never create or modify project files.

## What to Do

### Step 1: Load Skills
Follow **Section A** from `skills/_shared/sdd-phase-common.md`.

### Step 2: Read the Codebase

Before designing, read the actual code that will be affected:
- Entry points and module structure
- Existing patterns and conventions
- Dependencies and interfaces
- Test infrastructure (if any)

### Step 2a: Applicability-Driven Threat Matrix

If the design changes routing, shell commands, subprocesses, VCS/PR automation, executable-file classification, or process integration, read `references/threat-matrix.md` and include its matrix in the design. Mark every row `Applicable` or explicit `N/A` with a reason. Define expected safe/failure behavior and planned RED tests for every applicable case. If none of these boundaries exists, record the matrix as not applicable; do not manufacture irrelevant tasks.

### Step 3: Persist Design to DB

**CRITICAL**: The DB is the source of truth. `.md` files are GENERATED exports, never the source.

**IF mode is `openspec` or `hybrid`:**
1. Write the design to TeamDB via `teamdb_exec.py`:
```bash
python3 ~/.config/opencode/scripts/teamdb_exec.py \
  --db "$PROJECT/.opencode/teamdb.sqlite" \
  --mode write \
  --sql "UPDATE plans SET design_md = ?, updated_at = datetime('now') WHERE slug = ?" \
  --params '["# Design\n\n{design content}", "{change-name}"]'
```
2. **NO export automático**. Para generar .md manualmente:
```bash
bash ~/.config/opencode/scripts/skalling-snapshot.sh "$PROJECT" {change-name}
```

**IF mode is `engram`**: Use `mem_save` per Section C (persistence).

**IF mode is `none`**: Compose in memory only.

#### Design Document Format

Use this template to structure the design content before writing to DB:

```markdown
# Design: {Change Title}

## Technical Approach

{Concise description of the overall technical strategy.
How does this map to the proposal's approach? Reference specs.}

## Architecture Decisions

### Decision: {Decision Title}

**Choice**: {What we chose}
**Alternatives considered**: {What we rejected}
**Rationale**: {Why this choice over alternatives}

### Decision: {Decision Title}

**Choice**: {What we chose}
**Alternatives considered**: {What we rejected}
**Rationale**: {Why this choice over alternatives}

## Data Flow

{Describe how data moves through the system for this change.
Use ASCII diagrams when helpful.}

    Component A ──→ Component B ──→ Component C
         │                              │
         └──────── Store ───────────────┘

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `path/to/new-file.ext` | Create | {What this file does} |
| `path/to/existing.ext` | Modify | {What changes and why} |
| `path/to/old-file.ext` | Delete | {Why it's being removed} |

## Interfaces / Contracts

{Define any new interfaces, API contracts, type definitions, or data structures.
Use code blocks with the project's language.}

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | {What} | {How} |
| Integration | {What} | {How} |
| E2E | {What} | {How} |

## Threat Matrix

{For routing/shell/process integration, include the applicability matrix from `references/threat-matrix.md`. Otherwise: `N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary.`}

## Migration / Rollout

{If this change requires data migration, feature flags, or phased rollout, describe the plan.
If not applicable, state "No migration required."}

## Open Questions

- [ ] {Any unresolved technical question}
- [ ] {Any decision that needs team input}
```

**Then write to DB** using the command in Step 3 above, incorporating this composed content.

### Step 4: Persist Artifact

**This step is MANDATORY — do NOT skip it.**

- **engram**: Follow **Section C** from `skills/_shared/sdd-phase-common.md` — save to Engram.
- **openspec**: **NO export automático**. La DB es la fuente de verdad. Si se necesita visibilidad en Git, el usuario corre `skalling-snapshot` manualmente.
- **hybrid**: Save to Engram. **NO export automático a filesystem**.
- **none**: Return result inline only.
- **none**: Return result inline only.

### Step 5: Return Summary

Return to the orchestrator:

```markdown
## Design Created

**Change**: {change-name}
**Location**: DB (source of truth) | `openspec/changes/{change-name}/design.md` (openspec/hybrid export) | Engram `sdd/{change-name}/design` (engram)

### Summary
- **Approach**: {one-line technical approach}
- **Key Decisions**: {N decisions documented}
- **Files Affected**: {N new, M modified, K deleted}
- **Testing Strategy**: {unit/integration/e2e coverage planned}

### Open Questions
{List any unresolved questions, or "None"}

### Next Step
Ready for tasks (sdd-tasks).
```

## Rules

- **DB is source of truth** — never write `.md` files as if they were source. Use `teamdb_exec.py --mode write` for DB persistence.
- ALWAYS read the actual codebase before designing — never guess
- Every decision MUST have a rationale (the "why")
- Include concrete file paths, not abstract descriptions
- Use the project's ACTUAL patterns and conventions, not generic best practices
- If you find the codebase uses a pattern different from what you'd recommend, note it but FOLLOW the existing pattern unless the change specifically addresses it
- Keep ASCII diagrams simple — clarity over beauty
- Apply any `rules.design` from `openspec/config.yaml`
- If you have open questions that BLOCK the design, say so clearly — don't guess
- **Size budget**: Design artifact MUST be under 800 words. Architecture decisions as tables (option | tradeoff | decision). Code snippets only for non-obvious patterns.
- Applicable threat-matrix rows are design requirements and MUST propagate to tasks and RED tests unchanged; explicit `N/A` rows require no task.
- Return envelope per **Section D** from `skills/_shared/sdd-phase-common.md`.

## References

- [references/threat-matrix.md](references/threat-matrix.md) — load only for routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration designs.
