# The crew

The agents that make up `crew-for-claude`. Drop this folder into your project's
`.claude/agents/`. The `lead-agent` is a **role the main session plays** — never spawn it
as a sub-agent. Everything else is a real spawnable sub-agent.

## Roster

| Agent | Tier | Role |
|---|---|---|
| `lead-agent` | Opus (main session) | Orchestrator — decomposes, routes to leads, integrates, reports. A ROLE, not a spawn target. |
| `architect` | Opus | Cross-cutting design BEFORE code. Produces an architecture brief. Doesn't write code. |
| `dev-lead` | Sonnet | Owns a development slice end-to-end + the quality pipeline. |
| `design-lead` | Sonnet | UI/UX, API contracts, schemas, wireframes (text/mermaid/SVG). |
| `devops-lead` | Sonnet | CI/CD, IaC, deploy, observability. Non-local actions gated behind typed user approval. |
| `test-lead` | Sonnet | Test strategy + QA. No fixer — failures route back up. |
| `security-lead` | Opus | Authorized security work only. No fixer — findings route back up. |
| `research-lead` | Sonnet | Feasibility, standards, market scans. Time-boxed reports, not code. |
| `media-lead` | Sonnet | Content copy, image briefs, brand voice. Doesn't render bitmaps. |
| `junior-worker` | Haiku | Bounded sub-tasks under a lead. Never delegates further. |
| `critic` | Sonnet | First quality gate — produces a structured issue list. |
| `fixer` | Sonnet | Resolves critic findings without scope creep. |
| `auditor` | Opus | Final independent verdict (APPROVED / CONDITIONAL / REJECTED). |
| `tester` | Haiku | Executes tests + collects evidence under `test-lead`. |
| `pentester` | Sonnet | Authorized active security testing under `security-lead`, within scope. |

## Routing in one picture

```
user → lead-agent (main session)
         ├─ architect (design-first, for cross-cutting work)
         └─ a domain lead (dev/design/devops/test/security/research/media)
                  ├─ junior-worker (bounded tasks)
                  └─ critic → fixer → auditor (the quality pipeline)
```

## Tier discipline (the cost lever)

Haiku for mechanical work, Sonnet for slices, Opus only where being wrong is expensive
(orchestration, architecture, the final audit, security). A review gate fires identically
regardless of model — don't pay top-tier prices for mid-tier work. See
[../../docs/THE-METHOD.md](../../docs/THE-METHOD.md) habit #2.

## Customizing

The model tiers in each agent's frontmatter are a sensible default — adjust to your
budget. The names are paint; the roles and routing are the method. If you rename agents,
update the cross-references in `lead-agent.md` and `docs/AGENT-WORKFLOW.md`.
