# SDD status contract

Structured status the orchestrator (Alex) should have on hand before handing a
change to `sdd-apply`, `sdd-verify`, or `sdd-archive`. There is no special
tool that produces this — derive it directly from TeamDB (the same tables
described in Section B of `sdd-phase-common.md`), not from a filesystem
convention.

| Field           | Where it comes from                                                     |
|-----------------|---------------------------------------------------------------------------|
| `schemaName`    | Fixed: `"teamdb"` — this installation has one artifact store, not a choice of schemas. |
| `planningHome`  | `.opencode/context/team.db` for the project (the DB, not a directory).   |
| `changeRoot`    | The plan's `slug` in the `plans` table.                                  |
| `artifactPaths` | Not filesystem paths — table/row references: `plans.slug`, `specs.plan_id`, `tasks.plan_id`. |
| `contextFiles`  | Whatever `teamdb-context.sh for-request` already returned for this request — reuse it, don't recompute. |
| `applyState`    | `plans.status` for this change (`draft`/`approved`/`in_progress`/`completed`/`abandoned`). |
| task progress   | `COUNT(*)` and `SUM(status IN ('approved','resolved'))` from `tasks` where `plan_id` matches — the same query the dashboard's `/api/plans` endpoint uses. |
| dependency states | `task_dependencies` joined to `tasks`, as in `dashboard-server.py`'s `dependencies()`. |
| `actionContext` | The specific task/phase this handoff is about — not a separate lookup, just what the orchestrator already knows it's delegating. |

If a field can't be derived from TeamDB for some reason, say so explicitly to
whichever phase skill needs it — do not fabricate a plausible-looking value.
