# Design: TeamDB Hardening v0.7.2

**Slug:** `teamdb-hardening`
**Date:** 2026-08-05
**Companion to:** `proposal.md`, `spec.md`

---

## Architectural Decisions (forced by source-of-truth declaration)

### AD-1 — Source of Truth: TeamDB (libSQL)

**Decision:** TeamDB is the canonical source for state, versions, plans, decisions, problems, WIP, audit, tags, and links.

**Rationale:** Declared by user. Eliminates dual-write ambiguity. Markdown becomes derived/exported data (like SQL dumps in `.opencode/context/teamdb/data_*.sql`).

**Trade-off:** All consumers must use `teamdb_query_*` / `teamdb_write_*`. Old code reading `.jsonl` or `.md` directly becomes a fallback path, deprecated.

**Non-negotiable:** All scripts in `scripts/teamdb-*.sh` MUST use the lib helpers. Direct `sqlite3` invocation is reserved for tests and one-off migrations.

---

### AD-2 — Parameterized SQL via helper, not raw sqlite3

**Decision:** New helper `teamdb_safe_query <db> <mode> <query> [<param>...]` where:
- `<mode>` ∈ {`fts`, `like`, `exact`}
- `<query>` is a parameterized SQL template
- `<param>` values are bound via `sqlite3 :param` syntax

**Rationale:** Bash string interpolation is unsafe (SQL injection). SQLite supports `:var` placeholders. Centralizing in a helper keeps the audit trail in one place.

**Implementation pattern:**
```bash
teamdb_safe_query() {
  local db="$1"; shift
  local mode="$1"; shift
  local template="$1"; shift
  sqlite3 -separator $'\t' "$db" "$template" "$@"
}

# Usage:
teamdb_safe_query "$DB" fts \
  "SELECT slug, title FROM concepts_fts WHERE concepts_fts MATCH ?" \
  "$user_query"
```

**Trade-off:** Slightly more verbose than `$var` interpolation, but immune to SQLi.

---

### AD-3 — Audit log via PRAGMA actor + helper-side write

**Decision:** Two-tier approach:
1. **Triggers** still exist (for backward compat with tests that count triggers)
2. **Helper `teamdb_write_*`** prepends an explicit `INSERT INTO audit_log` with the real actor

**Rationale:** SQLite triggers cannot read environment variables. PRAGMA values are session-scoped and CAN be set by `teamdb_write_*` before the operation, then read by a custom function. But that requires `sqlite3_create_function` which Bash can't do. Pragmatic solution: the helper writes the audit row explicitly, triggers still fire (with literal `'system'` for the trigger-side row, which marks schema-level mutations).

**Trade-off:** `audit_log` may have two rows per mutation (one from helper with real actor, one from trigger with `system`). We deduplicate at read time by preferring the helper row.

**Migration path:**
- New `audit_log.actor_source` column (`'helper' | 'trigger' | 'manual'`)
- Helper writes `actor_source='helper'`
- Triggers write `actor_source='trigger'`
- Readers filter `WHERE actor_source='helper'` for real attribution

---

### AD-4 — Schema versioning via version-row stampeo (no full regeneration)

**Decision (CORREGIDA por Sol):** `scripts/build-schema.sh` SOLO estampa la línea de versión — no regenera los archivos enteros. Concretamente:
1. Lee `VERSION`
2. Reemplaza SOLO la línea `INSERT INTO schema_meta VALUES ('version', '<X>')` en `sql/project-schema.sql` y `sql/global-schema.sql`
3. Remueve la línea `UPDATE schema_meta SET value = '<X>' WHERE key = 'version'` (manejada solo por el INSERT inicial)
4. Valida que no haya otras strings literales `0\.\d+\.\d+` en los schemas (falla si las encuentra, indicando que deben moverse a VERSION)
5. NO toca triggers, tablas cycle, ni nada del cuerpo del schema

**Rationale (CORREGIDA):** La propuesta original de regenerar `sql/*.sql` enteros era sobre-alcance — esos archivos contienen triggers y tablas cycle hand-written (12 triggers con `agent='system'` literal que se refactoriza en TASK-3.7). Regenerar todo pisaría cambios no triviales. El "single source" se consigue estamapando solo la fila `schema_meta.version`, que es el ÚNICO punto donde el número de versión realmente vive.

**Trade-off:** `sql/*.sql` siguen siendo hand-written (excepto la fila de versión). El header del schema debe documentar "el version row se genera; no editar a mano".

**Mitigation:** El script `build-schema.sh` se corre en CI antes de los tests; si la fila de versión no coincide con VERSION, falla. Se commitea el resultado. **TASK-2.1 implementa este AD-4 corregido.**

---

### AD-5 — Snippet deduplication via build-time include

**Decision:** `install-global.sh` reads `<!-- @include-snippet NAME -->` markers from agent files, replaces them with the body of `templates/agents/snippets/NAME.md`, and writes the resolved file to `~/.config/opencode/agents/`.

