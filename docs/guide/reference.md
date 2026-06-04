# Reference — Full Inventory

Complete tables for every agent, skill, command, workflow, hook, and pack in the framework.
This is the lookup surface: one accurate line per item. For the full spec of any item, follow
the link to the source file.

---

## Agents (15)

Source: [`.claude/agents/`](../../.claude/agents/)

### Orchestrator and coordination

| Agent | Model | Role |
|---|---|---|
| `lead-agent` | Opus (main session) | **Role, not a spawn target.** The main session plays this role: decomposes requests, routes to domain leads, integrates results, reports to the user. Holds the `Workflow` tool. |
| `architect` | Opus | Cross-cutting design *before* code. Produces an architecture brief; does not write code. Spawn when work touches >1 module or is ADR-worthy. |

### Domain leads (7, spawnable)

| Agent | Model | Role |
|---|---|---|
| `dev-lead` | Sonnet | Backend, frontend, APIs, data, integrations. Owns a development slice end-to-end + runs the quality pipeline. |
| `design-lead` | Sonnet | UI/UX, API contracts, schemas, wireframes (text/mermaid/SVG). Runs critic → fixer → auditor. |
| `devops-lead` | Sonnet | CI/CD, IaC, deploy, observability. Non-local actions gated behind typed user approval. |
| `test-lead` | Sonnet | Test strategy + QA validation. No fixer — failures route back up. |
| `security-lead` | Opus | Authorized security work only. No fixer — findings route back up. |
| `research-lead` | Sonnet | Feasibility, standards, market scans. Time-boxed reports, not code. |
| `media-lead` | Sonnet | Content copy, image briefs, brand voice. Does not render bitmaps. |

### Execution specialists

| Agent | Model | Role |
|---|---|---|
| `junior-worker` | Haiku | Bounded sub-tasks under any domain lead: one file, one endpoint, one schema. Never delegates further. |
| `tester` | Haiku | Executes tests and collects evidence under `test-lead`. |
| `pentester` | Sonnet | Authorized active security testing under `security-lead`, within defined scope. |

### Quality pipeline (3)

| Agent | Model | Role |
|---|---|---|
| `critic` | Sonnet | First quality gate — reviews the full diff for completeness, correctness, and rule compliance. Produces a structured issue list. FULL tier only. |
| `fixer` | Sonnet | Resolves critic findings on the feature branch without scope creep. FULL tier only (and only when critic found issues). |
| `auditor` | Opus | Final independent verdict: APPROVED / CONDITIONAL / REJECTED. Both tiers. If REJECTED, the lead does not merge. |

---

## Skills (18)

Source: [`.claude/skills/`](../../.claude/skills/)

Each skill lives at `.claude/skills/<name>/SKILL.md`. Agents invoke them; you can invoke
them directly too.

### Method-critical

| Skill | Who uses it | What it does |
|---|---|---|
| `orient` | onboarding loop (Loop 1) | Generates a real `CONTEXT.md` from actual code — data model, public surface, module map, glossary. The orientation actuator. Draft-show-confirm; never clobbers an authored file. |
| `remember` | learning loop (Loop 2) | Routes a durable lesson to its home: rule → `CLAUDE.md`, orientation → `CONTEXT.md`, decision → ADR, preference → `.claude/memory/`. Propose-never-auto-write for tracked files. |
| `install` | onboarding | Detect → Scope → Wire: classifies stack, resolves repo universe, generates config, wires hooks (including the three-loop sensors), seeds `.claude/memory/`. Idempotent; `--dry-run` previews. |
| `interrogate-plan` | `lead-agent`, `architect` | Front-loads decisions against `CONTEXT.md` + ADRs before any lead builds. Updates them inline. The executable form of habit #1. |
| `draft-prd` | `lead-agent`, `architect` | Turns converged decisions into a PRD before dispatching leads. |
| `slice-issues` | `lead-agent` | Breaks a plan into tracer-bullet vertical slices — one slice = one lead invocation. |
| `test-first` | `dev-lead` | Red-green-refactor; the default build loop where a test seam exists. |
| `troubleshoot` | `dev-lead` | Disciplined debugging loop for hard bugs and performance regressions. |
| `context-handoff` | all long-running leads | Compacts in-flight work into a structured handoff file so a fresh instance resumes cleanly. Includes FILE-FORMAT, RESUME, and TRIGGERS reference documents. |
| `create-workflow` | `lead-agent` | Authors a new named workflow with the resolver model, verify-map idiom, and DRY-RUN default baked in. Includes PATTERNS and RULES reference documents. |

