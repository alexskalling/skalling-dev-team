# SDD Phase Common — Sections A–D

Referenced by every `sdd-*` skill in this installation. **This installation only
supports TeamDB persistence** — there is no Engram integration and no real
`openspec` CLI/tool wired up here. Where an individual `sdd-*` skill branches on
`engram | openspec | hybrid | none`, treat that entire distinction as
inapplicable: always follow the DB-only path described below, and never write
a `.md` file to the filesystem as if it were the source of an artifact.

If a skill instructs you to "read and follow `skills/_shared/openspec-convention.md`"
for `openspec` mode, ignore that instruction — that file does not exist in this
installation on purpose, and there is no real `openspec` project layout
(`openspec/changes/...`, `openspec/config.yaml`) to follow. Do not improvise one
from general knowledge of the `openspec` tool. Persist to TeamDB per Section C
below, exactly as you would for any other mode.

## Section A — Load Skills

Before doing phase work, check `.opencode/project.yaml` → `skills_installed` for
stack-specific skills relevant to the change (framework, test runner, linter).
Load only the ones that apply to the files you are about to touch. This is a
convenience step, not a gate — proceed with the phase even if nothing extra
applies.

## Section B — Retrieval

Read the prior phase's artifact directly from TeamDB — never from a filesystem
path, never from Engram. Use `teamdb-read.sh` (read-only, parameterized) or the
project's own `sqlite3` access pattern, scoped to `"$PROJECT"`.

| Phase reads    | Table(s)                                   | Column(s)                          |
|----------------|---------------------------------------------|-------------------------------------|
| spec           | `proposals` (by slug)                       | `intent_md`, `questions_json`       |
| design         | `specs` (by `plan_id`)                      | `body_md`                           |
| tasks          | `plans` (by slug)                           | `design_md`, `acceptance_md`        |
| apply          | `plans` + `tasks` (by `plan_id`)             | `design_md`; task `title`/`description_md`/`status` |
| verify         | `plans`, `specs`, `tasks`                    | `acceptance_md`, spec `body_md`, task `status` |
| archive        | `proposals`, `plans`, `specs`, `tasks`       | all of the above, for the final record |

If a required row is missing, stop and report it as a blocker — do not
fabricate the missing artifact from what the change is "probably" about.

## Section C — Persistence

**The DB is the source of truth. A `.md` file is a generated export, never the
source of an artifact — this applies to every phase, regardless of what mode
label the orchestrator passed.**

- Compose the artifact's content in memory (a normal string/heredoc in your own
  reasoning), then persist it with the project's real write path for that
  artifact type:
  - Proposals/specs/plans/tasks: `teamdb-plan.sh` (new plan) or
    `teamdb-amend.sh --add-task` / `--set-design` / etc. (existing plan) —
    compose the content, pipe it via `/dev/stdin` where the script expects a
    body, pass metadata via flags (`--purpose`, `--acceptance`, ...).
  - Never `mkdir -p .opencode/plans/...` or `cat > .../tasks.md`. There is no
    project convention that reads from that path — writing there produces a
    file nothing downstream will ever consult, and leaves the DB (the thing
    Alex, the dashboard, and every other agent actually read) empty.
- **No automatic filesystem export.** If the user wants a Markdown copy for
  Git visibility, they run `skalling-snapshot.sh` themselves — never do this
  on their behalf as part of a phase.

## Section D — Return Envelope

Return to the orchestrator (Alex, or whoever delegated the phase) using this
shape, adapted to the phase:

```markdown
## {Phase Name} — {Change Title}

**Change**: {change-slug}
**Location**: TeamDB (source of truth) — `{table}` row for `{change-slug}`

### Summary
{1-3 sentences: what was produced, and any blocker found in Section B}

### Next Step
{Which phase/agent should run next, or what decision is needed from the user}
```

Keep it short — this is a status update for the orchestrator, not the artifact
itself (the artifact already lives in the DB per Section C).