**Rationale:** Markdown comments are ignored by opencode runtime. Build-time resolution gives us single source + zero runtime cost.

**Implementation:**
```bash
resolve_includes() {
  local file="$1"
  local content; content="$(cat "$file")"
  while [[ "$content" =~ @include-snippet[[:space:]]+([a-z-]+) ]]; do
    local name="${BASH_REMATCH[1]}"
    local body; body="$(cat "$SCRIPT_DIR/templates/agents/snippets/$name.md")"
    content="${content//<!-- @include-snippet $name --> /$body}"
  done
  echo "$content"
}
```

**Trade-off:** Agent files in the repo are templates (have markers); installed files are resolved. This breaks direct "copy agent file" workflows.

**Mitigation:** Document the no-direct-copy rule. Add `tests/snippets-sync.test.sh` to enforce.

---

### AD-6 — Conditional required fields in handoff schema

**Decision:** Use JSON Schema `if/then/else` to conditionally require `project_context` and `verification`.

**Pattern:**
```json
{
  "allOf": [
    {
      "if": { "properties": { "to": { "enum": ["TEO", "LUZ"] } } },
      "then": { "required": ["project_context"] }
    },
    {
      "if": { "properties": { "to": { "enum": ["JHON", "LUZ"] } } },
      "then": { "required": ["verification"] }
    }
  ]
}
```

**Rationale:** Some handoffs (ALEX → user) don't need project_context; others (SOL → TEO) do. Conditional requirements model this accurately.

**Trade-off:** Validator implementations must support JSON Schema 2020-12. `ajv` and `jsonschema` (Python) do.

---

### AD-7 — Hooks with absolute paths via `git rev-parse`

**Decision:** Hooks compute their project root with `git rev-parse --show-toplevel`, then reference `scripts/teamdb-export.sh` from the **repo** OR the **global install** path.

**Implementation:**
```bash
PROJECT="$(git rev-parse --show-toplevel)"
if [ -f "$PROJECT/.opencode/context/team.db" ]; then
  EXPORT_SCRIPT="${SKALLING_ROOT:-$HOME/.config/opencode}/scripts/teamdb-export.sh"
  bash "$EXPORT_SCRIPT" "$PROJECT"
  git add "$PROJECT/.opencode/context/teamdb"/data_*.sql 2>/dev/null || true
fi
```

**Rationale:** `$SCRIPT_DIR/..` is wrong because `$SCRIPT_DIR=.git/hooks`. Absolute via git is reliable.

**Trade-off:** Hooks depend on either repo presence (for dev) or global install (for consumers). This is the same dependency as before — no new fragility.

---

### AD-8 — Cycle tables (`plans`, `tasks`) replace `work_in_progress` for new work

**Decision:** New scripts use `plans`/`tasks`/`proposals`. `work_in_progress` is grandfathered (used only by `wip-tree.sh` and `teamdb-migrate.sh` for legacy imports).

**Rationale:** The cycle complete tables (`proposals`, `plans`, `specs`, `design_notes`, `tasks`) were already in `project-schema.sql` v0.7.1. They model the SDD lifecycle more accurately than `work_in_progress`. Continuing to use `work_in_progress` for new work would be technical debt.

**Trade-off:** Two parallel hierarchies. Visualizer (`wip-tree.sh`) only sees `work_in_progress`. New visualizer for `plans`/`tasks` is out of scope (OOS-3).

**Migration:** Old `work_in_progress` rows are imported into `plans`/`tasks` only if Pau manually triggers it. Not in this change.

---

### AD-9 — Tests colocated with scripts, named `tests/teamdb-<area>.test.sh`

**Decision:** New tests live in `tests/teamdb-<area>.test.sh` (e.g., `teamdb-search-sqli.test.sh`, `teamdb-cycle.test.sh`, `agents-teamdb-integration.test.sh`).

**Rationale:** Bash test convention used by existing `tests/teamdb.test.sh`. Easy to grep and identify coverage.

**Trade-off:** No centralized test runner. CI lists them explicitly in workflows.

---

### AD-10 — No commits until user explicitly authorizes (R16)

**Decision:** Teo writes code + tests, but does NOT commit. Final commit message is written by Alex (in Spanish, R16 format).

**Rationale:** Constitution R16 (already enforced). Explicit confirmation required.

**Trade-off:** Slower feedback loop for the team. User benefits from review checkpoints.

---

## Patterns and Conventions

### P-1 — All new scripts start with `set -euo pipefail`
Plus a 4-line header explaining purpose.

### P-2 — All scripts source `lib-teamdb.sh` via fallback pattern
Same fallback used in existing scripts (handles repo vs global install).

### P-3 — Tests use `mktemp -d` for DB fixtures
No shared state. Each test gets a fresh DB.

### P-4 — Error messages in Spanish, prefixed with `[ERROR]` or `[WARN]`
Matches existing convention in `teamdb-*.sh`.

