# Agent Workflow Spec

**Status:** BINDING. Every agent that writes code or modifies a repo MUST read this
before touching the working tree.
**Owner:** the `lead-agent` (the main session). This document is the single source of
truth — agents reference it, they do not duplicate it, they do not deviate from it.

> This is the genericized version of a spec used to build a real ~20-repo platform.
> Adapt the project-specific bits (your CI command, your test floor, your branch names)
> to your stack — the *structure* is the part worth keeping.

---

## Why this exists

You (the agent reading this) are working in a multi-session, multi-stream project.
Without a shared workflow spec, parallel sessions create branch chaos, inconsistent
PRs, skipped quality gates, merge conflicts nobody can resolve, and lost work. This
document fixes that. **Read it once per session; obey it everywhere.**

---

## The team model (three roles)

| Role | Who | Owns | Branch |
|---|---|---|---|
| **Lead** | a domain lead agent (or the `lead-agent` dispatching one) | A whole slice. Reviews junior-worker PRs. Opens the final PR to the main branch. | `feat/<slice-name>` |
| **Junior-worker** | `junior-worker` dispatched by a lead | A bounded sub-task (one file, one endpoint, one model). Opens PR to the lead's feature branch. | `feat/<slice-name>/<sub-task>` |
| **You (the human)** | the user | Final merge authority. Reviews the lead's PR + external review + green checks before merging. | N/A |

All domain leads (`dev-lead`, `design-lead`, `devops-lead`, `test-lead`,
`security-lead`) follow the same pattern. `architect` and `research-lead` don't write
code, so they're exempt.

---

## Cheat-sheet (read before you do anything)

**Route work to the cheapest capable agent — don't burn the top model on grunt work:**

| The work is… | Dispatch | Model |
|---|---|---|
| Mechanical: find/replace, file move, one bounded file, a known command | `junior-worker` | Haiku |
| A whole slice / feature / endpoint / schema, clear scope, one discipline | the domain **lead** | Sonnet |
| Cross-module / shared-package / load-bearing or ADR-worthy decision | `architect` first | Opus |
| Final verdict on a slice | `auditor` (spawned by the lead) | Opus |
| Multi-discipline orchestration / routing across leads | the **main session** as `lead-agent` (a role, NOT a spawned agent) | Opus |

**Before opening ANY PR — prove the gate green locally first.** Run **`/verify-service
<repo>`** (it resolves this repo's CI-equivalent command from the verify map — install,
lint, type-check, migrate, test). Open the PR only when it's green. This is how you stop
wasting CI rounds.

**Use the commands for the boilerplate** — they're the cheapest layer: `/new-slice-branch`
to open the feature branch the right way, `/verify-service` for the pre-PR proof,
`/file-bug` for the file-first rule, `/bump-pointer` for a submodule pointer bump. See
[../.claude/commands/README.md](../.claude/commands/README.md).

**File-first bug rule:** any bug that won't be fixed in this loop gets a tracker issue
BEFORE you defer/route/note it. No bug ever leaves a loop as a bare mention or a bare
`TODO`. (See "Bug tracking" below.)

---

## The flow (top to bottom)

### 1. Slice dispatch
The `lead-agent` hands a slice to a domain lead with: a pointer to the brief/design doc,
the repo path, an effort estimate, and any cross-module contract pointers. The lead owns
it from here until the final PR is merged.

### 2. Lead opens the feature branch
```bash
git fetch origin
git checkout main
git pull --ff-only origin main
git checkout -b feat/<slice-name>
```
Never push an empty feature branch. Push only when there's real work.

### 3. Lead decides: solo or delegate?
For each commit group, the lead picks **solo** (writes it directly) or **delegate**
(spawns a `junior-worker`). Delegate when the task is small, single-file, well-specified,
and needs no architectural judgment. Do it yourself for cross-file coordination, state
design, or security-sensitive code.

### 4. Junior-worker sub-branch flow
```bash
git checkout feat/<slice-name>
git pull --ff-only origin feat/<slice-name>
git checkout -b feat/<slice-name>/<sub-task>
# ... work ...
git push -u origin feat/<slice-name>/<sub-task>
# Open PR: feat/<slice-name>/<sub-task>  →  feat/<slice-name>
```
The junior reports back with the PR URL. The lead reviews the diff, requests changes, or
merges to the feature branch.

### 5. Lead runs the quality pipeline ON THE FEATURE BRANCH
After all sub-tasks are merged (or solo commits are done), classify the tier (FULL vs
LEAN — see "Gate tiering"), then:
1. **Critic** — reviews the full diff for completeness, correctness, rule compliance,
   brief alignment. *(FULL only)*
