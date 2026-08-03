---
name: skalling-memory
description: "Trigger: memory, context, remember, project history, past decisions, previous work, learned, known. Self-hosted memory using local files — Engram-style without external service."
license: MIT
metadata:
  author: skalling-team
  version: "1.0"
---

# Skalling Memory — Self-Hosted Engram-Style Memory

## Overview

Engram-style memory using local files. No external service required. Works with OpenCode native file system.

**Principle:** Memory should reduce context loading time, not add overhead. Each memory save = one line summary. Each recall = < 10 lines.

## Hard Rules

1. **One line per memory.** No essays, no logs, no trivia.
2. **Memory is for context, not storage.** Only save what affects decisions.
3. **Recall before acting.** Every agent starts with context load.
4. **Memory never replaces verification.** Saved decisions can be overridden.

## Memory Types

### DECISION — Architectural choices that stick

```json
{
  "type": "DECISION",
  "topic": "auth",
  "decision": "JWT with refresh tokens, not sessions",
  "reason": "Stateless. Better for API-first.",
  "date": "2026-07-15",
  "agents": ["Pol", "Sol"]
}
```

### PATTERN — Reusable solutions

```json
{
  "type": "PATTERN",
  "name": "repository-pattern",
  "description": "One repository per aggregate root",
  "example": "UserRepository, OrderRepository",
  "context": "Domain-driven design, TypeScript"
}
```

### PROJECT — Project-specific facts

```json
{
  "type": "PROJECT",
  "key": "db",
  "value": "PostgreSQL via Drizzle ORM",
  "note": "Migrations in /drizzle/"
}
```

### PREFERENCE — User/team preferences

```json
{
  "type": "PREFERENCE",
  "scope": "code-style",
  "preference": "No else statements. Early return only.",
  "enforced_by": "Luz"
}
```

### REJECTION — What didn't work and why

```json
{
  "type": "REJECTION",
  "attempted": "Monorepo with Turborepo",
  "reason": "Overkill for 2 packages. Slowed down CI.",
  "date": "2026-07-20",
  "alternative": "Simple npm workspaces"
}
```

## Decision Gates

| Situation | Action |
| --- | --- |
| New decision made | Save to memory immediately |
| Working on known topic | Load context first |
| Decision being challenged | Retrieve original reasoning |
| Pattern discovered | Save for reuse |

## Memory Files Location

```
.opencode/context/
├── DECISIONS.jsonl    # Architectural decisions
├── PATTERNS.jsonl     # Reusable patterns
├── PROJECT.jsonl      # Project facts
├── PREFERENCES.jsonl  # User preferences
├── REJECTIONS.jsonl   # What didn't work
└── receipts/          # Verification receipts
```

Format: `.jsonl` (JSON Lines) — one JSON object per line. Append-only.

## Memory Operations

### SAVE — Adding a memory

```bash
# Manual save (rarely needed, usually automatic)
echo '{"type":"DECISION","topic":"auth","decision":"JWT","date":"2026-08-03"}' >> .opencode/context/DECISIONS.jsonl
```

**When to save automatically:**
- Sol completes design.md → save key decisions
- Luz rejects something → save rejection reason
- User states preference → save to PREFERENCES
- Pattern identified → save to PATTERNS

### RECALL — Loading context

```bash
# By topic
grep '"topic":"auth"' .opencode/context/DECISIONS.jsonl

# By type
grep '"type":"PATTERN"' .opencode/context/PATTERNS.jsonl

# By date range
grep '2026-07' .opencode/context/DECISIONS.jsonl
```

### SEARCH — Finding related

```bash
# Full-text search across all memory
grep -h "JWT" .opencode/context/*.jsonl

# Recent memories (last 10)
tail -10 .opencode/context/DECISIONS.jsonl
```

## Agent Context Loading Protocol

Every agent MUST load context at start:

```
1. Identify relevant memory types for this task
2. Load DECISIONS for your domain
3. Load PREFERENCES (always)
4. Load recent REJECTIONS if working on similar scope
5. Proceed with work
```

**Example for Teo starting auth work:**
```bash
# Load auth decisions
grep '"topic":"auth"' .opencode/context/DECISIONS.jsonl
# → "JWT with refresh tokens, not sessions"

# Load code preferences
grep '"scope":"code-style"' .opencode/context/PREFERENCES.jsonl
# → "No else statements. Early return only."
```

## Memory Size Budget

| Type | Max entries | Max age |
| --- | --- | --- |
| DECISION | 50 | Forever |
| PATTERN | 30 | Forever |
| PROJECT | 20 | Until stale |
| PREFERENCE | 15 | Forever |
| REJECTION | 20 | 6 months |

**If budget exceeded:** Archive oldest to `.opencode/context/archive/`

## Context vs Memory

| Context (system) | Memory (project) |
|---|---|
| OKF files | DECISIONS.jsonl |
| AGENTS.md | PATTERNS.jsonl |
| SKILL.md files | PREFERENCES.jsonl |
| Project config | REJECTIONS.jsonl |

**Memory augments context, doesn't replace it.**

## Token Optimization

Goal: Reduce context by 80-90% through selective loading.

**Before (no memory):**
- Load all OKF files: ~5000 tokens
- Load all skill files: ~3000 tokens
- Total: ~8000 tokens per task

**After (with memory):**
- Load relevant memories: ~200 tokens
- Load current task context: ~500 tokens
- Total: ~700 tokens per task

**Savings: ~90%**

## Integration with Routing

Memory loads AFTER routing decision:

```
Route: INLINE
→ Load relevant memories only
→ Proceed

Route: SDD
→ Load all memories for this domain
→ Pol starts with context
→ Sol saves decisions at end
```

## Memory Anti-Patterns

| Anti-pattern | Problem | Correct |
| --- | --- | --- |
| Saving logs | Memory bloat | Don't save |
| Saving everything | Noise | Only decisions |
| Not loading | Context loss | Load at start |
| Overriding facts | Confusion | Add new, don't edit |

## Engram vs Self-Hosted

| Feature | Engram (cloud) | Self-hosted (this) |
| --- | --- | --- |
| Search | Semantic | Grep |
| Storage | Cloud | Local files |
| Setup | MCP required | None |
| Cost | Free tier | Free |
| Privacy | Data leaves machine | Data stays local |
| Speed | API latency | Instant |

**This implementation prioritizes privacy and zero-setup over semantic search.**

## Quick Reference

```bash
# Save a decision
echo '{"type":"DECISION","topic":"api","decision":"REST not GraphQL","reason":"Simpler","date":"2026-08-03"}' >> .opencode/context/DECISIONS.jsonl

# Load context for a task
grep '"topic":"auth"' .opencode/context/DECISIONS.jsonl
grep '"type":"PREFERENCE"' .opencode/context/PREFERENCES.jsonl

# Search across all
grep -h "JWT\|auth\|token" .opencode/context/*.jsonl
```

---

**Memory is a second brain, not a diary. Save decisions, not events.**
