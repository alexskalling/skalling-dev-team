---
name: test-driven-development
description: "Trigger: behavior changes, functional bugs and logic refactoring. Use focused RED/GREEN tests; exclude declarative copy, icons and static ordering."
license: Apache-2.0
metadata:
  author: Skalling (adapted from Anthropic Skills)
  version: "0.19.0"
---

## Activation Contract

Load before implementing behavior, a functional bug fix or logic refactoring.
Do not load automatically for every edit or because strict_tdd is true.

## Hard Rules

- For behavior changes, write a focused test, observe the expected failure,
  implement the minimum and observe it pass. A test failing for infrastructure
  reasons is not a valid RED. Never report a test you did not run.
- Preserve validation, security, accessibility and existing user work. Do not delete
  existing implementation or unrelated edits to manufacture a RED-first history.
- Reuse valid evidence. A known unrelated suite failure is not a new baseline.

## Decision Gates

| Change | Verification |
| --- | --- |
| Local reversible copy, icon or static ordering; no logic, routes, data contract, permissions or accessibility change | Inspect affected code and complete diff/result. No bespoke temporary test or RED/GREEN required. This is an explicit exception, including strict_tdd; no additional permission needed. |
| Behavior, transformation, bug or logic | Focused RED/GREEN; compare full expected result and relevant success/fallback cases. |
| Runner unavailable | State the limitation and use the best relevant check; do not claim TDD. |
| Shared or sensitive behavior | Relevant regression coverage and the workflow's assigned review. |

## Execution Steps

1. Identify the observable requirement and affected behavior.
2. Select the smallest meaningful check. Test behavior, not an implementation copy.
3. Observe the expected failure, implement, then verify success.
4. Refactor only within scope. Deliver the check, exit status and result.

## Output Contract

Return concise evidence tied to acceptance and any remaining limitation. Do not
require a full suite, extra role, or generic checklist after criteria are covered.

## References

Load [examples and troubleshooting](references/guide.md) only for a concrete testing
question. The activation contract and exceptions above take precedence.
