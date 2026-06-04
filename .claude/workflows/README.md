# Workflows library

Durable, git-tracked, **named** multi-agent workflows for your workspace.

A workflow is a JavaScript orchestration script the **main session** launches via the
`Workflow` tool. Unlike the interactive lead flow (you drive each step, turn by turn), a
workflow **fans work out to many isolated agents deterministically** — `parallel()` /
`pipeline()` / loops — and returns one structured result. It is the right tool for
**breadth** (the same thing across many repos), where leads are the right tool for
**depth** (one slice, your judgment, human-in-loop).

These live here (not in a session dir) so they are: **named** (`Workflow({ name: "…" })`),
**reusable across sessions**, **versioned in git**, and **reviewable**. A one-off
workflow run only persists in the session dir and is gone when that session is cleaned —
promote anything worth keeping into this folder.

## How to run one

You don't write JS. You ask the main session, e.g. *"run the hygiene-fix-sweep"* or
*"use the cross-repo-migration workflow to bump the shared core lib to 0.2.0."* The main
session invokes `Workflow({ name: "<name>", args: {…} })`. Watch live progress in
`/workflows`.

## The repo universe is RESOLVED, never hardcoded

**No workflow inlines a list of repos.** Hardcoding rots — a repo added next week is
silently skipped. Instead every sweeping workflow opens with a **Resolve phase** that
spawns one short-lived discovery agent. That agent walks the precedence ladder in
[`RESOLVER.md`](RESOLVER.md) and **stops at the first non-empty rung**:

1. explicit `args.repos`
2. `.claude/workflows/repos.config.js` (the consumer manifest — see
   [`repos.config.example.js`](repos.config.example.js))
