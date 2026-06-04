# The Method

The philosophy behind `crew-for-claude`. The mechanics are in
[AGENT-WORKFLOW.md](AGENT-WORKFLOW.md); this document is the *why*.

The goal is simple to state and hard to do: **ship production-grade code at high
velocity without the quality coming from your constant vigilance.** The system enforces
quality so you don't have to babysit it. These six habits are how that happens.

---

## 1. Front-load decisions — they're the expensive part

The costliest waste in agent work isn't tokens, it's **rework from under-specified
intent.** A wrong guess on scope is paid three times: the work, the review, the redo.

So surface ambiguity *before* writing code, not after. If a request has a branch that
would change the design, ask 1–3 sharp questions first (or run `/interrogate-plan` to do
it properly). Ten minutes of decisions saves hours of wrong-direction build.

Capture the decisions that get made — in a `PLATFORM-DECISIONS` doc, in ADRs, in
`CONTEXT.md`. Locked decisions exist so you read them, extend them, and don't
re-litigate them next session.

---

## 2. Route work to the cheapest capable model/agent

This is the biggest cost lever and it's free. Don't do grunt work on the most expensive
model in your main session. Match the task to the tier:

| Task | Use | Why |
|---|---|---|
| Mechanical edits, find/replace, file moves, a known command, one bounded file | `junior-worker` (Haiku) | No judgment needed; cheapest |
| A whole slice, feature, endpoint, schema — clear scope, one discipline | the relevant **lead** (Sonnet) | Owns the slice + quality pipeline |
| Architecture, cross-module decisions, ADR-worthy calls | `architect` (Opus) | Being wrong here is expensive |
| Final verdict on a slice | `auditor` (Opus, spawned by the lead) | High blast radius |
| Multi-discipline orchestration / routing | **main session** as `lead-agent` (Opus) | High blast radius |

The agent tiers already encode this (Haiku → Sonnet → Opus). Trust them. Reach for the
top tier only where being wrong actually hurts. A review gate fires *identically*
regardless of which model produced the work — so don't pay top-tier prices for
mid-tier work.

---

## 3. Parallelize independent work; serialize dependent work — but verify is non-negotiable

Independent slices (backend + frontend, or two unrelated features) run concurrently
under the `lead-agent`. **Parallel is fast only if the verification gate is real.**

