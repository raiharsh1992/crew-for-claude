# ADR-0002: The three loops — an auto-learning, auto-growing workspace

**Status:** Accepted — all three loops + the cockpit built
**Date:** 2026-06-04
**Deciders:** framework maintainers

---

## Context

The kit's mechanisms (context contract, tiered routing, quality pipeline, human merge
gate) are all **forward flow**: a human invokes a skill, agents produce code, the human
merges. Every mechanism is *pull* — nothing happens unless someone runs it.

The product goal is different: **from the moment Claude Code opens in a folder — fresh,
existing, or multi-repo-pulled — the workspace should orient itself, get smarter with use,
and stay honest with the code, without being told to.** That requires **back-flow**: the
session must feed what it learned back into the kit so the next session is better. The kit
had no back-flow at all. A correction died with the context window; a fresh agent
re-earned every lesson; docs drifted silently until someone ran an audit.

The forces:
- **Magic vs. trust.** Silent edits to version-controlled files (`CLAUDE.md`, ADRs) feel
  like magic right up until one is wrong and the user didn't see it coming. Trust, once
  lost, kills adoption.
- **Precision vs. nag.** A system that suggests "remember this?" on every turn trains the
  user to ignore it. A sensor must fire rarely and be right when it does.
- **Three entry shapes, one experience.** Fresh folder, existing project, and
  multi-repo-pulled workspace must all reach "alive and learning" — the kit can't assume
  which one it's in.

---

## Decision

**We model the auto-growing experience as three explicit loops, each a back-flow the kit
previously lacked. Every loop that writes a version-controlled file PROPOSES the edit and
writes only on confirmation — propose, never silently auto-write. Low-stakes agent memory
may be written directly, but always announced (never silent).**

| Loop | Job | Sensor (notices) | Actuator (writes) | State |
|---|---|---|---|---|
| **1. Onboarding** | install → *alive* in minutes, for any folder shape | `onboard.sh` (SessionStart) | `/orient` (CONTEXT.md generator) + `/install` | ✅ built |
| **2. Learning** | a lesson learned once is never re-learned | `suggest-memory.sh` (Stop hook) | `/remember` skill | ✅ built |
| **3. Freshness** | docs never silently drift from code | `check-freshness.sh` (SessionStart) | `drift-audit` → proposed CONTEXT.md patches | ✅ built |
| **+ Cockpit** | one-screen read-only view of all three loops | — (on-demand) | `/status` command | ✅ built |

The **sensor/actuator split is the core pattern**: a cheap deterministic hook *notices* the
moment (no model cost, fires regardless of which model ran), and a skill the user can see
and approve *acts*. The hook never writes; the skill never fires unprompted on tracked
files. This keeps the human merge gate philosophy intact even as the kit learns.

---

## Options considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Three loops, sensor/actuator split, propose-never-auto-write** | Trust preserved; cheap deterministic capture; works across folder shapes | More moving parts than a single "memory file" | ✅ chosen |
| Let the agent decide what to remember (no hook) | Zero new infra | The mid-task agent is the worst narrator of "this is durable"; lessons die with context | rejected — capture is unreliable exactly when it matters |
| Auto-write everything, review via `git diff` | Maximum "magic" feel | Surprise edits to tracked files erode trust; one bad write loses the user | rejected — violates the merge-gate principle |
| Lean on Claude Code's built-in memory only | No kit code | Not routed (rule vs. decision vs. preference all land in one undifferentiated place); no drift/onboarding loops | rejected — undifferentiated memory pollutes the rulebook |

---

## Loop 2 — Learning (built)

The reference implementation of the pattern, shipped in this change:

- **Sensor:** [`.claude/hooks/suggest-memory.sh`](../../.claude/hooks/suggest-memory.sh) —
  a `Stop` hook. Reads the last user message from the transcript, matches a
  precision-tuned set of "durable lesson" phrases (`from now on`, `we decided`,
  `always/never`, `i prefer`, …), and emits a one-line nudge. Never blocks (no `exit 2`),
  fails silent on any parse error (a missed nudge is fine; a spurious one is not), and
  guards against recursion via `stop_hook_active`.