3. `.gitmodules` (a superproject's submodules)
4. marker-based auto-discovery (`pyproject.toml`, `package.json`+lockfile, `pom.xml`,
   `go.mod`, `*.tf`, …)

The agent returns a structured manifest of `{name, path, class, language}` plus a `gaps[]`
list (detected languages with no installed pack) and the `source` rung. The workflow then
fans its real work across that manifest. Because the orchestration script itself has no
filesystem access, this discovery agent is the **only** way a workflow learns its repo
universe — and it learns it the same way every time, correct as the workspace grows.

## Verify is RESOLVED from the config map, never hardcoded

When a workflow needs to *prove* a change (CI-equivalence), it does **not** bake in a
toolchain. The agent running the verify reads `.claude/skills-config.json`'s 2-D
language×class **verify map** and resolves the repo's command:

```
verify.byRepo.<name>.overrides.<stage>  →  verify.defaults.<language>.<stage>  →  built-in fallback
```

So the same workflow proves a Python repo with its lint+test+coverage chain, a Node UI
with lint+build+test, and an infra repo with validate+fmt-check — all from config, no
per-toolchain branches in the workflow body. See `skills-config.example.json`.

## The library

| Name | Kind | What it does | Writes code? |
|---|---|---|---|
| **build-status-audit** | read-only | Per-repo BUILT vs DESIGNED vs PLANNED truth from code+git (not plan docs). Verifies "design is locked" claims. | no |
| **drift-audit** | read-only | The honest mirror: detects 3 drift types per repo — doc-vs-code (CONTEXT.md freshness), config-vs-baseline (hygiene gates), copy-vs-source (diverged propagated files). Pairs with hygiene-fix-sweep (fixes the config axis). | no |
| **hygiene-fix-sweep** | doer (parameterized) | Applies ONE configured baseline-config fix (`args.baseline`) to every repo that lacks it; verifies each; opens a PR per repo. Default baseline = a coverage-precision example. | yes |
| **submodule-sync-sweep** | doer | Finds stale parent submodule pointers after a merge wave (superproject only), bumps them, opens the parent PR(s). | yes |
| **cross-repo-migration** | doer (parameterized) | One change (bump a dep / rename an event / add a CI gate) discovered + applied + verified + PR'd across every affected repo. | yes |
| **slice-ship** | doer (parameterized) | One slice through the FULL pipeline (impl → critic → fixer → auditor → **script-run verify** → PR). The verify gate is run by the script, so it can't be faked. | yes |

> **Rename note:** `submodule-sync-sweep` is the workflow formerly called
> `pointer-bump-sweep`. Same behavior (detect stale submodule pointers → bump → PR),
> generic name. Each workflow's `meta.name` equals its filename slug.

## DRY-RUN safety (the doers)

Every doer defaults to **`DRY_RUN = true`**: it does the real work in **isolated git
worktrees** and runs the real verify, but **STOPS before pushing / opening PRs** —
reporting the diff it *would* open. Arm it for real with `args: { dryRun: false }`.

```
Workflow({ name: "hygiene-fix-sweep" })                            # dry-run: shows what it'd fix
Workflow({ name: "hygiene-fix-sweep", args: { dryRun: false } })   # armed: opens the PRs
```

Parameterized doers need their spec in `args`:

```
Workflow({ name: "cross-repo-migration", args: {
  change: { title: "bump-core-0-2-0",
            instruction: "Bump the shared core dependency to ==0.2.0 in the package manifest and reinstall.",
            grepHint: "core==" },
  dryRun: false,
}})

Workflow({ name: "slice-ship", args: {
  slice: { repo: "billing-service", brief: "<brief text or path>",
           scope: "in: X,Y  out: Z" },
}})

Workflow({ name: "hygiene-fix-sweep", args: {
  baseline: { title: "mypy-blocking",
              detect: "CI must run the type-checker as a blocking step (not continue-on-error).",
              fix: "Remove continue-on-error from the type-check CI step; touch nothing else.",
              classes: ["SERVICE", "LIBRARY"] },
}})
```

## Control-Board pattern: the 5-stage feature lifecycle

A sustainable organization ships features through a gated, human-in-loop cadence. The **Control-Board pattern** is
the discipline that disciplines the ship — it defines five stages where work fans out (agents), converges (audits),
and halts at **deliberate human gates** before the next leg.

### The five stages

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Stage 1: feature-intake                                                  │
│ • User/PM drafts brief + scope in a spec doc (Workspace context)         │
│ • Discovery agent resolves the slice (e.g., which repos are affected)    │
│                                                                           │
│ ──→ [HUMAN GATE #1: SCOPE LOCKED] ←─────────────────────────────────   │
│     An explicit human review: "This scope is feasible, clear, aligned"   │
│                                                                           │
├──────────────────────────────────────────────────────────────────────────┤
│ Stage 2: feature-design                                                  │
│ • Impl agent(s) draft design doc (no code yet)                           │
│ • Critic reviews design; fixer incorporates feedback                     │
│ • Auditor signs off on feasibility + dependencies                        │
│                                                                           │
│ ──→ [HUMAN GATE #2: DESIGN APPROVED + dryRun ARMED] ←──────────────── │
│     Two things happen here — a human reviews + approves the design,     │
│     AND the human EXPLICITLY sets dryRun:false on the slice-ship call. │
│     This is the chokepoint. Gate #2 is not "agent says done"; it is    │
│     a deliberate human action that arms the ship.                       │
│                                                                           │
├──────────────────────────────────────────────────────────────────────────┤
│ Stage 3: slice-ship (the real work)                                      │
│ • Impl agent(s) code the feature across the affected repos (dryRun=false)│
│ • Critic reviews code + git diffs                                        │
│ • Fixer addresses feedback (code rework)                                 │
│ • Auditor verifies: green verify, CONTEXT.md fresh, no sacred violations │
│ • Script-asserted gate: tree-clean, staged-by-name, verify GREEN        │
│ • PR opens (if all checks pass) to integration branch                    │
│                                                                           │
│ ──→ [HUMAN MERGE GATE] ←────────────────────────────────────────────   │
│     Human merges the PR (no auto-merge). This is the second human       │
│     chokepoint — merge only after final QA / review.                    │
│                                                                           │
├──────────────────────────────────────────────────────────────────────────┤
│ Stage 4: launch-readiness-audit (or drift-audit for ongoing features)   │
│ • Auditor scans: doc-vs-code (CONTEXT stale?), config-vs-baseline       │
│ • Produces findings (no auto-fix at this stage)                          │
│ • Filer surfaces findings to the board (GitHub issues)                   │
│                                                                           │
│ ──→ [Inform, not gate] ──────────────────────────────────────────────   │
│     Findings inform the next cycle; they do not block.                   │
│                                                                           │
├──────────────────────────────────────────────────────────────────────────┤
│ Stage 5: (optional) post-launch observables / hygiene                    │
│ • Sweep workflows (hygiene-fix-sweep, drift-audit re-run on schedule)   │
│ • Drift-audit doubles as a living "truth" audit — no design debt         │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### The gates are deliberate human actions, never auto-reported

**Gate #1 (Scope Locked)** — a human reads the feature-intake scope and approves it; they do not ask an agent
"is this good?" They review directly and issue a decision: "locked" or "rework scope."

**Gate #2 (Design Approved + dryRun Armed)** — a human reads the design doc (agent-drafted, critic-refined), decides
it is sound, and EXPLICITLY sets `dryRun: false` when invoking the `slice-ship` workflow. No automation arms it. No
agent says "design is done"; a human DECIDES to arm the ship.

**Merge Gate** — after slice-ship opens a PR, a human (or human automation like CI + branch protection) decides
whether to merge. The PR is there; the verify is green; the choice remains human. This is the firewall between
integration and shipping.

### The workflows are parked; you wire the intake/design cycle

The workflows `feature-intake` and `feature-design` are **not yet shipped**; they are _available_ as patterns
to build on using the **`create-workflow`** skill. When you need to wire a feature intake → design cycle,
invoke `create-workflow` and reference this pattern (the sections above define the contract). The `slice-ship`
workflow **is** shipped and ready — it runs stage 3 end-to-end.

**Why parked?** Every organization's intake → design → scope-lock → arm-ship cadence is slightly different.
The pattern teaches the shape; you wire it to match your culture + tooling.

## Safety net (always on)

Workflows obey the same guardrails as everything else:
- **No auto-merge to the default branch** — doers open PRs; *you* merge (the single human
  chokepoint).
- The **PreToolUse hooks** fire on every agent's Bash/Write surface — a workflow agent
  can't force-push the default branch, `rm -rf`, or write a secret
  (`block-secrets-in-writes.sh` + the project's git-guard hook) — any more than you can.
- Stage **by explicit name**, never `git add -A` — baked into every doer's prompt.

## Authoring a new workflow

Use the **`create-workflow`** skill. It encodes the resolver model, the verify-map idiom,
the `meta`-literal rule, the JS-not-TS limits, the three shapes (fan-out→synthesize /
discover→apply / find→verify→synthesize), and the DRY-RUN default. Always validate with
`bash .claude/workflows/verify-workflow.sh .claude/workflows/<name>.js` before declaring a
workflow done — NOT plain `node --check`, which is a false-green for workflow files (they
carry both `export const meta` and top-level `return`; see issue #12). Then add its row
here with `meta.name` == the filename slug.

## Promoting a one-off into the library

Ran a useful one-off this session? Its script is in the session dir. Lift it here, strip
any run-id from the filename and `meta.name`, add a `whenToUse`, and replace any inlined
repo list with the Resolve phase (per RESOLVER.md). That's how a one-off becomes durable.
