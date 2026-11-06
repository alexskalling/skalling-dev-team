---
name: skalling-ponytail
description: "Trigger: nontrivial implementation, new abstraction or dependency, complexity review. Choose the simplest adequate solution after reading affected code."
license: MIT
metadata:
  author: Skalling (inspired by DietrichGebert/ponytail)
  version: "0.19.0"
---

## Activation Contract

Use for substantive implementation choices or a concrete complexity concern.
Do not load for local copy, icons or static ordering without logic changes;
the short simplicity rule in Teo's instructions suffices there.

## Hard Rules

Read the affected code before deciding. Preserve validation, security,
accessibility and error handling. Never reject solely on line count or number of
implementations: explain a concrete defect or unnecessary complexity in scope.

## Decision Gates

Stop at the first adequate solution:
1. Is the requested code necessary?
2. Does the project already provide it?
3. Can the standard library do it?
4. Can the platform do it?
5. Can an installed dependency do it?
6. Is a direct, small implementation adequate?
7. Otherwise implement the minimum required custom behavior.

## Execution Steps

Read the relevant flow, choose and implement the simplest adequate option, then
verify acceptance. Do not generate a seven-step report for each task. Optional
improvements outside scope belong in defer and must not block completion.

## Output Contract

Explain a non-obvious choice briefly. A review rejection identifies concrete
impact and a remedy, not an aesthetic preference or an arbitrary size limit.

## References

Load [extended examples](references/guide.md) only when a specific tradeoff needs
clarification. This contract takes precedence over examples and old templates.
