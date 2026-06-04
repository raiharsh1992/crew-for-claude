# Core Concepts

This page explains the five concepts that everything else in the framework builds on. Read
[docs/THE-METHOD.md](../THE-METHOD.md) for the full philosophy behind each one.

---

## 1. The team model

The crew is a fixed hierarchy of agents. The hierarchy is what prevents parallel agents from
colliding, keeps cost controlled, and keeps the human merge gate intact.

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

**Key rules:**

- **`lead-agent` is a role, not a spawnable agent.** The main session (the Claude Code
  session you talk to) plays this role. Spawning a sub-agent-as-orchestrator self-blocks in
  this runtime — the main session *is* the orchestrator.
- **Domain leads** (`dev-lead`, `design-lead`, `devops-lead`, `test-lead`, `security-lead`,
  `research-lead`, `media-lead`) are real spawnable sub-agents. Each owns one slice
  end-to-end.
- **`architect`** is spawned for cross-cutting design *before* code, when a decision touches
  more than one module. Produces a brief; does not write code.
- **`junior-worker`** does one bounded, well-specified task (one file, one endpoint, one
  schema) under a lead. Never delegates further.
- **The quality pipeline** — `critic` finds issues, `fixer` resolves them on the branch,
  `auditor` gives the final independent verdict. `test-lead` and `security-lead` have no
  fixer: their findings route back up, not sideways.
- **You** hold the only merge authority on the main branch. This is the single
  human-judgment chokepoint and it never moves.

The full spec is in [docs/AGENT-WORKFLOW.md](../AGENT-WORKFLOW.md).

---

## 2. The context contract

**Every repo carries two context files, kept current in the same change as the code:**

| File | Role | Who reads it |
|---|---|---|
| `CLAUDE.md` | The **rules** — house style, constraints, prohibited patterns, links to deeper docs | Anyone about to *write* code here |
| `CONTEXT.md` | The **orientation** — what this repo owns, its data model, its contracts, its domain glossary | Anyone about to *navigate* this repo |

**Why this matters:** a fresh agent (or a new team member, or a new session) can orient in
minutes instead of re-deriving the project from scratch. This is your "RAG" — curated,
version-controlled, always-fresh context — not a vector store that silently goes stale.

**The freshness rule is the whole point:** any change that alters a module's contracts,
endpoints, or data shape updates `CONTEXT.md` in the same change. Stale orientation is a
review-blocker — the `critic` and `auditor` treat it with the same weight as a missing test.

**Reading order for any session picking up work:**
root `CLAUDE.md` → root `CONTEXT.md` → the module's `CONTEXT.md` → the module's `CLAUDE.md`
→ design docs → the code.

The `/orient` skill generates a real `CONTEXT.md` from actual code (see
[Getting Started](./getting-started.md)), and the Loop 3 freshness sensor nudges when it
drifts. The full philosophy is in [docs/THE-METHOD.md](../THE-METHOD.md) → "The context
contract".

---

## 3. Tiered model routing

Routing work to the cheapest capable model/agent is the single biggest cost lever in the
framework, and it's free. The agent tiers encode this directly:

| Work | Agent | Model | Why |
|---|---|---|---|
| Mechanical: find/replace, file move, one bounded file, a known command | `junior-worker` | Haiku | No judgment needed; cheapest |
| A whole slice, feature, endpoint, schema — clear scope, one discipline | the domain **lead** | Sonnet | Owns the slice + runs the quality pipeline |
| Cross-module, shared-package, load-bearing, or ADR-worthy decision | `architect` first | Opus | Being wrong here is expensive |
| Final verdict on a slice | `auditor` | Opus | High blast radius; independent verdict |
| Security review (authorized work only) | `security-lead` | Opus | Security findings are high blast radius |
| Multi-discipline orchestration, routing across leads | main session as `lead-agent` | Opus | The coordination point |

A quality gate fires *identically* regardless of which model produced the work — so there
is no quality trade-off in routing cheap work cheaply. The cost saving is real; the quality
risk is not.

---

