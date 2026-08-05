# Specs: TeamDB Hardening v0.7.2

**Slug:** `teamdb-hardening`
**Status:** Draft → Approved at proposal acceptance
**Format:** Given/When/Then + RFC 2119 keywords (MUST, SHALL, SHOULD, MAY)

These specs implement the Acceptance Criteria defined in `proposal.md`. Each spec is independently testable. Tests live under `tests/` with naming `tests/teamdb-<area>.test.sh`.

---

## Spec SEGURIDAD-1 — SQL Injection Safe Search

**Spec ID:** SEG-1
**Implements AC:** 1.1, 1.4, 1.5
**File:** `scripts/teamdb-search.sh`, `scripts/lib/lib-teamdb.sh`

### SEG-1.1 — Query parameterization (MUST)
- **Given** a project DB with N rows in `concepts`
- **When** the user invokes `bash scripts/teamdb-search.sh "JWT auth; DROP TABLE concepts; --" concepts`
- **Then** the query SHALL be executed as a literal search term; no SQL statement modification SHALL occur
- **And** the `concepts` table SHALL remain intact (row count unchanged)

### SEG-1.2 — Helper function for safe queries (MUST)
- **Given** `lib-teamdb.sh` is sourced
- **When** any script needs to interpolate user input into SQL
- **Then** it SHALL call `teamdb_safe_query <db_path> <type> <query>` where `<type>` ∈ {`fts`, `like`, `exact`}
- **And** the helper SHALL escape the input via `sqlite3` parameter binding (NOT string interpolation)
- **And** the helper SHALL return non-zero if input contains control characters (NUL, BEL, ESC) or exceeds 1024 chars

### SEG-1.3 — Reject shell metacharacters in type filter (MUST)
- **Given** a user invokes `bash scripts/teamdb-search.sh "query" "all; malicious"`
- **When** the script validates the type argument
- **Then** it SHALL reject the input with exit code 2 and message "Invalid type"
- **And** it SHALL NOT proceed to execute SQL with the malicious type

### SEG-1.4 — Audit log of suspicious queries (SHOULD)
- **Given** a search query contains shell metacharacters
- **When** the query is rejected by SEG-1.3
- **Then** the rejection SHALL be logged to `audit_log` with `agent='search-defender'`, `action='reject'`, `details=<rejected_query>`

---

## Spec SEGURIDAD-2 — SQL Injection Safe Related

**Spec ID:** SEG-2
**Implements AC:** 1.2, 1.4, 1.5
**File:** `scripts/teamdb-related.sh`, `scripts/lib/lib-teamdb.sh`

### SEG-2.1 — Parameterized slug lookup (MUST)
- **Given** a slug `evil'; DROP TABLE memory_links; --`
- **When** the user invokes `bash scripts/teamdb-related.sh "evil'; DROP TABLE memory_links; --" concept`
- **Then** the script SHALL escape the slug via `teamdb_safe_query` parameter binding
- **And** `memory_links` SHALL remain intact

### SEG-2.2 — Whitelist for table type (MUST)
- **Given** a user invokes `bash scripts/teamdb-related.sh slug "concept'"`
- **When** the script switches on type
- **Then** it SHALL match against a hardcoded whitelist (`concept`, `decision`, `preference`, `problem`)
- **And** any other input SHALL exit with code 2 and message "Invalid type"

### SEG-2.3 — Memory_tags and memory_links queries use placeholders (MUST)
- **Given** the script joins `memory_tags` with `concepts`
- **When** the JOIN uses `memory_id` from the lookup result
- **Then** the JOIN SHALL use a parameter placeholder (`?`) bound to the integer ID
- **And** the integer SHALL be validated as positive before binding

---

## Spec SEGURIDAD-3 — FTS5 Search for Known Problems

**Spec ID:** SEG-3
**Implements AC:** 1.3
**File:** `sql/project-schema.sql`, `scripts/teamdb-search.sh`

