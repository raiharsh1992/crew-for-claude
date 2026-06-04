# Crew for Claude — Documentation

This guide is the complete technical reference for **Crew for Claude**: a portable
operating-model framework for running Claude Code as a small software organisation. It covers
how to install the framework, what every piece does, and how to work with it day to day.

**Start here if you are new.** If you already have the crew running, jump straight to the
[Reference](./reference.md) for the full inventory, or to
[Working with the Crew](./working-with-the-crew.md) for daily patterns.

---

## Pages in this guide

| Page | What it covers |
|---|---|
| [Getting Started](./getting-started.md) | Copy-in, `/install`, the onboarding loop, first slice |
| [Core Concepts](./core-concepts.md) | Team model, context contract, tiered routing, quality pipeline, 5 capability layers |
| [The Three Loops](./three-loops.md) | The marquee feature: onboarding, learning, freshness — sensor/actuator pattern, the cockpit |
| [Working with the Crew](./working-with-the-crew.md) | Daily workflows: building a slice, running breadth, gate tiers, bugs, context handoff |
| [Reference](./reference.md) | Full inventory — every agent, skill, command, workflow, hook, and pack |

---

## Deeper docs (normative)

These documents are the authoritative specification; the guide links into them rather than
duplicating them:

| Document | What it is |
|---|---|
| [docs/THE-METHOD.md](../THE-METHOD.md) | Philosophy — the six habits + the 5-layer capability model + back-flow |
| [docs/AGENT-WORKFLOW.md](../AGENT-WORKFLOW.md) | Binding workflow spec — branch model, PR flow, quality gates, merge authority |
| [docs/INSTALL.md](../INSTALL.md) | Installation walkthrough — Detect → Scope → Wire, manual fallback, hook wiring |
| [docs/adr/0001-projects-self-configure-via-install-resolver-packs.md](../adr/0001-projects-self-configure-via-install-resolver-packs.md) | ADR: why the framework hardcodes nothing project-specific |
| [docs/adr/0002-the-three-loops-auto-growing-workspace.md](../adr/0002-the-three-loops-auto-growing-workspace.md) | ADR: the three-loops design — the full rationale, options considered, trade-offs |

---

## The through-line

The framework solves four hard problems with concrete mechanisms:

| Problem | Mechanism |
|---|---|
| Context drift on a large codebase | The **context contract** — `CLAUDE.md` (rules) + `CONTEXT.md` (orientation), updated in the same change as the code |
| Unverified agent output | The **quality pipeline** (critic → fixer → auditor) + independent verify + **human merge gate** |
| Token cost | **Tiered model routing** — Haiku for mechanical work, Sonnet for slices, Opus for high-blast-radius decisions |
| A workspace that never learns | **The three loops** — back-flow sensors and actuators that orient, learn, and stay fresh without silent writes |

The three loops are what is new in this release. Everything else was already in place; the
loops are what adds back-flow — the workspace now gets better the longer you use it.

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
