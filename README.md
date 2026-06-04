# Crew for Claude

**A portable operating-model framework for running Claude Code as a small software org —
now with an auto-learning, auto-growing workspace.**

This is not a prompt pack. It is not an autocomplete helper. It is a complete framework
that drops into any codebase and gives you a functioning software organisation with
structured roles, quality gates, tiered cost controls, and a workspace that gets
smarter every session without requiring you to babysit it.

It has been used to build a real multi-service platform across multiple repositories. This
repo is that machinery, genericized so you can install it in any codebase — a brand new
repo or an existing one — in a few minutes.

---

## The marquee feature: back-flow

The framework's existing mechanisms (context contract, tiered routing, quality pipeline,
human merge gate) are all **forward flow** — a human invokes a skill, agents produce output,
the human merges. Everything is pull; nothing happens unless someone runs it.

**This release adds back-flow: three loops that make the workspace orient itself, accumulate
knowledge, and stay honest with the code — without being told to.**

Each loop is a cheap deterministic **sensor** hook (notices a moment; never writes; never
blocks; fails silent) paired with an **actuator** skill (acts; proposes every
version-controlled edit before making it; sends a one-line receipt on write). **The trust
invariant is "propose, never silently auto-write."**

| Loop | Sensor | Actuator | What it gives you |
|---|---|---|---|
| **1. Onboarding** | `onboard.sh` (SessionStart) | `/orient` + `/install` | Point the crew at any folder — minutes later it understands the repo. Fresh / existing / multi-repo: one path to alive. |
| **2. Learning** | `suggest-memory.sh` (Stop) | `/remember` | A correction made once becomes a rule every future session reads. The lesson is never re-explained. |
| **3. Freshness** | `check-freshness.sh` (SessionStart) | `drift-audit` | Documentation never silently drifts from code. The sensor nudges; the actuator proposes patches. |

Plus the **cockpit**: `/status` — a single-screen read-only health view of all three loops,
every `⚠️` naming the one command that closes the gap.

The full rationale, options considered, and trade-offs are in
[docs/adr/0002-the-three-loops-auto-growing-workspace.md](docs/adr/0002-the-three-loops-auto-growing-workspace.md).

---

## Why this exists

The hard problems with coding agents at scale are not "can the model write code." They are:

1. **Context drift** — the agent loses the plot on a large codebase, or works off stale
   assumptions a vector index cannot keep fresh.
2. **Unverified output** — a summary of what an agent *intended* gets mistaken for proof of
   what it *did*.
3. **Cost** — burning the most expensive model on grunt work.
4. **Quality variance** — no consistent gate between "the agent finished" and "this is safe
   to merge."
5. **A workspace that forgets** — lessons die with the context window; every new session
   re-earns every insight.

This framework answers each one with a concrete mechanism:

| Problem | Mechanism |
|---|---|
| Context drift | The **context contract** — every repo carries `CLAUDE.md` (rules) + `CONTEXT.md` (orientation), updated in the same change as the code. Curated, version-controlled, always-fresh context — your "RAG" without a vector store. |
| Unverified output | The **quality pipeline** (critic → fixer → auditor) + independent verify + a **human merge gate**. A report is intent; the gate is evidence. |
| Cost | **Tiered model routing** — Haiku for mechanical work, Sonnet for slices, Opus only where being wrong is expensive. The single biggest cost lever, and it's free. |
| Quality variance | **Gate tiering** — match rigor to blast radius. High-risk work runs the full stack unchanged; proven low-risk work runs lean. Cut redundancy, never rigor. |
| A workspace that forgets | **The three loops** — back-flow that orients, learns, and stays fresh. A lesson persisted once is applied forever. |

---

## The team model

```
                         you (human)
                              │   final merge authority
                              ▼
                  main session = lead-agent
   ┌─────────┬─────────┬─────────┬──────────┬──────────┬─────────┬─────────┐
   ▼         ▼         ▼         ▼          ▼          ▼         ▼         ▼
 dev-lead design-lead devops-lead research-lead test-lead security-lead media-lead
   │         │         │         │          │          │         │
   ▼         ▼         ▼         ▼          ▼          ▼         ▼
        each lead delegates bounded work to junior-worker
        and runs the quality pipeline (critic → fixer → auditor)
```

- **`lead-agent`** is a **role the main session plays**, not a sub-agent to spawn. It
  decomposes requests, routes each piece to a domain lead, integrates results, and reports
  to you. (Spawning an orchestrator-as-sub-agent self-blocks in this runtime.)
- **Domain leads** (`dev-lead`, `design-lead`, `devops-lead`, `test-lead`, `security-lead`,
  `research-lead`, `media-lead`) are real spawnable sub-agents, each owning one slice
  end-to-end.
- **`architect`** handles cross-cutting design before code — produces a brief, never writes
  production code.
- **`junior-worker`** does one bounded, well-specified thing and reports to its lead. Never
  delegates further.