The known failure mode is *unverified parallelism* — leads faking a smoke-test,
self-blocked agents, ten wasted CI rounds on one slice. Never skip the independent
verify to go faster; that's exactly where time leaks. Run your verify step *in parallel
with* the critic/auditor pass (they're independent), and don't execute the same lint/test
suite three times — pre-commit + one pre-PR verify + CI is the chain, and CI is
authoritative.

### Gate tiering — cut redundancy, never rigor

Uniform gates make everything feel slow. The fix is **tiering by blast radius, not
lowering the bar.** High-risk slices (auth, data isolation, audit, money, migrations,
cross-service contracts, anything a critic would auto-fail) run the **FULL**
critic → fixer → auditor stack unchanged. Provably low-risk slices (docs, styling on
existing patterns, read-only endpoints, behavior-identical refactors) run **LEAN** =
auditor-only (which still does a full independent top-down review). CI, the external
reviewer, verify, and human-merge are **identical in both tiers** — nothing that protects
correctness is skipped. Default is FULL; any doubt = FULL; a LEAN slice that surfaces a
real finding is reclassified FULL.

---

## 4. Trust but verify — a summary is intent, not evidence

An agent's report says what it *intended* to do, not always what it *did*. Before
marking work done: check the actual diff, run the actual test, look at the real output.

"Are the changes actually there, or did the agent just say so?" is the cheapest
insurance in the whole system. It applies to you reviewing the agents AND to leads
reviewing their sub-agents. The auditor exists precisely because self-assessment is not
evidence.

---

## 5. Cost & context hygiene

- **One clear ask per turn** beats a vague multi-part one — less hedging across
  interpretations.
- **Paste the error + file:line** — don't make an agent rediscover "it's broken" with
  five tool calls.
- **Say when to stop.** The default is thorough. If "good enough, ship it" is what you
  want, say so and the polishing stops.
- **`/clear` between unrelated tasks.** Long sessions get expensive and drift; the
  memory system carries forward what matters.
- **No scratch in git.** Throwaway verification output, temp dirs, run dumps — never
  committed. Stage files by explicit name, never `git add -A` in a tree that might
  contain scratch.

---

## 6. Protect the spec — the part no agent can judge

"The best version of this product" is won or lost on the things agents *can't* see: the
real workflows, what the user needs under pressure, the domain constraints, the right
tone for each surface. An agent can build to a spec flawlessly and still build the wrong
thing.

The domain *why* — fed in by the people who hold it — is the ceiling on quality. Keep it
flowing. It's the one input that can't be delegated.

---

## The five capability layers — reach for the cheapest that fits

Tiered model routing (habit #2) has a twin: **tiered *tooling*.** The crew exposes five
layers, and the discipline is the same — use the cheapest one that actually does the job,
escalate only when the work demands it.

| Layer | What it is | Reach for it when | Relative cost |
|---|---|---|---|
| **command** | a prompt template (`.md`, `$ARGUMENTS` substituted) — no agents, no logic | a cheap, repeatable, single action you do often (`/verify-service`, `/file-bug`, `/new-slice-branch`) | cheapest |
| **skill** | conditional knowledge + bundled resources, loaded on demand | a procedure that needs judgment but not a whole agent (`/test-first`, `/troubleshoot`, `/install`) | cheap |
| **workflow** | a deterministic multi-agent JS script (`parallel`/`pipeline`/loops) returning one structured result | **breadth** — the *same* well-specified operation across many repos (`cross-repo-migration`, `hygiene-fix-sweep`, `drift-audit`) | medium |
| **lead** | a spawnable domain agent owning a slice + its quality pipeline | **depth** — one slice, your taste, human-in-the-loop correction | higher |
| **orchestrator** | the main session acting as `lead-agent` | multi-discipline decomposition, routing across leads, integration | highest |

**The load-bearing distinction is workflow vs. lead: breadth vs. depth.**

- A **workflow** fans one change across the whole repo universe deterministically. It does
  not improvise — it does the *same* thing to every repo and returns a structured result.
  Use it for "bump this shared dep everywhere," "roll this CI gate to every service,"
  "audit every repo for doc-vs-code drift." Its doers default to **DRY-RUN** (real work in
  isolated worktrees, real verify, but STOP before pushing) so breadth never auto-merges.
- A **lead** takes one slice through design → build → review with you correcting it turn by
  turn. Use it when the work needs judgment, taste, or a conversation — exactly what a
  deterministic script can't supply.
- A **command** is for the cheap action you repeat constantly; promote a repeated
  hand-typed sequence into one. A repeated *multi-repo* chore, by contrast, wants a
  **workflow** — author it with `/create-workflow`.

Only the orchestrator holds the `Workflow` tool. Leads work in depth and **report
breadth-needs up** — they don't fan work out themselves. This keeps the human merge gate
(and the single coordination point) intact even when work goes wide.

---

## The context contract — why drift doesn't happen

This is the mechanism that makes everything above sustainable on a large codebase, so it
gets its own section.

**Every repo carries two context files, kept current in the same change as the code they
describe:**

| File | Role | Audience |
|---|---|---|
| `CLAUDE.md` | The **rules** — house style, constraints, prohibited patterns, the one-line links to deeper docs. | Anyone about to *write* code here. |
| `CONTEXT.md` | The **orientation** — what this repo owns, its data model, its contracts, the one file to read first. | Anyone about to *navigate* this repo. |

**Freshness is mandatory.** A change that alters a module's contracts, endpoints, or data
shape updates that repo's `CONTEXT.md` in the same change. Stale orientation is a
review-blocker, the same weight as a missing test.

This is your "RAG": curated, version-controlled, always-fresh context — **not** a vector
store that silently goes stale. It is the thing that lets a fresh session (a new agent, a
new day) orient in minutes instead of re-deriving the project from scratch. It is the
single highest-leverage artifact in the whole kit.

The reading order for any session picking up work: root `CLAUDE.md` → root `CONTEXT.md`
(glossary) → the module's `CONTEXT.md` → the module's `CLAUDE.md` → design docs → the
code.

---

## Back-flow — the framework that compounds

The six habits and the five capability layers are all **forward flow**: a human invokes a
skill, agents produce output, the human merges. Everything is pull. Nothing happens unless
someone runs it.

That works well for deliberate work. It breaks down for the ambient maintenance tasks:
orienting a fresh repo, capturing a lesson before it dies with the context window, keeping
documentation honest as code evolves. These need **back-flow** — the session feeding what it
learned back into the kit so the next session starts better.

The framework adds back-flow through **three loops**. Each loop is a cheap deterministic
**sensor** hook (notices the moment, never writes, never blocks, fails silent) paired with an
**actuator** skill (acts, proposes every version-controlled edit before making it, sends a
receipt). The **trust invariant** is "propose, never silently auto-write": a fact going into
a tracked file changes how every future agent behaves — that edit belongs in front of a human.

| Loop | What it closes | Sensor | Actuator |
|---|---|---|---|
| **1. Onboarding** | A fresh/un-installed repo is opaque until someone manually runs `/orient` | `onboard.sh` (SessionStart) | `/orient` + `/install` |
| **2. Learning** | A correction dies with the context window; every new session re-earns it | `suggest-memory.sh` (Stop) | `/remember` |
| **3. Freshness** | `CONTEXT.md` drifts silently as code evolves | `check-freshness.sh` (SessionStart) | `drift-audit` |

**The payoff compounds with use.** Each lesson persisted is a mistake never repeated and
context never re-paid for. Each fresh `CONTEXT.md` means every future session starts from
a real map of the code. Each freshness nudge caught early is hours of re-derivation avoided.

The full design, options considered, and trade-offs are in
[adr/0002-the-three-loops-auto-growing-workspace.md](adr/0002-the-three-loops-auto-growing-workspace.md).

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