- **Actuator:** [`/remember`](../../.claude/skills/remember/SKILL.md) — classifies the fact
  (rule → `CLAUDE.md`, orientation → `CONTEXT.md`, decision → ADR, preference →
  `.claude/memory/`), drafts the exact text, shows it, writes on confirm, and prints a
  one-line receipt.
- **Store:** `.claude/memory/` with `MEMORY.md` as the session-loaded index. Team memories
  are committed; `*.local.md` personal ones are gitignored.

---

## Loop 1 — Onboarding (built)

**Goal:** the *wow* moment. Three folder shapes, one path to "alive":

1. **Fresh empty folder / new project** → the sensor offers to scaffold: describe the goal,
   the crew lays down `CLAUDE.md` + `CONTEXT.md` from templates and runs `/install`.
2. **Existing project** → *instant orientation*: `/orient` reads the repo and generates a
   real `CONTEXT.md` (glossary, module map, "read this first"), then offers `/install`.
3. **Multi-repo pulled into one workspace** → `/install --dry-run` resolves the repo
   universe; `/orient` generates per-repo `CONTEXT.md`.

**Sensor:** [`onboard.sh`](../../.claude/hooks/onboard.sh) (SessionStart) — detects
first-run (no `.claude/skills-config.json`) and the folder shape (empty / single / multi-repo
/ superproject) with pure-bash filesystem checks, then surfaces the one right offer. Goes
silent once installed AND `CONTEXT.md` is authored. **Actuator:**
[`/orient`](../../.claude/skills/orient/SKILL.md) (the CONTEXT.md generator, `survey-code`-backed)
+ `/install`. Propose-never-auto-write holds: the generated `CONTEXT.md` is shown before it's
written, and an authored one is never clobbered.

> **Constraint honored:** `/install` v1 is configure-in-place only (clone / new-workspace are
> documented fast-follows). The onboarding sensor therefore offers scaffolding and
> orientation for what's *on disk* — it does not improvise a clone flow.

---

## Loop 3 — Freshness (built)

**Goal:** the docs never lie. `drift-audit` already detects doc-vs-code drift but was
*pull* — nobody ran it.

**Sensor:** [`check-freshness.sh`](../../.claude/hooks/check-freshness.sh) (SessionStart) —
the cheap tripwire: count code-bearing commits since `CONTEXT.md`'s last commit that did NOT
also touch it (commits that updated the doc in the same change kept the contract and don't
count). Over `STALE_THRESHOLD` (default 15) → nudge. It's a heuristic by commit count, so it
only ever *suggests* the real audit — it never claims drift as fact. Stays silent on
un-installed / un-oriented repos (that's Loop 1's turf). **Actuator:** `drift-audit` →
proposed `CONTEXT.md` patches the user approves. Same propose-never-auto-write rule.

---

## Consequences

**Positive:**
- The kit now has back-flow. A correction becomes a durable rule for the cost of one
  `/remember`; the next session inherits it for free.
- The sensor/actuator split generalizes — Loops 1 and 3 reuse the exact pattern (a cheap
  `SessionStart` sensor + an existing actuator skill), so they're now small slices, not
  research.
- Trust is structural: nothing version-controlled is written without the user seeing it.

**Negative / accepted trade-offs:**
- The Stop hook adds a transcript read per turn, and the two SessionStart hooks add cheap
  filesystem/git checks per session start. All fail silent, none call a model — but the cost
  is non-zero.
- Precision-tuned patterns will miss some learnable moments (low recall by design). The
  manual `/remember` covers the gap; we'd rather miss than nag.
- The freshness signal is a commit-count heuristic, not a real surface diff — it can nudge
  when nothing user-facing changed, or stay quiet when one commit changed a lot. It's a
  tripwire for the real audit, deliberately not the audit itself.

**Follow-ups:**
- Wire `/install` to seed `.claude/memory/MEMORY.md` + the gitignore stance and to add the
  three sensor hooks to `settings.json` on install, so the loops have a home from session one
  in every consumer (today they're wired in this kit's own `settings.json`; the installer
  should reproduce that wiring in a target repo).
- Upgrade the freshness sensor from a commit-count heuristic toward a cheap real-surface
  check (e.g. diff the endpoint/table names in `CONTEXT.md` against a grep of the code) if
  the heuristic proves too noisy or too quiet in practice.
- `/status` cockpit — ✅ built (the health-dashboard wow-moment).
