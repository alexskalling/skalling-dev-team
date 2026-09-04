---
name: skalling-receipt
description: "Trigger: verification, completion, done, passing, evidence, proof, test, build, verify, quality gate. Formalizes verification into a verifiable receipt."
license: MIT
metadata:
  author: skalling-team
  version: "1.0"
---

# Skalling Receipt — Formal Verification Contract

## Activation Triggers

Load when:
- About to claim work is complete
- Before any delivery gate (commit, push, PR)
- After any test, build, or verification
- Agent reports "done", "passing", "complete"

## Hard Rules

1. **No claim without command output.** Assertion without running command is fraud.
2. **Receipt is immutable once issued.** Cannot retroactively edit.
3. **Every route produces a receipt.** No exceptions.
4. **Receipt gates delivery.** No commit without valid receipt.

## Decision Gates

| Condition | Action |
| --- | --- |
| Command not run | RUN FIRST — cannot claim anything |
| Command failed | ISSUE REJECTION — not done |
| Command passed | ISSUE RECEIPT — with evidence |
| Partial verification | COMPLETE VERIFICATION — no partial receipts |

## Receipt Schema

```json
{
  "receipt_id": "rcpt_YYYYMMDDHHMMSS",
  "timestamp": "ISO8601",
  "route": "INLINE|INTERVENTION|FAST-TRACK|SDD",
  "verdict": "PASS|FAIL|REJECTED",
  "verification": {
    "type": "test|build|lint|security|manual",
    "command": "exact command run",
    "output_summary": "last 5 lines",
    "exit_code": 0|1
  },
  "artifacts": ["files changed"],
  "coverage": 0-100,
  "rejection_reasons": [] | null
}
```

## Verification Types

### TEST Verification

```
REQUIRED: Test command output (full, not truncated)
ACCEPTABLE: vitest, pytest, npm test, cargo test, go test
NOT ACCEPTABLE: "tests pass", "should work"
```

**Receipt format:**
```json
{
  "verification": {
    "type": "test",
    "command": "bun test src/auth/login.test.ts",
    "output_summary": "✓ login.test.ts (5 tests) - 12ms",
    "exit_code": 0,
    "tests_total": 5,
    "tests_passed": 5,
    "tests_failed": 0
  }
}
```

### BUILD Verification

```
REQUIRED: Build command with exit code
ACCEPTABLE: npm run build, cargo build, python -m build
NOT ACCEPTABLE: "builds locally", "no errors"
```

**Receipt format:**
```json
{
  "verification": {
    "type": "build",
    "command": "npm run build",
    "output_summary": "Route built: /login - 45ms",
    "exit_code": 0
  }
}
```

### LINT Verification

```
REQUIRED: Linter output with exit code
ACCEPTABLE: eslint, ruff, golangci-lint, clippy
NOT ACCEPTABLE: "linter passes"
```

### SECURITY Verification (Luz gate)

```
REQUIRED: Security scan output
ACCEPTABLE: npx audit, snyk, trivy
FOR FRONTEND: npx impeccable detect src/
```

### MANUAL Verification

Used when human must approve:
```
REQUIRED: Human sign-off documented
FORMAT: "User approved: [description] at [timestamp]"
```

## Rejection Patterns

| Pattern | Verdict | Action |
| --- | --- | --- |
| Test failed | FAIL | Do not deliver |
| Build failed | FAIL | Do not deliver |
| Coverage < 80% | FAIL | Add tests |
| Security finding | FAIL | Fix before delivery |
| Rejection from Jhon/Luz | REJECTED | Correct and re-verify |

## Receipt Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│  ISSUING                                                  │
│  Agent runs verification → passes → issues receipt       │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  VALIDATING                                               │
│  Next agent (Jhon/Luz) validates receipt authenticity    │
│  - Command was actually run                             │
│  - Output matches claim                                   │
│  - Exit code is correct                                  │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  GATING                                                  │
│  Receipt required for: commit, push, PR, phase advance    │
│  No receipt = no gate passed                             │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  ARCHIVING                                               │
│  Receipt stored in: .opencode/changes/<slug>/receipts/  │
│  Format: receipt_YYYYMMDDHHMMSS.json                    │
└─────────────────────────────────────────────────────────────┘
```

## Delivery Gates

| Gate | Receipt Required |
| --- | --- |
| Teo → Jhon (per task) | YES |
| Jhon → Luz (regression) | YES |
| Luz → Pau (quality gate) | YES |
| Commit | YES |
| Push | YES |
| PR | YES |

## Anti-Patterns

| Anti-pattern | Detection | Correct |
| --- | --- | --- |
| "Tests pass" without running | No command in receipt | Run command first |
| Partial coverage claimed | coverage < actual | Full verification |
| Stale receipt used | timestamp > 1 hour | Re-verify |
| Receipt edited after issue | Hash mismatch | Immutable - issue new |

## When To Issue

**AFTER:**
- Test suite runs green
- Build succeeds
- Lint passes
- Security scan clean
- Manual approval received

**NEVER:**
- Before running command
- Based on assumption
- Because "should work"
- After partial check

## Receipt Storage

Location: `.opencode/changes/<slug>/receipts/`

Naming: `receipt_<task>_<timestamp>.json`

Example:
```
.opencode/changes/auth-jwt/receipts/
├── receipt_task1.1_20260803_143022.json
├── receipt_task1.2_20260803_143255.json
└── receipt_regression_20260803_144500.json
```

## Integration with Engram

After issuing receipt, optionally save to Engram:
```
mem_save({
  type: "task_completion",
  content: "Completed auth login. Receipt: rcpt_xxx. Tests: 5/5 pass."
})
```

---

## Final Check

Before any delivery claim, verify:

1. ✅ Command run (evidence in receipt)
2. ✅ Output confirmed (summary in receipt)
3. ✅ Exit code verified (0 for pass)
4. ✅ Receipt issued (JSON stored)
5. ✅ Gate passed (delivery authorized)

**No delivery without all five.**