- **The quality pipeline** — `critic` finds issues, `fixer` resolves them on the branch,
  `auditor` gives the final independent verdict (APPROVED / CONDITIONAL / REJECTED).
- **You** hold the only merge authority on the main branch. This is the one
  human-judgment chokepoint and it never moves.

---

## The five capability layers (cheapest → most expensive)

The framework is not only agents. Five layers, one discipline: reach for the cheapest that
fits.

| Layer | What it is | When to reach for it | Cost |
|---|---|---|---|
| **command** | a prompt template (`.md`), `$ARGUMENTS` substituted — no agents, no logic | a cheap, repeatable single action (`/verify-service`, `/file-bug`, `/status`) | cheapest |
| **skill** | conditional knowledge + bundled resources, loaded on demand | a procedure with judgment (`/test-first`, `/troubleshoot`, `/install`, `/orient`, `/remember`) | cheap |
| **workflow** | a deterministic multi-agent JS script returning one structured result | **breadth** — the same operation across many repos (`cross-repo-migration`, `hygiene-fix-sweep`, `drift-audit`) | medium |
| **lead** | a spawnable domain agent owning a slice + its quality pipeline | **depth** — one slice, your judgment in the loop, turn-by-turn correction | higher |
| **orchestrator** | the main session acting as `lead-agent` | multi-discipline decomposition + routing across leads + integration | highest |

**The load-bearing distinction: workflow = breadth, lead = depth.** A workflow fans one
well-specified change across the entire repo universe deterministically. A lead takes one
slice through design → build → review with you correcting it turn by turn. Only the
orchestrator holds the `Workflow` tool.

---

## What is in this repo

```
.claude/
  agents/         15 agents — lead-agent (role, main session), 7 domain leads,
                  architect, junior-worker, critic/fixer/auditor, tester, pentester
  skills/         17 skills — orient, remember, install, create-workflow, interrogate-plan,
                  draft-prd, slice-issues, test-first, troubleshoot, context-handoff,
                  mockup, survey-code, deepen-architecture, sort-issues, stress-test,
                  terse-mode, author-skill
  commands/       5 commands — status (cockpit), verify-service, new-slice-branch,
                  file-bug, bump-pointer
  workflows/      5 workflows — build-status-audit, drift-audit, hygiene-fix-sweep,
                  cross-repo-migration, submodule-sync-sweep, slice-ship;
                  plus RESOLVER.md and repos.config.example.js
  hooks/          safety backstop — block-dangerous-git.sh, block-secrets-in-writes.sh,
                  secret-patterns.sh (sourced by both);
                  three-loop sensors — onboard.sh, check-freshness.sh, suggest-memory.sh;
                  naming guard — check-commit-msg.sh (git commit-msg hook, default OFF)
  memory/         MEMORY.md index — the session-loaded lesson store (seeded by /install)
  skills-config.example.json     shape of the per-project verify map + tracker config
  skills-config.schema.json      JSON Schema for validation
  settings.json                  sample hook wiring
packs/
  python-fastapi/ ACTIVE pack — 8 commands, 2 hooks, verify defaults (flake8+mypy+pytest)
  java/           spec-only stub
  node/           spec-only stub
  go/             spec-only stub
  PACK-SPEC.md    the authoring contract for new packs
docs/
  guide/          the complete technical guide (this release) — index, getting started,
                  core concepts, the three loops, working with the crew, full reference
  THE-METHOD.md   philosophy — the six habits + five-layer model + back-flow
  AGENT-WORKFLOW.md  binding workflow spec — branch model, PR flow, quality gates,
                     merge authority (every agent reads this per session)
  INSTALL.md      installation walkthrough — Detect → Scope → Wire, manual fallback
  WAVE-PLAN-TEMPLATE.md  how to plan a release as waves of parallel slices
  PR-TEMPLATE.md  PR format — scope, commits, quality pipeline result, CI gates
  adr/            architecture decision records
    0001-projects-self-configure-via-install-resolver-packs.md
    0002-the-three-loops-auto-growing-workspace.md
templates/
  CLAUDE.md.template   the per-repo rules file template
  CONTEXT.md.template  the per-repo orientation file template
  ADR.template.md      architecture decision record template
LICENSE
CONTEXT.md
```

> **How a project configures itself:** the framework ships zero project-specific facts. The
> repo universe, the verify commands, the active language pack, and the issue tracker all
> live in per-project config the consumer owns (`.claude/workflows/repos.config.js` +
> `.claude/skills-config.json` + activated `packs/`). Run `/install` to wire it. The
> reasoning is in [docs/adr/0001-projects-self-configure-via-install-resolver-packs.md](docs/adr/0001-projects-self-configure-via-install-resolver-packs.md).

---

## Quick start

### 1. Copy the framework in

```bash
cp -r /path/to/crew-for-claude/.claude  ./.claude
cp -r /path/to/crew-for-claude/packs    ./packs    # optional: stack packs
cp -r /path/to/crew-for-claude/docs     ./docs     # optional: workflow spec + ADRs
```

