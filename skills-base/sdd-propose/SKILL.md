---
name: sdd-propose
description: "Create an SDD change proposal with intent, scope, and approach. Trigger: orchestrator launches proposal work for a change."
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
> the dedicated `sdd-propose` sub-agent using your platform's delegation primitive
> (e.g., `task(...)`, sub-agent invocation, etc.). This skill is for EXECUTORS
> only.

## Executor Override

If you ARE the `sdd-propose` sub-agent (NOT the orchestrator), the gate above does NOT apply to you. Continue with the phase work below. Do NOT delegate. Do NOT call the Skill tool. You are the executor — execute.


## Language Domain Contract

Generated technical artifacts default to English. Do not inherit the user's conversational language or the active persona's regional voice for SDD artifacts unless the user explicitly requests that artifact language or the project convention requires it.

If technical artifacts are explicitly requested in another language, use a neutral/professional register unless the user explicitly requests a different tone or regional variant.

Public/contextual comments follow the target context language by default. Explicit user language or tone overrides win; otherwise use a neutral/professional register unless the target context clearly calls for another tone or regional variant.

## Purpose

You are a sub-agent responsible for creating PROPOSALS. You take the exploration analysis (or direct user input) and produce a structured `proposal.md` document inside the change folder.

## What You Receive

From the orchestrator:
- Change name (e.g., "add-dark-mode")
- Exploration analysis (from sdd-explore) OR direct user description
- Artifact store mode (`engram | openspec | hybrid | none`)

## Execution and Persistence Contract

> Follow **Section B** (retrieval) and **Section C** (persistence) from `skills/_shared/sdd-phase-common.md`.

- **engram**: Read `sdd/{change-name}/explore` (optional) and `sdd-init/{project}` (optional). Save artifact as `sdd/{change-name}/proposal`.
- **openspec**: Read and follow `skills/_shared/openspec-convention.md`.
- **hybrid**: Follow BOTH conventions — persist to Engram AND write to filesystem. Retrieve dependencies from Engram (primary) with filesystem fallback.
- **none**: Return result only. Never create or modify project files.
- Never force `openspec/` creation unless user requested file-based persistence or mode is `hybrid`.

## What to Do

### Step 0: Shape the Proposal in Interactive Mode

- In interactive SDD mode, do not make the executor decide silently whether the proposal is "clear enough". Offer the user a proposal question round before finalizing the proposal: explain that the questions are meant to improve the PRD/proposal by uncovering business rules, implications, impact, edge cases, and product tradeoffs. Let the user answer, skip, correct the framing, or ask for a second question round.
- Proposal-shaping questions should uncover business/product/PRD understanding, not harness mechanics. Cover the smallest useful subset of:
  1. business problem: what pain, opportunity, user confusion, or operational cost makes this change worth doing now;
  2. target users and situations: who is affected, in which workflow, at what moment, and with what level of urgency;
  3. business rules: policies, permissions, thresholds, lifecycle rules, compliance/security expectations, or domain invariants the proposal must respect;
  4. product outcome: what should feel, work, or become possible after the change;
  5. current-state gap: what is wrong, inconsistent, missing, ad hoc, or hard to explain today;
  6. implications and impact: which teams, workflows, data, UX expectations, support burden, or operational processes may be affected;
  7. edge cases: empty states, partial data, failures, permissions, slow paths, unusual customers, migration states, or conflicting user needs;
  8. decision gaps: which product unknowns would make the proposal ambiguous, risky, or easy to overbuild;
  9. scope boundaries and non-goals: what belongs in the first product slice, what is later refinement, and what must stay unchanged even if related;
  10. business risk or tradeoff: what downside matters most if the proposal chooses the wrong direction.
- Prefer 3–5 concrete product questions per round. After the first answers, summarize the resulting proposal assumptions and ask whether the user wants to correct anything or run a second question round. Do not ask about test commands, PR shape, changed-line budget, or other harness decisions unless the user explicitly asks to discuss delivery. If blocked from asking directly, write a `## Proposal question round` section in the proposal result with the proposed questions and assumptions needing user review.

### Step 1: Load Skills
Follow **Section A** from `skills/_shared/sdd-phase-common.md`.

### Step 2: Persist Proposal to DB

**CRITICAL**: The DB is the source of truth. `.md` files are GENERATED exports, never the source.

**IF mode is `openspec` or `hybrid`:**
1. Write the proposal to TeamDB via `teamdb_exec.py`:
```bash
python3 ~/.config/opencode/scripts/teamdb_exec.py \
  --db "$PROJECT/.opencode/teamdb.sqlite" \
  --mode write \
  --sql "INSERT INTO proposals(slug, title, intent_md, status, agent, created_at, updated_at) VALUES (?, ?, ?, 'draft', 'pol', datetime('now'), datetime('now')) ON CONFLICT(slug) DO UPDATE SET title=excluded.title, intent_md=excluded.intent_md, updated_at=datetime('now')" \
  --params '["{change-name}", "{Change Title}", "# Intent\n\n{intent content}"]'
```
2. After DB write, export to filesystem if user visibility is needed:
```bash
bash ~/.config/opencode/scripts/teamdb-export-md.sh "$PROJECT" --plan={change-name}
```

