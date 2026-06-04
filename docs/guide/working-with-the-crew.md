# Working with the Crew

This page covers daily patterns: building a single slice with a domain lead, running breadth
with a workflow, choosing the right gate tier, filing bugs, and handing off long tasks. The
binding spec for all of this is [docs/AGENT-WORKFLOW.md](../AGENT-WORKFLOW.md).

---

## Building a slice (depth with a lead)

A slice is one domain lead's end-to-end unit of work: one feature branch → one PR → one
merge. This is the most common interaction pattern.

### 1. Front-load the decision

Before dispatching a lead, clarify scope. The costliest waste in agent work is rework from
under-specified intent. If the request has a branch that would change the design, surface
it first:

- For a vague or large request: run `/interrogate-plan` — it surfaces ambiguity against
  `CONTEXT.md` and ADRs, updates them inline, and produces a locked decision record.
- For something with a clear shape but uncertain details: ask 1–3 sharp questions before
  dispatching.

Ten minutes of decisions saves hours of wrong-direction build.

### 2. Open the feature branch

The lead (or the `lead-agent` on its behalf) runs `/new-slice-branch <slice-name>`, which:
- Fetches origin, checks out main, pulls `--ff-only`, creates `feat/<slice-name>`.
- Scaffolds a DESIGN doc stub.
- Reminds the lead of the gate tier to declare.

### 3. Let the lead work

The lead decides solo vs. delegate for each commit group:
- **Solo** — cross-file coordination, state design, security-sensitive code, architectural
  judgment. The lead writes it directly.
- **Delegate** — a bounded, single-file, well-specified task with no architectural judgment.
  The lead spawns a `junior-worker` on a sub-branch (`feat/<slice>/<sub-task>`), reviews the
  junior's PR to the feature branch, then merges.

### 4. The quality pipeline

After all work on the feature branch is done, the lead classifies the gate tier and runs the
pipeline. See [Core Concepts](./core-concepts.md) → "The quality pipeline and the human merge
gate" for the full gate-tiering rules.

**FULL tier** (any doubt → FULL):
1. `critic` — reviews the full diff; produces a structured issue list.
2. `fixer` — resolves critic findings on the feature branch.
3. `auditor` — independent top-down verdict: APPROVED / CONDITIONAL / REJECTED.

**LEAN tier** (proven low-risk only):
1. `auditor` — full independent review (critic/fixer pre-pass skipped).

Run `/verify-service <repo>` in parallel with the critic/auditor pass — they are independent.

### 5. Open the PR

When the auditor approves, the lead pushes and opens a PR using the template in
[docs/PR-TEMPLATE.md](../PR-TEMPLATE.md). The PR captures scope, commits, quality pipeline
result, CI gates, external review status, cross-module impact, and deferred follow-ups.

### 6. You merge

When the auditor is APPROVED (or CONDITIONAL with documented conditions), external review is
resolved-with-proof (if gated), and all CI is green, the lead pings you with the PR URL and
a one-paragraph summary. You review and merge. **No agent has merge authority on the main
branch.**

---

## Running breadth with a workflow

A **workflow** fans one well-specified operation across the whole repo universe
deterministically. Use it instead of a lead when the work is "do one thing across all
repos":

- Bump a shared dependency everywhere → `cross-repo-migration`
- Roll a CI gate to every service → `hygiene-fix-sweep`
- Detect doc-vs-code drift across all repos → `drift-audit`
- Sync stale submodule pointers after a merge wave → `submodule-sync-sweep`
- Ship one slice through the full pipeline → `slice-ship`
- Check build status across all repos → `build-status-audit`

Only the orchestrator (main session as `lead-agent`) holds the `Workflow` tool. Leads that
discover a breadth need report it up — they do not fan work out themselves.

### Running a workflow

Ask the main session in plain language:

```
"Run the hygiene-fix-sweep to add the mypy blocking gate to every service."
"Use cross-repo-migration to bump the shared core library to 0.2.0."
"Run drift-audit across all repos."
```

The main session invokes `Workflow({ name: "<name>", args: {…} })`. All doer workflows
**default to DRY-RUN**: real work in isolated git worktrees, real verify, but stop before
pushing or opening PRs. Review the dry-run report, then arm it:

```
Workflow({ name: "hygiene-fix-sweep", args: { dryRun: false } })
```

The doers open PRs; you still merge — the human gate is identical to the interactive flow.