On Windows PowerShell, use `Copy-Item -Recurse` instead of `cp -r`.

### 2. Open Claude Code — the onboarding loop greets you

Open Claude Code in the repo root. The onboarding sensor (`onboard.sh`) fires immediately:
it detects what kind of folder you have and surfaces the right offer:

- **Empty / new project** → scaffold `CLAUDE.md` + `CONTEXT.md`, then `/install`
- **Existing project** → `/orient` generates a real `CONTEXT.md` from your code, then `/install`
- **Multi-repo workspace** → `/install --dry-run` resolves the universe, then `/orient` per repo

You do not need to script anything — confirm the offer and the crew does the work.

### 3. Run `/orient` on an existing repo

```
/orient
```

Point the crew at a repo it has never seen. Minutes later it understands it: a real
`CONTEXT.md` with the data model, public surface, module map, and domain glossary — generated
from the actual code. Draft is shown before anything is written.

### 4. Run `/install` to wire the machinery

```
/install --dry-run        # show the plan, write nothing
/install                  # apply the plan
```

`/install` runs **Detect → Scope → Wire**: classifies the stack(s) and shape, resolves the
repo universe, generates `repos.config.js` and `skills-config.json`, activates the matching
language pack, seeds `.claude/memory/MEMORY.md`, and wires all six hooks including the
three-loop sensors — idempotently, never clobbering files you wrote.

### 5. Check the cockpit: `/status`

```
/status
```

One-screen health view: install state, orientation, memories captured, doc freshness, safety
hooks, open work. Every `⚠️` line names the one command that closes the gap.

### 6. Fill in `CLAUDE.md` and `CONTEXT.md`

The context contract is the highest-leverage thing you do after install. The templates guide
you through the questions each file answers. Commit them alongside the code; treat them as
load-bearing.

### 7. Start the lead-agent

Describe a concrete goal. The main session acts as `lead-agent`, decomposes it, dispatches
leads, and fans breadth out via workflows. For larger releases, plan waves with
[docs/WAVE-PLAN-TEMPLATE.md](docs/WAVE-PLAN-TEMPLATE.md) before dispatching.

---

## Documentation

| Document | What it covers |
|---|---|
| **[docs/guide/README.md](docs/guide/README.md)** | Documentation index — start here |
| [docs/guide/getting-started.md](docs/guide/getting-started.md) | Install → onboarding loop → `/orient` → `/status` → first slice |
| [docs/guide/core-concepts.md](docs/guide/core-concepts.md) | Team model, context contract, tiered routing, quality pipeline, 5 capability layers |
| [docs/guide/three-loops.md](docs/guide/three-loops.md) | The three loops in depth — sensor/actuator pattern, each loop, the cockpit, the trust invariant |
| [docs/guide/working-with-the-crew.md](docs/guide/working-with-the-crew.md) | Daily workflows: slices, breadth, gate tiers, bugs, context handoff |
| [docs/guide/reference.md](docs/guide/reference.md) | Full inventory — every agent, skill, command, workflow, hook, pack (tables, one line each) |
| [docs/THE-METHOD.md](docs/THE-METHOD.md) | Philosophy — the six habits + back-flow + five-layer capability model |
| [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md) | Binding workflow spec — every agent reads this per session |
| [docs/INSTALL.md](docs/INSTALL.md) | Detailed installation walkthrough + manual fallback |
| [docs/adr/0001](docs/adr/0001-projects-self-configure-via-install-resolver-packs.md) | ADR: why the framework hardcodes nothing project-specific |
| [docs/adr/0002](docs/adr/0002-the-three-loops-auto-growing-workspace.md) | ADR: the three loops — full rationale, options considered, trade-offs |

---

## The six working habits

These bind every session. The full version is in [docs/THE-METHOD.md](docs/THE-METHOD.md).

1. **Front-load decisions** — they are the expensive part. Surface ambiguity before writing
   code. Ten minutes of decisions saves hours of wrong-direction build.
2. **Route work to the cheapest capable model** — the single biggest cost lever, and it is
   free. Haiku for mechanical, Sonnet for slices, Opus only where being wrong hurts.
3. **Parallelize independent work, serialize dependent work — but verify is non-negotiable.**
   Unverified parallelism is where time actually leaks.
4. **Trust but verify** — a summary is intent, not evidence. Check the diff, run the test,
   look at the real output before marking work done.
5. **Cost and context hygiene** — one clear ask per turn; paste the error + file:line; say
   when to stop; `/clear` between unrelated tasks.
6. **Protect the spec** — the domain *why* is the one input no agent can supply. Keep it
   flowing; it is the ceiling on quality.

---

## License

MIT License. See [LICENSE](LICENSE).

Copyright (c) 2026 Crew for Claude contributors.

The framework is yours to adapt — the agents, skills, and docs are starting points. The
mechanisms (context contract, tiered routing, the review pipeline, the human merge gate,
the three loops) are the part worth keeping.