### Optional / productivity

| Skill | What it does |
|---|---|
| `stress-test` | Lighter grilling when there is no `CONTEXT.md` to anchor on yet. |
| `mockup` | Throwaway prototype to settle a state machine, data shape, or UI choice. Includes LOGIC and UI reference documents. |
| `survey-code` | Produces a module/caller map in domain vocabulary before touching unfamiliar code. Used internally by `/orient`. |
| `deepen-architecture` | Identifies deepening and refactoring opportunities informed by `CONTEXT.md` + ADRs. Includes DEEPENING, INTERFACE-DESIGN, HTML-REPORT, and LANGUAGE reference documents. |
| `sort-issues` | Runs an incoming-issue queue through a triage state machine. Includes AGENT-BRIEF and OUT-OF-SCOPE reference documents. |
| `bootstrap-skills` | One-time bootstrap for the issue tracker + label vocabulary. |
| `terse-mode` | Ultra-terse output mode to save context on long sessions. |
| `author-skill` | Authors a new skill with proper structure and frontmatter. |

---

## Commands (5)

Source: [`.claude/commands/`](../../.claude/commands/)

Commands are prompt templates (`.md` files with `$ARGUMENTS` substituted). No agents, no
logic — the cheapest reusable action in the framework.

| Command | What it does |
|---|---|
| `/status [repo]` | **The cockpit.** One-screen read-only health view: install state, orientation (Loop 1), memories captured (Loop 2), doc freshness (Loop 3), safety-hook wiring, open work. Every `⚠️` line names the one command that closes the gap. |
| `/verify-service <repo>` | The pre-PR CI-equivalence proof. Resolves the repo's verify command from `skills-config.json` (language × class map) — no hardcoded toolchain. |
| `/new-slice-branch <slice>` | Opens `feat/<slice>` off the default branch, scaffolds a DESIGN doc stub, and reminds the lead of the gate tier to declare. |
| `/file-bug <description>` | Files an issue on the configured tracker (github / local / none) per the file-first rule. Reads `issueTracker` + label vocabulary from `skills-config.json`. |
| `/bump-pointer <submodule…>` | Post-merge parent submodule pointer bump, staged by explicit name. For superproject workspaces only. |

---

## Workflows (6)

Source: [`.claude/workflows/`](../../.claude/workflows/)

All workflows are resolver-driven (no inlined repo lists) and verify-map-driven (no hardcoded
toolchains). Doers default to DRY-RUN. Only the orchestrator holds the `Workflow` tool.

| Workflow | Kind | What it does |
|---|---|---|
| `build-status-audit` | read-only | Per-repo BUILT vs DESIGNED vs PLANNED truth from code + git. Verifies "design is locked" claims. |
| `drift-audit` | read-only | Detects three drift types per repo: doc-vs-code (CONTEXT.md freshness), config-vs-baseline (hygiene gates), copy-vs-source (diverged propagated files). The freshness actuator (Loop 3). |
| `hygiene-fix-sweep` | doer (parameterized) | Applies one configured baseline-config fix to every repo that lacks it; verifies each; opens a PR per repo. |
| `cross-repo-migration` | doer (parameterized) | One change (bump a dep, rename an event, add a CI gate) discovered + applied + verified + PR'd across every affected repo. |
| `submodule-sync-sweep` | doer | Finds stale parent submodule pointers after a merge wave, bumps them, opens the parent PR(s). |
| `slice-ship` | doer (parameterized) | One slice through the FULL pipeline: implementation → critic → fixer → auditor → script-run verify → PR. The verify gate is run by the script — it cannot be faked. |

Also in `.claude/workflows/`:
- `RESOLVER.md` — the repo-universe precedence contract (`args → repos.config.js → .gitmodules → marker auto-discovery`).
- `repos.config.example.js` — the shape of the consumer repo manifest.

---

## Hooks (6 core + 2 pack)

Source: [`.claude/hooks/`](../../.claude/hooks/)

### Safety backstop family (PreToolUse — fail safe / over-block)

| Hook | Matcher | What it does |
|---|---|---|
| `block-dangerous-git.sh` | `Bash` | Blocks force-push to the protected branch, `rm -rf`, `git reset --hard`, `git clean -f`, destructive DB ops (`DROP`/`TRUNCATE TABLE`, `dropdb`), and real secrets in commands. Warns (does not block) on parallel-session collision. |
| `block-secrets-in-writes.sh` | `Write\|Edit\|MultiEdit\|NotebookEdit` | Scans content about to be written for credential shapes before it lands in a tracked file. Allows writes to gitignored secret-bearing files (`.env`, `*.pem`, `*.key`). |
| `secret-patterns.sh` | *(sourced, not matched)* | Single source of truth for credential shapes — sourced by both hooks above so neither surface can disagree on what counts as a secret. |

