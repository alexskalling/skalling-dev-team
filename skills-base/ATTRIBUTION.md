# Skills Attribution

Skalling includes skills from external sources. We respect and acknowledge their authors.

## Core Skills (in `skills-base/`)

The following skills come from upstream projects and are included as-is:

| Skill | Source | License | Path |
|-------|--------|---------|------|
| `test-driven-development` | [Anthropic Skills](https://github.com/anthropics/skills) | Apache 2.0 | `skills-base/test-driven-development/` |
| `systematic-debugging` | [Anthropic Skills](https://github.com/anthropics/skills) | Apache 2.0 | `skills-base/systematic-debugging/` |
| `verification-before-completion` | [Anthropic Skills](https://github.com/anthropics/skills) | Apache 2.0 | `skills-base/verification-before-completion/` |
| `brainstorming` | Community | MIT | `skills-base/brainstorming/` |
| `code-review-excellence` | Community | MIT | `skills-base/code-review-excellence/` |
| `doc-coauthoring` | Community | MIT | `skills-base/doc-coauthoring/` |
| `find-skills` | Community | MIT | `skills-base/find-skills/` |
| `writing-plans` | Community | MIT | `skills-base/writing-plans/` |

## Stack-Specific Skills (NOT installed by default, fetched on-demand)

| Skill | Source | License |
|-------|--------|---------|
| `impeccable` | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | MIT |
| `firecrawl` | [mendableai/firecrawl](https://github.com/mendableai/firecrawl) | AGPL-3.0 |
| `next-cache-components` | Community | MIT |
| `shadcn-ui` | [shadcn-ui/ui](https://github.com/shadcn-ui/ui) | MIT |
| `tailwind-design-system` | Community | MIT |
| `vercel-composition-patterns` | Community | MIT |
| `ui-ux-pro-max` | Community | MIT |
| `vitest` | [vitest-dev/vitest](https://github.com/vitest-dev/vitest) | MIT |
| `webapp-testing` | [Microsoft Playwright](https://github.com/microsoft/playwright) | Apache 2.0 |

## Skalling Original Skills

The following skills are original work by the Skalling project:

- `skalling-cycle` — MIT
- `skalling-handoff` — MIT
- `skalling-ponytail` — MIT (inspired by [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail))
- `skalling-impeccable-bridge` — MIT

## Acknowledgments

- **Anthropic Skills** — for foundational engineering practices (TDD, debugging, verification).
- **pbakaus/Impeccable** — for the design vocabulary and AI slop detector.
- **DietrichGebert/ponytail** — for the "lazy senior dev" philosophy and the 7-rung ladder.
- **GoogleCloudPlatform/knowledge-catalog** — for the Open Knowledge Format (OKF) standard.

## Contributing a Skill

If you want to add a new skill to Skalling:

1. Add the skill folder to `skills-base/<name>/` with `SKILL.md`.
2. Add an entry to `data/skills-by-stack.yaml` if it's stack-specific.
3. Update this ATTRIBUTION.md with source, license, and path.
4. Run `bash tests/setup.test.sh` to verify.
5. Open a PR.

**Important**: only include skills whose licenses are compatible with Skalling's MIT license.
