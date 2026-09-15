# openspec convention — not used in this installation

If an `sdd-*` skill sent you here because the orchestrator passed
`openspec` (or `hybrid`) as the artifact store mode: **this installation has
no real `openspec` project layout**. There is no `openspec/` directory, no
`openspec/config.yaml`, and nothing downstream ever reads
`openspec/changes/{change-name}/*.md`.

Do not create that layout from general knowledge of the `openspec` tool.
Ignore the `openspec`/`hybrid`/`engram` distinction entirely and follow
**Section C (Persistence)** in `skills/_shared/sdd-phase-common.md` instead:
persist directly to TeamDB via `teamdb-plan.sh` / `teamdb-amend.sh`. That is
the only artifact store this project has.