**IF mode is `engram`**: Use `mem_save` per Section C (persistence).

**IF mode is `none`**: Compose in memory only.

### Step 3: Read Existing Specs

**IF mode is `openspec` or `hybrid`:** If `openspec/specs/` has relevant specs, read them to understand current behavior that this change might affect.

**IF mode is `engram`:** Existing context was already retrieved from Engram in the Persistence Contract. Skip filesystem reads.

**IF mode is `none`:** Skip — no existing specs to read.

### Step 3: Compose Proposal Content

Use this template to structure the proposal content before writing to DB:

```markdown
# Proposal: {Change Title}

## Intent

{What problem are we solving? Why does this change need to happen?
Be specific about the user need or technical debt being addressed.}

## Scope

### In Scope
- {Concrete deliverable 1}
- {Concrete deliverable 2}
- {Concrete deliverable 3}

### Out of Scope
- {What we're explicitly NOT doing}
- {Future work that's related but deferred}

## Capabilities

> This section is the CONTRACT between proposal and specs phases.
> The sdd-spec agent reads this to know exactly which spec files to create or update.
> Research `openspec/specs/` before filling this in.

### New Capabilities
<!-- Capabilities being introduced. Each becomes a new `openspec/specs/<name>/spec.md`.
     Use kebab-case names (e.g., user-auth, data-export, api-rate-limiting).
     Leave empty if no new capabilities. -->
- `<capability-name>`: <brief description of what this capability covers>

### Modified Capabilities
<!-- Existing capabilities whose REQUIREMENTS are changing (not just implementation).
     Only list here if spec-level behavior changes. Each needs a delta spec.
     Use existing spec names from openspec/specs/. Leave empty if none. -->
- `<existing-capability-name>`: <what requirement is changing>

## Approach

{High-level technical approach. How will we solve this?
Reference the recommended approach from exploration if available.}

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `path/to/area` | New/Modified/Removed | {What changes} |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| {Risk description} | Low/Med/High | {How we mitigate} |

## Rollback Plan

{How to revert if something goes wrong. Be specific.}

## Dependencies

- {External dependency or prerequisite, if any}

## Success Criteria

- [ ] {How do we know this change succeeded?}
- [ ] {Measurable outcome}
```

**Then write to DB** using the command in Step 2 above, incorporating this composed content.

### Step 4: Persist Artifact

**This step is MANDATORY — do NOT skip it.**

- **engram**: Follow **Section C** from `skills/_shared/sdd-phase-common.md` — save to Engram.
- **openspec**: After the DB write in Step 2, export to filesystem via `teamdb-export-md.sh`. The file is GENERATED, not source.
- **hybrid**: Do BOTH — save to Engram AND export to filesystem.
- **none**: Return result inline only.

### Step 5: Return Summary

Return to the orchestrator:

```markdown
## Proposal Created

**Change**: {change-name}
**Location**: DB (source of truth) | `openspec/changes/{change-name}/proposal.md` (openspec/hybrid export) | Engram `sdd/{change-name}/proposal` (engram)

### Summary
- **Intent**: {one-line summary}
- **Scope**: {N deliverables in, M items deferred}
- **Approach**: {one-line approach}
- **Risk Level**: {Low/Medium/High}

### Next Step
Ready for specs (sdd-spec) or design (sdd-design).
```

## Rules

- **DB is source of truth** — never write `.md` files as if they were source. Use `teamdb_exec.py --mode write` for DB persistence.
- If the change already exists with a proposal in DB, UPDATE it via SQL, don't overwrite blindly.
- Keep the proposal CONCISE - it's a thinking tool, not a novel
- Every proposal MUST have a rollback plan
- Every proposal MUST have success criteria
- Use concrete file paths in "Affected Areas" when possible
- Apply any `rules.proposal` from `openspec/config.yaml`
- **ALWAYS fill in the Capabilities section** — this is the contract with sdd-spec. Research `openspec/specs/` first to use correct existing capability names.
- New Capabilities → each will become `openspec/specs/<name>/spec.md` (new full spec)
- Modified Capabilities → each will become a delta spec in the change folder
- If nothing changes at the spec level (pure refactor, config change), explicitly write "None" under both sub-sections — don't leave them as template placeholders
- **Size budget**: Proposal artifact MUST be under 450 words. Use bullet points and tables over prose. Headers organize, not explain.
- Return envelope per **Section D** from `skills/_shared/sdd-phase-common.md`.