### SEG-3.1 — Add FTS5 virtual table for problems (MUST)
- **Given** the schema is regenerated
- **When** the schema applies
- **Then** a virtual table `problems_fts` SHALL exist with columns `(title, symptom_md, workaround_md)` and `content='known_problems'`
- **And** triggers `problems_fts_ai/ad/au` SHALL keep it synced with `known_problems`

### SEG-3.2 — Use correct FTS table in search (MUST)
- **Given** the user searches with type=problems
- **When** `teamdb-search.sh` builds the query
- **Then** it SHALL query `problems_fts`, NOT `concepts_fts`
- **And** results SHALL be rows from `known_problems` whose FTS-indexed content matches

### SEG-3.3 — Fallback to LIKE if FTS5 unavailable (SHOULD)
- **Given** SQLite version < 3.9 (no FTS5)
- **When** the user invokes search with type=problems
- **Then** the script SHALL fallback to `LIKE '%query%'` against `symptom_md` and `workaround_md`
- **And** a warning SHALL be printed once per session: "FTS5 unavailable, using LIKE fallback"

---

## Spec INSTALACIÓN-1 — Copy all teamdb scripts to global

**Spec ID:** INST-1
**Implements AC:** 2.1
**File:** `install-global.sh`

### INST-1.1 — Extended script list (MUST)
- **Given** `install-global.sh` runs
- **When** `install_teamdb()` is called
- **Then** it SHALL copy to `~/.config/opencode/scripts/`: `teamdb-init.sh`, `teamdb-migrate.sh`, `teamdb-export.sh`, `teamdb-import.sh`, `teamdb-amend.sh`, `teamdb-resume.sh`, `teamdb-execute-plan.sh`, `teamdb-plan.sh`, `teamdb-status.sh`, `teamdb-graph.sh`, `teamdb-search.sh`, `teamdb-related.sh`, `wip-tree.sh`
- **And** it SHALL copy `scripts/lib/lib-teamdb.sh` to `~/.config/opencode/scripts/lib-teamdb.sh`

### INST-1.2 — Install all hooks (MUST)
- **Given** `install-global.sh` runs
- **When** `install_teamdb_hooks()` is called
- **Then** it SHALL copy ALL files from `scripts/hooks/` to `~/.config/opencode/hooks/`
- **And** it SHALL make them executable (`chmod +x`)
- **And** the destination directory SHALL be created if absent

### INST-1.3 — Dry-run shows all paths (MUST)
- **Given** `install-global.sh --dry-run`
- **When** output is inspected
- **Then** every file mentioned in INST-1.1 and INST-1.2 SHALL appear in the dry-run output

---

## Spec INSTALACIÓN-2 — Robust hook paths

**Spec ID:** INST-2
**Implements AC:** 2.2, 2.3
**File:** `scripts/hooks/pre-commit`, `scripts/hooks/post-merge`

### INST-2.1 — Hooks use absolute paths via git rev-parse (MUST)
- **Given** a hook is executed from `.git/hooks/`
- **When** the hook resolves the `teamdb-export.sh` path
- **Then** it SHALL compute `PROJECT_ROOT="$(git rev-parse --show-toplevel)"` first
- **And** it SHALL call `"$PROJECT_ROOT/scripts/teamdb-export.sh" "$PROJECT_ROOT"` (or the global installed path)
- **And** it SHALL NOT rely on `$SCRIPT_DIR/../` or other relative paths

### INST-2.2 — Pre-commit adds .sql files to staging (MUST)
- **Given** the pre-commit hook runs and team.db is present
- **When** `teamdb-export.sh` produces `data_*.sql` files
- **Then** the hook SHALL `git add` only files under `$PROJECT/.opencode/context/teamdb/data_*.sql`
- **And** it SHALL NOT error if no `.sql` files exist (DB was empty)