### P-5 — Function names in snake_case español
`teamdb_escribir_proyecto`, `teamdb_safe_query`, `obtener_audit_log`.

### P-6 — No emojis in code paths
Visual indicators (✅, ⚠️) only in CLI output for human reading.

### P-7 — Snake_case in SQL identifiers
Already enforced. New tables/columns follow the convention.

---

## Data Model Changes

### New columns

**`audit_log`:**
- `actor_source TEXT DEFAULT 'trigger'` — `'helper' | 'trigger' | 'manual'`
- `session_id TEXT` — UUID generated per `teamdb_write_*` invocation (groups mutations)
- `correlation_id TEXT` — shared across operations in a single plan (optional)

### New tables

None. All tables for cycle complete already exist.

---

## File Layout (new + modified)

```
scripts/
├── lib/
│   └── lib-teamdb.sh                (modified — add teamdb_write_global, teamdb_safe_query)
├── teamdb-init.sh                   (modified — set TEAMDB_ACTOR during init to 'sol')
├── teamdb-migrate.sh                (modified — frontmatter extraction, idempotency, warning on empty)
├── teamdb-export.sh                 (modified — include audit_log, schema_meta)
├── teamdb-import.sh                 (modified — dedup audit_log by ts+agent+action+row_id)
├── teamdb-plan.sh                   (new — CIC-1.1)
├── teamdb-status.sh                 (new — CIC-1.5)
├── teamdb-amend.sh                  (new — CIC-1.2)
├── teamdb-resume.sh                 (new — CIC-1.3)
├── teamdb-execute-plan.sh           (new — CIC-1.4)
├── teamdb-search.sh                 (modified — SEG-1, parameterized)
├── teamdb-related.sh                (modified — SEG-2, parameterized)
├── teamdb-graph.sh                  (modified — use teamdb_safe_query)
├── wip-tree.sh                      (unchanged — grandfathered legacy)
└── build-schema.sh                  (new — AD-4)

sql/
├── project-schema.sql               (modified — actor_source, session_id, problems_fts)
├── global-schema.sql                (modified — version stamped from VERSION at build)
└── migrations/                      (recreated — 001_add_audit_actor_source.sql)

install-global.sh                    (modified — install all teamdb-* scripts + hooks)
bootstrap-context.sh                 (modified — TEAMDB_ACTOR export)

tests/
├── teamdb.test.sh                   (modified — add coverage for new scripts)
├── teamdb-search-sqli.test.sh       (new — AC-1.1)
├── teamdb-related-sqli.test.sh      (new — AC-1.2)
├── teamdb-cycle.test.sh             (new — AC-4.5)
├── teamdb-hardening-suite.sh        (new — aggregator, runs all teamdb tests)
├── handoff-schema-validation.test.sh (new — AC-9.x)
├── agents-teamdb-integration.test.sh (new — AC-6.x)
├── snippets-sync.test.sh            (new — AC-7.x)
├── version-coherence.test.sh        (new — AC-3.x)
├── install.test.sh                  (new — AC-2.x)
├── portability-bash32.test.sh       (new — AC-12.x)
├── write-helpers.test.sh            (new — AC-5.x)
└── audit-log.test.sh                (new — AC-8.x)

.github/workflows/
├── tests.yml                        (modified — include teamdb.test.sh in matrix)
├── teamdb-sqli.yml                  (new — AC-10.2)
└── handoffs.yml                     (new — AC-10.3)

templates/
├── handoff.schema.json              (modified — conditional required)
└── agents/snippets/
    ├── code-intelligence.md         (unchanged — single source)
    └── memory-protocol.md           (unchanged — single source)

agents-base/
├── Alex.md                          (modified — AGE-1.1, AGE-1.2, markers)
├── Jes.md                           (modified — AGE-1.3, markers)
├── Pol.md                           (modified — markers only)
├── Sol.md                           (modified — markers only)
├── Teo.md                           (modified — markers only)
├── Jhon.md                          (modified — markers only)
├── Luz.md                           (modified — markers only)
└── Pau.md                           (modified — markers only)

VERSION                              (unchanged — still 0.7.0; this change is 0.7.2)
CHANGELOG.md                         (modified — document 0.7.2)
README.md                            (modified — dynamic version, document new scripts)
```

---

## Risks and Mitigations (design-level)

| Risk | Mitigation |
|---|---|
| Schema regeneration breaks existing team.db files | `scripts/build-schema.sh` includes idempotent `ALTER TABLE` steps for additive changes; doc note about non-additive changes requiring migration |
| Helper-side audit_log duplicates trigger audit_log | `actor_source` column disambiguates; readers filter by source |
| Snippet resolution adds 200ms to install time | Acceptable; install is one-shot |
| Conditional schema requirements break some existing tools | Backward-compatible: existing fields remain, only ADDED requirements |

---

*Design authored by Pol. Implementation by Teo under Sol's task list.*