### Three-loop sensor family (SessionStart / Stop — fail silent / nudge-only)

| Hook | Matcher | What it does |
|---|---|---|
| `onboard.sh` | `SessionStart` | Loop 1 sensor: detects un-installed or un-oriented repos, identifies folder shape, surfaces the right install/orient offer. Goes silent once installed + `CONTEXT.md` authored. |
| `check-freshness.sh` | `SessionStart` | Loop 3 sensor: counts code-bearing commits since `CONTEXT.md`'s last commit. Over `STALE_THRESHOLD` (default 15) → nudges toward `drift-audit`. |
| `suggest-memory.sh` | `Stop` | Loop 2 sensor: reads the last user message from the transcript, matches durable-lesson phrases, emits a one-line nudge toward `/remember`. Never writes, never blocks. |

### Naming guard

| Hook | Matcher | What it does |
|---|---|---|
| `check-commit-msg.sh` | `commit-msg` (git hook) | Rejects commit messages naming a model vendor or tier (Anthropic / Claude Code / Sonnet / Haiku / Opus) when `attributionTrailer` is configured in `skills-config.json` (default OFF). Installed via a one-line shim in `.git/hooks/commit-msg`; `/install` wires the shim automatically. |

### Pack-scoped hooks (python-fastapi pack only)

| Hook | Matcher | What it does |
|---|---|---|
| `enforce-venv.sh` | `Bash` | Enforces the Python venv rule: one `.venv` at the repo root, every Python command (`pip`/`python`/`pytest`/`mypy`/…) runs inside it. Bare system-interpreter commands are blocked. |
| `block-destructive-migrations.sh` | `Bash` | Blocks irreversible `alembic downgrade base` / relative rollbacks. Language-specific; kept out of the language-neutral core git guard. |

---

## Packs (4)

Source: [`packs/`](../../packs/)

Packs teach the crew one language/stack. Core stays language-agnostic; all language-specific
knowledge lives in packs. See [`packs/PACK-SPEC.md`](../../packs/PACK-SPEC.md) for the full
authoring contract.

| Pack | Status | Commands | Hooks | Notes |
|---|---|---|---|---|
| `python-fastapi` | **active** | `new-model`, `new-router`, `new-event`, `new-sqs-handler`, `lint`, `run-tests`, `migrate`, `audit` (8 total) | `enforce-venv.sh`, `block-destructive-migrations.sh` | Verify defaults: flake8 + mypy + pytest --cov. The one complete, deployable pack. |
| `java` | spec-only | — | — | `pack.json` stub + README. Detected by `/install` as a gap; contributes no verify commands or hooks. |
| `node` | spec-only | — | — | `pack.json` stub + README. Same gap behavior as java. |
| `go` | spec-only | — | — | `pack.json` stub + README. Same gap behavior as java. |

---

## Config files (consumer-owned)

These files live in the consuming project, generated by `/install` and owned by the consumer:

| File | Role |
|---|---|
| `.claude/workflows/repos.config.js` | The **repo universe** manifest — `{name, path, class, language}` per repo. Workflows resolve through this; nothing inlines a repo list. |
| `.claude/skills-config.json` | The **verify map** (`verify.defaults.<language>` + per-repo `verify.byRepo` overrides) and the issue-tracker block. The 2-D map that makes one crew serve any stack. |
| `.claude/hooks/hook-globs.env` | Project-specific hook values (`PROTECTED_BRANCH`, test-secret allowlist). |
| `.claude/memory/MEMORY.md` | The **memory index** — one pointer line per captured lesson. Read at session start by the `CLAUDE.md` instruction. |

Reference configs in this repo: `.claude/skills-config.example.json` (shape + comments) and
`.claude/skills-config.schema.json` (JSON Schema for validation).

---

## Templates

Source: [`templates/`](../../templates/)

| File | What it is |
|---|---|
| `CLAUDE.md.template` | The per-repo rules file template. Sections: project identity, authoritative docs table, stack, architecture non-negotiables, house style, auto-fail conditions, credential handling, bug tracking, crew routing, three loops summary, working style. |
| `CONTEXT.md.template` | The per-repo orientation file template. Sections: responsibility boundary, the one file to read first, data model, endpoints/public surface, cross-module contracts, domain glossary. |
| `ADR.template.md` | Architecture decision record template. |

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
