# Skills

Skills are slash-command capabilities the crew invokes at the right moments. They live
flat at `.claude/skills/<name>/SKILL.md` (one folder per skill, the `SKILL.md` is required
— a nested layout will not be picked up).

This kit references a set of skills the agents are wired to call. They split into two
groups: the **method-critical** ones (the workflow leans on them) and the **optional**
productivity ones. Install the ones you want; the agents degrade gracefully if a skill is
absent (they just won't auto-invoke it).

## Method-critical (recommended)

| Skill | Who invokes it | Why it matters to the method |
|---|---|---|
| `interrogate-plan` | `lead-agent`, `architect` | Front-loads decisions against your `CONTEXT.md` + ADRs, updating them inline. This is habit #1 made executable — the single highest-leverage skill. |
| `draft-prd` | `lead-agent`, `architect` | Turns converged decisions into a PRD before any lead builds. |
| `slice-issues` | `lead-agent` | Breaks a plan into tracer-bullet vertical slices — one slice = one dev-lead. |
| `test-first` | `dev-lead` | Red-green-refactor; the default build loop where a test seam exists. |
| `troubleshoot` | `dev-lead` | Disciplined debugging loop for hard bugs / perf regressions. |
| `context-handoff` | all long-running leads | Compacts in-flight work so a fresh instance resumes cleanly — the thing that makes long tasks survivable. |
| `orient` | onboarding (Loop 1) | Generates a real `CONTEXT.md` from the actual code — the orientation half of the context contract, and the highest-leverage artifact in the kit. The wow-moment for an existing repo. |
| `remember` | learning loop (Loop 2) | Persists a correction/decision/preference to its right home (rule / orientation / ADR / memory), proposing tracked edits first. The back-flow that makes the crew auto-grow. |

## Optional (productivity)

| Skill | Use |
|---|---|
| `stress-test` | Lighter grilling when there's no `CONTEXT.md` to anchor on yet. |
| `mockup` | Throwaway prototype to settle a state machine / data shape / UI choice. |
| `survey-code` | Get a module/caller map in domain vocabulary before touching unfamiliar code. |
| `deepen-architecture` | Find deepening/refactoring opportunities informed by `CONTEXT.md` + ADRs. |
| `sort-issues` | Run an incoming-issue queue through a triage state machine. |
| `founder-checklist` | Track the founder-only external/business actions an agent can't do (accounts, KYC, licenses, legal, domains, prod sign-offs). Sources `founder`-labelled issues on the crew's board; renders a lead-time status board; propose-only. |
| `bootstrap-skills` | One-time bootstrap for the issue tracker + label vocabulary the publishing skills use. |
| `terse-mode` | Ultra-terse mode to save context on long sessions. |
| `author-skill` | Author new skills with proper structure. |
| `cross-team-request` | Create a structured requirement sheet + linked GitHub issue for cross-team handoffs. Use when your team is blocked on or needs work from another team. Routes through skills-config.json for repo/directory/labels. |

## Where to get them

Many of these are community/Anthropic skills (e.g. the
[Claude Code skills ecosystem](https://github.com/anthropics/claude-code) and
collections like `mattpocock/skills`). Drop each skill's folder into `.claude/skills/`.

This kit **bundles** the keystone, `interrogate-plan`, as a worked example of the expected
structure and because the method depends on it. Author or import the rest to taste.

## The contract every skill follows

- Lives at `.claude/skills/<name>/SKILL.md` (flat, not nested).
- Frontmatter has a `name` and a `description` that says *when* to use it (the description
  is how the agent decides to invoke it).
- Bundles any helper scripts/templates it needs alongside the `SKILL.md`.