2. **Fixer** — closes critic findings on the feature branch. *(FULL only)*
3. **Auditor** — independent final verdict: APPROVED / CONDITIONAL / REJECTED. *(both
   tiers)*

If the auditor REJECTS, the lead does NOT merge. The slice goes back to the `lead-agent`
/ user with the rejection report. **Never push a rejected slice to the main branch.**

### 6. Lead opens the final PR to the main branch
When APPROVED (or CONDITIONAL with documented conditions), push and open the PR. Use the
PR template in [PR-TEMPLATE.md](PR-TEMPLATE.md) — it captures scope, commits, the quality
pipeline result, CI gates, external-review status, cross-module impact, and deferred
follow-ups.

### 7. External review (advisory or gate — your call)
If you wire an automated reviewer (e.g. GitHub Copilot) into the PR, triage every comment
**with proof**: a fixing commit SHA, a cited rule/decision that makes it not apply, or a
filed follow-up issue number. "Replied, no proof" does not count as resolved. Decide
up-front whether this reviewer is a **hard gate** (no merge with open threads) or
**advisory** (good signal, not blocking) — and write that choice down so it's not
re-litigated per-PR. A flaky external bot should never be able to deadlock an otherwise
green, auditor-approved PR.

### 8. CI green
CI runs the per-PR gates (lint, types, tests, coverage floor, build). The lead waits for
all checks green — investigating root causes, not blindly retrying — before pinging the
user.

### 9. Lead pings the user for merge
When the auditor is APPROVED, external review is resolved-with-proof (if gated), and all
CI is green, the lead pings the user with: the PR URL, a one-paragraph summary, any
CONDITIONAL items, and any deferred follow-ups.

### 10. User merges
The user reviews PR + CI + review status + diff, then merges. **No agent has merge
authority on the main branch.** This is the single human-judgment chokepoint.

---

## Branch lifecycle (quick reference)

```
main
  └── feat/<slice> (lead owns)
        ├── feat/<slice>/<sub-task-a> (junior)  ──PR──► feat/<slice>
        ├── feat/<slice>/<sub-task-b> (junior)  ──PR──► feat/<slice>
        └── (lead's own commits)
                                                       │
        feat/<slice>  ──quality-pipeline──► critic + fixer + auditor
                                                       │
        feat/<slice>  ──PR──► main  ──external review──► fixes  ──User merges──► main
```

---

## Repo conventions

