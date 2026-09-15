# Engram convention — not used in this installation

This installation has no Engram integration — no `mem_save`/`mem_search` MCP
tools, no `sdd/{change-name}/...` key namespace. If a skill sent you here
because the orchestrator passed `engram` as the artifact store mode, that mode
does not apply here.

Ignore the `engram`/`openspec`/`hybrid` distinction entirely and follow
**Section C (Persistence)** in `skills/_shared/sdd-phase-common.md`: persist
directly to TeamDB via `teamdb-plan.sh` / `teamdb-amend.sh`. That is the only
artifact store this project has.