### Authoring a new workflow

Use `/create-workflow`. It encodes the resolver model (no inlined repo lists), the verify-map
idiom (no hardcoded toolchains), the DRY-RUN default, and the three workflow shapes
(fan-out→synthesize / discover→apply / find→verify→synthesize). After authoring, run
`node --check .claude/workflows/<name>.js` and add its row to the workflows README.

---

## Gate tiers in practice

When the lead declares the gate tier, it should be one line in the PR description:

```
Gate tier: FULL — new write endpoint with auth dependency
Gate tier: LEAN — doc copy update, no logic change
```

The classification checklist:

**FULL** if the slice touches ANY of: authentication / authorization / sessions / secrets /
signing / encryption; data isolation or access scoping; the audit trail or any
state-changing operation; database migrations; money (payments, pricing, billing, credit);
cross-module or cross-service contracts (events, API paths, shared schema); sensitive user
data; a new service; a new write endpoint; anything the critic or auditor would auto-fail;
**anything you are not 100% sure is excluded** (uncertainty is a FULL trigger).

**LEAN** ONLY IF it touches none of the above AND is one of: docs/comments/copy, UI styling
on existing patterns, a read-only endpoint with no new access logic, a behavior-identical
refactor fully covered by existing tests, a dependency bump CI fully exercises.

**What changes between tiers:** LEAN removes only the critic → fixer pre-pass. The auditor,
CI, external review, verify, and human-merge are **identical in both tiers**.

---

## The file-first bug rule

**The moment any agent identifies a bug that will not be fixed in the current loop, the
FIRST action is to file a tracker issue** — before deciding to defer it, route it, note it
as a known limitation, or write it into a report.

- Use `/file-bug <description>` — it reads `issueTracker` from `skills-config.json` (github
  / local / none) and files the issue with the right label vocabulary.
- Any in-code marker for a deferred defect carries the issue URL: `# TODO(#<n>): …`, never a
  bare `TODO`.
- **Covers** (escaping bugs): a pre-existing bug noticed while working, an out-of-scope
  discovery, any security finding, anything called a "follow-up", any `TODO` describing a
  real defect.
- **Does NOT cover** (in-loop findings): a critic finding the fixer resolves in the same PR,
  or the bug the current PR is fixing — those stay in the loop.

The test: *if work is about to end and this bug is still unfixed, it must already have an
issue number.*

---

## Context handoff on long tasks

Long-running leads can exhaust the context window, which causes silent quality degradation —
earlier decisions get forgotten, work gets repeated. The `/context-handoff` skill catches
this **before** quality degrades by triggering a structured stop at safe boundaries.

**When to checkpoint (heuristic triggers):**
- One acceptance criterion completed.
- About to start a sub-task over 100 lines.
- 5+ file edits since last checkpoint.
- 10+ files read since last checkpoint.
- Catching yourself re-summarizing earlier work to remember it.

**Hard fallback** (fire immediately): 50+ total tool calls, 30+ file edits, or 40+
conversation turns in the session.

On checkpoint, the lead writes a handoff file to `.handoff/<agent>-<timestamp>.md`, returns
to the `lead-agent` with a structured `CHECKPOINT` message, and stops. The `lead-agent`
reads the handoff and re-dispatches the lead with "Continue from `.handoff/<file>`".

If the `lead-agent` sees a second consecutive handoff on the same task, the scope is too
large — split it before continuing.

---

## Keeping the context contract fresh

After any slice that changes contracts, endpoints, or data shapes: update `CONTEXT.md` in
the same PR. The `critic` and `auditor` treat stale orientation as a review-blocker.

The Loop 3 freshness sensor watches for drift between sessions and nudges when it detects
that code commits have outpaced `CONTEXT.md` updates. Run `/status` to see the current
freshness state; run `drift-audit` when nudged.

---

## Escalation paths

| Situation | Escalate to |
|---|---|
| Brief and design doc disagree | `lead-agent` |
| Two slices conflict on a shared file | `lead-agent` (picks merge order) |
| A locked decision contradicts another | `lead-agent` → user (new ADR) |
| Can't make the tests pass | `lead-agent` (may dispatch `test-lead`) |
| About to do something destructive | STOP. Ping the `lead-agent` first. |

Always escalate **up** — to the `lead-agent`, then to the user. Agents in isolated contexts
cannot help each other; sideways escalation never resolves.

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