## 4. The quality pipeline and the human merge gate

Every slice goes through a quality pipeline before the human reviews it:

```
feature branch work
        │
    ┌───▼───┐  FULL tier only
    │ critic │  reviews the diff for completeness, correctness, rule compliance
    └───┬───┘
        │
    ┌───▼───┐  FULL tier only (if critic found issues)
    │ fixer  │  resolves critic findings on the feature branch
    └───┬───┘
        │
    ┌───▼────┐  BOTH tiers
    │ auditor │  independent top-down review: APPROVED / CONDITIONAL / REJECTED
    └───┬────┘
        │
    PR to main branch
        │
  human reviews and merges  ← the gate that never moves
```

**Gate tiering — match rigor to blast radius:**

- **FULL tier** (all gates): any slice touching auth, data isolation, audit, money,
  migrations, cross-service contracts, sensitive user data, or anything the critic would
  auto-fail. Default when in doubt.
- **LEAN tier** (auditor only): proven low-risk slices — docs/comments/copy, UI styling on
  existing patterns, read-only endpoints with no new access logic, behavior-identical
  refactors fully covered by existing tests. The critic/fixer pre-pass is skipped; the
  auditor still does a full independent review.
- **No tier removes CI, external review, the verify step, or the human merge gate.** What
  changes between tiers is only the critic → fixer pre-pass.
- A LEAN slice whose auditor finds anything beyond trivial polish is reclassified FULL.
- **If the auditor REJECTS: the lead does not merge.** The slice goes back to the
  `lead-agent` / user with the rejection report.

**The human merge gate:**
No agent has merge authority on the main branch. The user reviews the PR, CI checks, the
auditor verdict, and any external review — then merges. This is the one human-judgment
chokepoint, and it never moves.

The full gate spec is in [docs/AGENT-WORKFLOW.md](../AGENT-WORKFLOW.md) → "Quality gates"
and "Gate tiering".

---

## 5. The five capability layers

The framework exposes five layers, ordered from cheapest to most expensive. The discipline
is: reach for the cheapest layer that actually does the job.

| Layer | What it is | Reach for it when | Cost |
|---|---|---|---|
| **command** | a prompt template (`.md`), `$ARGUMENTS` substituted — no agents, no logic | a cheap, repeatable, single action you do often (`/verify-service`, `/file-bug`, `/new-slice-branch`) | cheapest |
| **skill** | conditional knowledge + bundled resources, loaded on demand | a procedure that needs judgment but not a whole agent (`/test-first`, `/troubleshoot`, `/install`, `/orient`, `/remember`) | cheap |
| **workflow** | a deterministic multi-agent JS script (`parallel`/`pipeline`/loops) returning one structured result | **breadth** — the same well-specified operation across many repos (`cross-repo-migration`, `hygiene-fix-sweep`, `drift-audit`) | medium |
| **lead** | a spawnable domain agent owning a slice + its quality pipeline | **depth** — one slice, your judgment in the loop, turn-by-turn correction | higher |
| **orchestrator** | the main session acting as `lead-agent` | multi-discipline decomposition, routing across leads, integration | highest |

**The load-bearing distinction is workflow vs. lead: breadth vs. depth.**

- A **workflow** fans one change across the whole repo universe deterministically. It does
  not improvise — it does the *same* thing to every repo and returns a structured result. Its
  doers default to DRY-RUN: real work in isolated worktrees, real verify, but stop before
  pushing. Only the orchestrator holds the `Workflow` tool.
- A **lead** takes one slice through design → build → review with you correcting it turn by
  turn. Use it when the work needs judgment, taste, or a conversation.
- A **command** is for the cheap action you repeat constantly. A repeated *multi-repo* chore
  wants a **workflow** instead — author it with `/create-workflow`.

Leads that discover a breadth need **report it up** to the orchestrator; they do not fan
work out themselves. This keeps the human merge gate intact even when work goes wide.

The full five-layer model is in [docs/THE-METHOD.md](../THE-METHOD.md) → "The five
capability layers".

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