### INST-2.3 — Post-merge imports with strict error handling (MUST)
- **Given** the post-merge hook runs and `.sql` files exist in `.opencode/context/teamdb/`
- **When** `teamdb-import.sh` is called
- **Then** any non-zero exit code from the import SHALL propagate to the hook (no `|| true`)
- **And** the hook SHALL print to stderr with a clear error message
- **And** git merge SHALL fail visibly

### INST-2.4 — Hooks are no-op if DB absent (SHOULD)
- **Given** neither team.db nor teamdb/ directory exists in project
- **When** a hook runs
- **Then** it SHALL exit 0 silently (no DB = no work)

---

## Spec VERSION-1 — Single source of version

**Spec ID:** VER-1
**Implements AC:** 3.1, 3.2
**File:** `VERSION`, `README.md`, `sql/project-schema.sql`, `sql/global-schema.sql`, `setup-team-doctor.sh`

### VER-1.1 — VERSION is single source (MUST)
- **Given** the project root has a `VERSION` file
- **When** any other file needs to reference the version
- **Then** it SHALL read it from `VERSION` at build time, runtime, or via shell substitution
- **And** no other file SHALL contain a hardcoded version string

### VER-1.2 — Schema version reads VERSION (MUST)
- **Given** `sql/project-schema.sql` is regenerated
- **When** `INSERT INTO schema_meta VALUES ('version', ?)` is written
- **Then** the value SHALL be derived from `VERSION` at generation time (via generator script or sed in CI)
- **And** the manual `UPDATE schema_meta SET value='0.7.1'` line SHALL be removed (replaced by generator)

### VER-1.3 — README mentions VERSION dynamically (MUST)
- **Given** `README.md` is generated/copied
- **When** the "Versión actual" line is written
- **Then** it SHALL be derived from `VERSION`
- **And** a CI check SHALL fail if a hardcoded version appears in README

### VER-1.4 — Doctor checks coherence (MUST)
- **Given** `setup-team-doctor.sh` runs
- **When** `check_teamdb()` compares `team.db.schema_meta.version` with `VERSION`
- **Then** if they differ, doctor SHALL print a warning with the diff and a remediation command
- **And** exit code SHALL be non-zero under `--strict`

---

## Spec CICLO-1 — Plan/Proposal/Spec/Tasks/DesignNotes Lifecycle

**Spec ID:** CIC-1
**Implements AC:** 4.1, 4.2, 4.3, 4.4, 4.5
**Files:** `scripts/teamdb-plan.sh`, `scripts/teamdb-status.sh`, `scripts/teamdb-amend.sh`, `scripts/teamdb-resume.sh`, `scripts/teamdb-execute-plan.sh`

### CIC-1.1 — teamdb-plan.sh creates full hierarchy (MUST)
- **Given** a user invokes `bash scripts/teamdb-plan.sh /path/to/project auth-jwt "Auth feature" tasks.md`
- **When** the script runs
- **Then** it SHALL create rows in: `proposals` (status=draft), `plans` (status=draft, linked to proposal), `tasks` (one row per task in tasks.md, status=pending, linked to plan)
- **And** it SHALL NOT touch `work_in_progress` (legacy)

### CIC-1.2 — teamdb-amend.sh updates plan in place (MUST)
- **Given** a plan exists with status=draft or active
- **When** the user invokes `bash scripts/teamdb-amend.sh auth-jwt --add-task "Y"`
- **Then** a new row in `tasks` SHALL be inserted (status=pending)
- **And** the plan's `updated_at` SHALL be set to now
- **And** an `audit_log` entry SHALL be added with `action='amend'`

### CIC-1.3 — teamdb-resume.sh shows last state (MUST)
- **Given** a plan exists with tasks in various statuses
- **When** the user invokes `bash scripts/teamdb-resume.sh auth-jwt`
- **Then** the output SHALL show: plan title/status, list of tasks grouped by status (pending/in_progress/resolved/blocked), last audit entry, suggested next task
- **And** the next task SHALL be the lowest-order_index pending task