### Commit message format
```
<type>(<scope>): <imperative one-line subject — <72 chars>

<body explaining WHY, not WHAT. Word-wrap at 80. Reference decision IDs.>

Closes: #<issue>   (if applicable)
```
`<type>` ∈ `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `security`,
`revert`. Imperative mood ("add", not "added"). No trailing period.

### Commit granularity
Aim for one logical change per commit (a migration, a model, a router — one of these,
not all). Each commit should pass tests on its own and have a subject that explains the
change. Never `wip`, never `fix everything`.

### Branch hygiene
Start from latest `main`; pull `--ff-only`; never force-push `main` (enforce with branch
protection); force-push your own feature branch only before the PR is open; delete
branches after merge.

### File hygiene
No trailing whitespace; no editor/IDE junk (covered by `.gitignore`); **no secrets ever**
— if you see one in a diff, STOP and escalate (it's in history; it must be rotated, not
just deleted).

---

## Quality gates (the non-negotiables)

Every PR to the main branch MUST pass:

| Gate | Owned by | Block-on-fail? |
|---|---|---|
| House-rule compliance | lead + critic | YES |
| critic review | lead's critic dispatch | YES (FULL tier) |
| fixer pass | lead's fixer dispatch | only if critic found things |
| auditor verdict | lead's auditor dispatch | YES (APPROVED or CONDITIONAL) |
| CI: lint / types / tests / coverage floor | CI | YES |
| External review resolved with proof | lead | per your gate/advisory choice |
| User merge approval | user | YES |

If you bypass any of these without explicit user permission, you are in violation of
this spec.

---

## Gate tiering — match rigor to blast radius (NEVER lower the bar where it matters)

The classification is binary and **defaults to FULL. Any doubt → FULL.** You may never
argue a risky slice into LEAN.

**FULL tier (all gates) if the slice touches ANY of:**
- Authentication, authorization, sessions, secrets, signing, encryption
- Data isolation / access scoping
- The audit trail or any state-changing operation
- Database migrations
- Money: payments, pricing, billing, credit
- Cross-module / cross-service contracts (events, API paths, shared schema)
- Sensitive user data
- A new service, a new write endpoint, or anything critic/auditor would auto-fail
- **Anything you are not 100% sure is excluded** — uncertainty is a FULL trigger

**LEAN tier ONLY IF it touches none of the above AND is one of:** docs/comments/copy,
UI styling on existing patterns, a read-only endpoint with no new access logic, a pure
behavior-identical refactor fully covered by existing tests, a dependency bump CI fully
exercises.

**What changes between tiers:** LEAN removes only the critic → fixer *pre-pass*. The
auditor still runs its full independent top-down review. CI, external review, verify, and
user-merge are **identical in both tiers.** A LEAN slice whose auditor finds anything
beyond trivial polish is reclassified FULL.

State the chosen tier + one-line reason in the PR description.

---

## Quality-neutral efficiency rules (both tiers)

1. **Don't run the same suite three times.** pre-commit (commit-time) → one pre-PR
   verify (when the slice is done) → CI (authoritative). A fourth manual run adds no
   signal.
2. **Run verify in parallel with the critic/auditor pass** — they're independent.
3. **Warm the venv / cache** so the verify step skips reinstalls once deps are stable.
4. **Enforce model routing** — the biggest token lever. A gate fires identically
   regardless of model; don't pay top-tier prices for mid-tier work.

---

## Workflows — breadth across many repos (orchestrator-only)

A **lead** owns one slice (depth). A **workflow** fans the *same* well-specified operation
across the whole repo universe (breadth) as a deterministic multi-agent script. Only the
**orchestrator** (the main session as `lead-agent`) holds the `Workflow` tool; leads that
discover a breadth-need **report it up** rather than fanning it out themselves.

- **The repo universe is RESOLVED, never inlined.** Every sweeping workflow opens with a
  Resolve phase that walks the precedence ladder in
  [../.claude/workflows/RESOLVER.md](../.claude/workflows/RESOLVER.md)
  (`args → repos.config.js → .gitmodules → marker auto-discovery`) and stops at the first
  non-empty rung. No workflow contains a hardcoded repo list — a repo added next week is
  picked up automatically.
- **Verify is RESOLVED from the config map, never baked in.** A workflow that proves a
  change reads the verify map in `.claude/skills-config.json` and resolves each repo's
  command (`byRepo.overrides → defaults[language] → fallback`) — so the same workflow proves
  a Python service and a Node UI.
- **Doers default to DRY-RUN** — real work in isolated worktrees + real verify, but STOP
  before pushing/PRing until armed with `args: { dryRun: false }`. They open PRs; **the
  user still merges** — the human gate is identical to the interactive flow.

The library and authoring contract live in
[../.claude/workflows/README.md](../.claude/workflows/README.md); author new ones with the
`/create-workflow` skill.

---

## Bug tracking — the file-first rule

**The moment any agent identifies a bug that will NOT be fixed in the current loop, the
FIRST action is to file a tracker issue** — before deciding to defer it, route it, note
it as a "known limitation", or write it into a report. No bug gets deferred,
mentioned-and-forgotten, or left as a bare `TODO`/`FIXME`.

- **Covers** (escaping bugs): a pre-existing bug noticed while working, an out-of-scope
  discovery, any security finding, anything an agent calls a "follow-up", any `TODO`
  describing a real defect.
- **Does NOT cover** (in-loop findings): a critic finding the fixer resolves in the same
  PR, or the bug the current PR is fixing — those stay in the loop.
- **Any in-code marker for a deferred defect carries its issue URL:**
  `# TODO(#<n>): …`, never a bare `TODO`.

The test: *if work is about to end and this bug is still unfixed, it must already have an
issue number.*

---

## Escalation paths — escalate UP, never sideways

| Situation | Escalate to |
|---|---|
| Brief and design doc disagree | `lead-agent` |
| Two slices conflict on a shared file | `lead-agent` (picks merge order) |
| A locked decision contradicts another | `lead-agent` → user (new ADR) |
| You can't make the tests pass | `lead-agent` (may dispatch test-lead) |
| You're about to do something destructive | STOP. Ping the `lead-agent` first. |

Other agents run in isolated contexts and cannot help you. The `lead-agent` is the only
cross-session coordinator.

---

## Auto-fail conditions (do not ship)

Customize this list to your stack. Common ones:
- Secrets in code / committed env files / obfuscated credentials
- A write endpoint without its auth/signing dependency
- A query that doesn't apply the required access scope
- Hard delete on business data (must be soft delete)
- A state-changing operation with no audit entry
- Debug `print()`/`console.log` left in
- A new service that doesn't clone from your template

The critic flags these; the auditor gates on them. Non-negotiable.

---

## Updating this document

This spec is version-controlled. Change it via a PR to the main branch, with a
description of what's changing and why. **Never change it during an in-flight slice** —
wait until between slices.

---

**End of spec.**

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