### CIC-1.4 — teamdb-execute-plan.sh marks tasks in_progress (MUST)
- **Given** a user invokes `bash scripts/teamdb-execute-plan.sh auth-jwt --task task-endpoint`
- **When** the script runs
- **Then** the task's `status` SHALL be set to `in_progress`, `owner=teo`, `started_at=now`
- **And** it SHALL NOT execute any external commands (no shell automation)
- **And** an `audit_log` entry SHALL be added with `action='start'`

### CIC-1.5 — teamdb-status.sh summary (MUST)
- **Given** a project DB exists
- **When** the user invokes `bash scripts/teamdb-status.sh /path/to/project`
- **Then** the output SHALL show: active plans count, pending tasks per plan, blocked tasks count, recent audit entries (last 5)
- **And** it SHALL exit 0 always

### CIC-1.6 — work_in_progress is legacy only (MUST)
- **Given** `scripts/wip-tree.sh` reads `work_in_progress`
- **When** any NEW script under `scripts/teamdb-*.sh` (added by this change) needs to operate on plans
- **Then** it SHALL use `plans` and `tasks` tables, NOT `work_in_progress`
- **And** `wip-tree.sh` is grandfathered (legacy visualizer)

---

## Spec WRITE-1 — Safe write helpers

**Spec ID:** WRI-1
**Implements AC:** 5.1, 5.2, 5.3
**File:** `scripts/lib/lib-teamdb.sh`

### WRI-1.1 — teamdb_write_global symmetric (MUST)
- **Given** `lib-teamdb.sh` is sourced
- **When** the user invokes `teamdb_write_global "UPDATE ..."`
- **Then** the function SHALL validate the global DB path exists
- **And** it SHALL acquire flock on `team.db.lock` with 5s timeout
- **And** it SHALL execute the SQL atomically
- **And** if flock fails, it SHALL return non-zero with `[ERROR] No lock`

### WRI-1.2 — Actor parameter for audit (MUST)
- **Given** `teamdb_write_project` or `teamdb_write_global` is called
- **When** `TEAMDB_ACTOR` environment variable is set (e.g., `export TEAMDB_ACTOR=sol`)
- **Then** the function SHALL prepend `INSERT INTO audit_log (ts, agent, action, table_name) VALUES (datetime('now'), '$TEAMDB_ACTOR', 'mutate', '<table>');` to the SQL
- **And** if `TEAMDB_ACTOR` is unset, the function SHALL use literal `'unknown'`

### WRI-1.3 — Reject unsafe patterns in SQL (MUST)
- **Given** a script calls `teamdb_write_project "$db" "$sql"`
- **When** `$sql` contains `;.*(DROP|DELETE|UPDATE|INSERT).*--` (comment-out attack pattern) OR multi-statement `;.*;`
- **Then** the function SHALL reject the input with `[ERROR] Unsafe SQL pattern`
- **And** it SHALL NOT execute the SQL

### WRI-1.4 — Documented || true exceptions (MUST)
- **Given** the teamdb scripts need resilience in some edge cases (e.g., DB doesn't exist yet on first init)
- **When** `|| true` is used
- **Then** the line SHALL have an inline comment `# OK: <reason>` explaining why
- **And** `tests/write-helpers.test.sh` SHALL grep for undocumented `|| true` and fail

---

## Spec AGENT-1 — TeamDB integration in Alex and Jes

**Spec ID:** AGE-1
**Implements AC:** 6.1, 6.2, 6.3
**Files:** `agents-base/Alex.md`, `agents-base/Jes.md`

### AGE-1.1 — Alex Session Start uses TeamDB (MUST)
- **Given** Alex starts a session in a project with `.opencode/context/team.db`
- **When** the Session Start Protocol runs
- **Then** Alex SHALL first query `teamdb_query_project "SELECT slug, title FROM concepts ORDER BY updated_at DESC LIMIT 10"`
- **And** Alex SHALL query decisions in `accepted` status
- **And** Alex SHALL fallback to legacy `.md` index ONLY if team.db is absent

### AGE-1.2 — Alex OKF Checkpoint prefers TeamDB (MUST)
- **Given** Alex runs the OKF Checkpoint
- **When** the checkpoint needs to verify "bundle válido"
- **Then** it SHALL check `teamdb_query_project "SELECT value FROM schema_meta WHERE key='version'"` and compare with `VERSION`
- **And** it SHALL use the result as primary source of bundle validity

### AGE-1.3 — Jes PASO 0 uses TeamDB (MUST)
- **Given** Jes is invoked to explain something in a project with team.db
- **When** PASO 0 runs
- **Then** Jes SHALL query `teamdb_query_project "SELECT title, body_md FROM concepts WHERE category='concept' OR category='pattern' LIMIT 20"`
- **And** Jes SHALL query relevant decisions via FTS
- **And** the legacy `.opencode/context/index.md` read SHALL be a fallback only

### AGE-1.4 — Audit test for agent-teamdb integration (MUST)
- **Given** all 8 agents exist
- **When** `tests/agents-teamdb-integration.test.sh` runs
- **Then** it SHALL grep each agent for `teamdb_query_project` OR `teamdb_query_global` OR explicit comment `# teamdb-N/A: <reason>`
- **And** it SHALL fail if any agent lacks both

---

## Spec SNIPPET-1 — Single Source Snippets

**Spec ID:** SNP-1
**Implements AC:** 7.1, 7.2
**Files:** `agents-base/*.md`, `templates/agents/snippets/*.md`

### SNP-1.1 — Remove duplicated Code Intelligence body (MUST)
- **Given** the 8 agents contain inline Code Intelligence snippet bodies
- **When** the deduplication change is applied
- **Then** each agent SHALL contain only a marker line: `<!-- @include-snippet code-intelligence -->` followed by a 1-line reference
- **And** the body of the snippet SHALL exist ONLY in `templates/agents/snippets/code-intelligence.md`

### SNP-1.2 — Remove duplicated Memory Protocol body (MUST)
- **Given** the 8 agents contain inline Memory Protocol snippet bodies
- **When** the deduplication change is applied
- **Then** each agent SHALL contain only a marker line: `<!-- @include-snippet memory-protocol -->`
- **And** the body SHALL exist ONLY in `templates/agents/snippets/memory-protocol.md`

### SNP-1.3 — Build-time snippet inclusion (SHOULD)
- **Given** agents are installed to `~/.config/opencode/agents/`
- **When** `install_agents()` runs
- **Then** it SHALL resolve `<!-- @include-snippet NAME -->` markers by reading `templates/agents/snippets/NAME.md` and inlining the content
- **And** the installed agent files SHALL contain the full snippets (so opencode runtime does not need to resolve)

### SNP-1.4 — Sync verification test (MUST)
- **Given** `tests/snippets-sync.test.sh` runs
- **When** the test computes a hash of each canonical snippet
- **Then** it SHALL compare with the hash of the corresponding inlined section in each agent (post-install)
- **And** it SHALL fail if any agent's inlined snippet differs from the canonical

### SNP-1.5 — OpenCode runtime fallback (MAY)
- **Given** opencode loads agent files directly without a build step
- **When** an agent file contains `<!-- @include-snippet NAME -->` markers unresolved
- **Then** opencode MAY ignore the markers (markdown comments are ignored) and the agent SHALL still function
- **And** the test SHALL verify this by running opencode on a mock agent with markers

---

## Spec AUDIT-1 — Reliable audit_log with real agent

**Spec ID:** AUD-1
**Implements AC:** 8.1, 8.2
**Files:** `sql/project-schema.sql`, `sql/global-schema.sql`, `scripts/teamdb-export.sh`, `scripts/teamdb-import.sh`

### AUD-1.1 — Triggers read actor from session var (MUST)
- **Given** SQLite supports session variables via `sqlite3_set_authorizer` or pragma
- **When** `teamdb_write_project` runs
- **Then** it SHALL set `PRAGMA actor = '<actor>'` before the write
- **And** the triggers SHALL read `PRAGMA actor` via a custom function or `sqlite3_db_config` mechanism
- **Implementation note**: if pure SQL triggers cannot read PRAGMA, fallback is to write `audit_log` directly from the helper (skip triggers for actor field) — see AUD-1.3.

### AUD-1.2 — Triggers record actor (MUST)
- **Given** a `INSERT/UPDATE/DELETE` happens on `concepts`/`decisions`/`work_in_progress`/`known_problems`
- **When** the trigger fires
- **Then** `audit_log.agent` SHALL be the actor from `TEAMDB_ACTOR` env OR `pragma actor` value
- **And** it SHALL NOT be the literal `'system'` (which is reserved for migrations and schema changes)

### AUD-1.3 — Export includes audit_log and schema_meta (MUST)
- **Given** `teamdb-export.sh` runs
- **When** it dumps tables
- **Then** it SHALL dump in this order: `schema_meta`, `audit_log` (last 1000 entries), then `concepts`, `decisions`, `preferences`, `known_problems`, `memory_tags`, `memory_links`
- **And** the dump SHALL use `.dump --no-data` for `schema_meta` (only the value rows)

### AUD-1.4 — Import handles audit_log idempotently (MUST)
- **Given** `teamdb-import.sh` runs against a DB that already has `audit_log` rows
- **When** the dump is imported
- **Then** duplicate `audit_log` rows (by ts + agent + action + table_name + row_id) SHALL be skipped via `INSERT OR IGNORE` or pre-filter
- **And** the import SHALL NOT fail

---

## Spec HANDOFF-1 — Runtime validation of handoff schema

**Spec ID:** HAN-1
**Implements AC:** 9.1, 9.2, 9.3
**Files:** `templates/handoff.schema.json`, `tests/handoff-schema-validation.test.sh`

### HAN-1.1 — Conditional required fields (MUST)
- **Given** `templates/handoff.schema.json` defines a handoff
- **When** the schema is evaluated
- **Then** it SHALL use `allOf` with `if/then` clauses:
  - If `to` ∈ {TEO, LUZ} → `project_context` is required
  - If `to` ∈ {JHON, LUZ} → `verification` is required
  - If `from` ∈ {TEO, JHON, LUZ} → `verification` is required (sender provides evidence)
- **And** the schema SHALL be valid JSON Schema draft 2020-12

### HAN-1.2 — Test rejects TEO handoff without project_context (MUST)
- **Given** a JSON handoff `{from: SOL, to: TEO, task: "...", summary: "...", next_action: "..."}` WITHOUT `project_context`
- **When** `tests/handoff-schema-validation.test.sh` validates it against the schema
- **Then** the validation SHALL fail
- **And** the test SHALL exit non-zero

### HAN-1.3 — Test rejects JHON handoff without verification (MUST)
- **Given** a JSON handoff `{from: TEO, to: JHON, ...}` WITHOUT `verification`
- **When** the schema validates it
- **Then** validation SHALL fail

### HAN-1.4 — Backward-compatible examples (SHOULD)
- **Given** the schema has examples at the end
- **When** examples are validated
- **Then** each example SHALL satisfy the conditional requirements (each example fills its required fields)

---

## Spec CI-1 — CI runs all TeamDB tests

**Spec ID:** CI-1
**Implements AC:** 10.1, 10.2, 10.3
**File:** `.github/workflows/tests.yml`, new files `.github/workflows/teamdb.yml`, `.github/workflows/handoffs.yml`

### CI-1.1 — teamdb tests in main matrix (MUST)
- **Given** `.github/workflows/tests.yml` has a `test` job with bash 3/4/5 matrix
- **When** the test job runs
- **Then** it SHALL execute `bash tests/setup.test.sh && bash tests/teamdb.test.sh && bash tests/teamdb-cycle.test.sh`
- **And** it SHALL fail the job if any suite fails

### CI-1.2 — SQL injection tests in dedicated workflow (MUST)
- **Given** a new workflow `.github/workflows/teamdb-sqli.yml` is added
- **When** it runs on PR
- **Then** it SHALL execute `bash tests/teamdb-search-sqli.test.sh && bash tests/teamdb-related-sqli.test.sh`
- **And** it SHALL fail if either suite fails

### CI-1.3 — Handoff validation in CI (MUST)
- **Given** a new workflow `.github/workflows/handoffs.yml` is added
- **When** it runs on PR
- **Then** it SHALL execute `bash tests/handoff-schema-validation.test.sh` and `bash tests/agents-teamdb-integration.test.sh`
- **And** it SHALL fail if either fails

---

## Spec MIGRACIÓN-1 — Robust migration of legacy content

**Spec ID:** MIG-1
**Implements AC:** 11.1, 11.2
**File:** `scripts/teamdb-migrate.sh`

### MIG-1.1 — Frontmatter extraction (MUST)
- **Given** a `.opencode/context/concept/foo.md` with frontmatter `type: Concept, tags: [auth, jwt], confidence: 0.9`
- **When** `teamdb-migrate.sh` runs
- **Then** it SHALL parse the YAML frontmatter and store:
  - `concepts.body_md` ← body content (after frontmatter)
  - `concepts.category` ← `type` value (lowercase)
  - `memory_tags` ← one row per tag in `tags` array
  - `concepts.category` ← `confidence` if available (else default 0.8)
- **And** it SHALL NOT remove the `.md` file (preserved for export readability)

### MIG-1.2 — Idempotent migration (MUST)
- **Given** a `.jsonl` file is migrated to DB
- **When** `teamdb-migrate.sh` runs a second time on the same project
- **Then** existing rows SHALL be skipped (`INSERT OR IGNORE` based on unique slug)
- **And** new rows SHALL be inserted
- **And** no duplicate slugs SHALL be created

### MIG-1.3 — Exit 0 with warning on empty legacy (MUST)
- **Given** `.opencode/context/` exists but has NO `.jsonl` files
- **When** `teamdb-migrate.sh` runs
- **Then** it SHALL print `warn: no legacy .jsonl files to migrate` to stderr
- **And** it SHALL exit 0 (not error)
- **And** it SHALL still initialize the DB if not present

### MIG-1.4 — Move .jsonl to legacy/ only after success (MUST)
- **Given** migration succeeds
- **When** the script moves `.jsonl` to `legacy/`
- **Then** it SHALL use `mv` (atomic) not `cp`
- **And** if `mv` fails, the script SHALL warn but not error (DB is the source of truth)

---

## Spec PORT-1 — Bash 3.2 portability

**Spec ID:** POR-1
**Implements AC:** 12.1
**File:** `tests/portability-bash32.test.sh`

### POR-1.1 — Test suite runs in bash 3.2 mode (MUST)
- **Given** `tests/portability-bash32.test.sh` runs with bash >= 4
- **When** the test mocks `BASH_VERSINFO[0]=3` via `env BASH_VERSION_MOCK=3` and runs `bash --version` checks
- **Then** it SHALL execute all teamdb scripts and verify exit 0
- **And** it SHALL grep for forbidden patterns: `declare -A`, `readarray`, `[[ -v ]]`, `local -n`, `${var,,}`, `${var^^}`, `mapfile`
- **And** it SHALL fail if any pattern is found in any `scripts/teamdb-*.sh`

### POR-1.2 — Run scripts under actual bash 3.2 if available (SHOULD)
- **Given** the CI matrix includes `bash: '3'`
- **When** the test job runs with bash 3
- **Then** all scripts SHALL be invoked and verified exit 0
- **And** no test failures specific to bash version SHALL occur

---

*Specs generated by Pol. Each spec is independently testable. Tests live in `tests/teamdb-<area>.test.sh`.*
