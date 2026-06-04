# Getting Started

This page takes you from zero to a running crew: copy the framework in, run `/install`, let
the onboarding loop greet you, orient the repo, and kick off your first slice. The full
details live in [docs/INSTALL.md](../INSTALL.md); this page is the fast path with pointers
into the full walkthrough.

---

## Prerequisites

- [Claude Code](https://claude.com/claude-code) installed and authenticated.
- A git repo on disk. The framework assumes git — the safety hooks, the workflow, and the
  branch model are all git-based.
- Nothing else. No services to run, no external dependencies.

---

## Step 1 — Copy the framework in

```bash
# From your project root:
cp -r /path/to/crew-for-claude/.claude  ./.claude
cp -r /path/to/crew-for-claude/packs    ./packs    # optional: stack packs
cp -r /path/to/crew-for-claude/docs     ./docs     # optional: workflow spec + ADRs
```

On Windows PowerShell:

```powershell
Copy-Item -Recurse /path/to/crew-for-claude/.claude  .\.claude
Copy-Item -Recurse /path/to/crew-for-claude/packs    .\packs
Copy-Item -Recurse /path/to/crew-for-claude/docs     .\docs
```

---

## Step 2 — Open Claude Code and run `/install`

Open Claude Code in the repo root. The **onboarding sensor** (`onboard.sh`) fires
immediately at session start: it detects that the crew is not yet installed and offers you
the right path forward based on what it finds:

- **Empty or new project** → it offers to scaffold `CLAUDE.md` + `CONTEXT.md` from
  templates and then run `/install`.
- **Existing project** → it offers `/orient` (to generate a real `CONTEXT.md` from your
  actual code) followed by `/install`.
- **Multi-repo workspace** → it offers `/install --dry-run` to resolve the whole repo
  universe, then `/orient` per repo.

You do not need to script the loop — the sensor surfaces the right offer and you confirm.

To install manually, run:

```
/install --dry-run        # show the plan; writes nothing — always start here
/install                  # apply the plan
/install --repos a,b,c    # scope to a named subset (skips full discovery)
```

`/install` runs **Detect → Scope → Wire**:

- **Detect** — classifies languages by file markers (`pyproject.toml` → python,
  `package.json`+lockfile → node, `pom.xml`/`build.gradle` → java, `go.mod` → go,
  `*.tf` → infra) and infers project shape (monorepo / multi-repo / single).
- **Scope** — resolves the repo universe using the precedence ladder: `--repos args →
  repos.config.js → .gitmodules → marker auto-discovery`.
- **Wire** — generates `repos.config.js` (the repo manifest), `.claude/skills-config.json`
  (the verify map + tracker), `hook-globs.env`, activates the matching language pack, seeds
  `.claude/memory/MEMORY.md`, wires the five Claude Code hooks into `.claude/settings.json`,
  and installs the commit-message naming guard shim — idempotently, never clobbering a file
  you wrote.

What the Wire step activates:

| Hook | Wired via | When | What it does |
|---|---|---|---|
| `block-dangerous-git.sh` | `settings.json` | Every Bash call | Blocks force-push to protected branch, `rm -rf`, DB drops |
| `block-secrets-in-writes.sh` | `settings.json` | Every file write | Blocks credentials landing in tracked files |
| `onboard.sh` | `settings.json` | SessionStart | Onboarding sensor (Loop 1) — goes silent once installed |
| `check-freshness.sh` | `settings.json` | SessionStart | Freshness sensor (Loop 3) — nudges toward `drift-audit` when docs lag |
| `suggest-memory.sh` | `settings.json` | Stop | Learning sensor (Loop 2) — notices durable lessons and nudges `/remember` |
| `check-commit-msg.sh` | `.git/hooks/commit-msg` shim | git commit | Naming guard — rejects commit messages naming model vendor/tiers |

It ends with a report: detected languages, shape, resolved repo manifest, every wire action,
activated packs, and — mandatory — any **gaps** (a detected language with no active pack).

> **Existing repo?** The only extra step is filling in `CLAUDE.md` / `CONTEXT.md`. `/install`
> leaves an existing `CLAUDE.md` untouched. If it still contains the bare template placeholder
> text, ask the `lead-agent`: *"Read this codebase and draft CLAUDE.md and CONTEXT.md from
> templates/ — use what's actually here."* Review the drafts (the domain *why* is yours
> alone), then commit.

---

## Step 3 — Run `/orient` on an existing repo

`/orient` is the **wow moment** of the onboarding loop. Point the crew at any repo and,
minutes later, it understands it — a real `CONTEXT.md` with the data model, public surface,
module map, and domain glossary, generated from the **actual code**, not guessed.

```
/orient
```

The skill:
1. Reads the repo (entry points, data model, public surface, domain vocabulary, cross-module
   contracts) — invoking `/survey-code` for unfamiliar/large areas.
2. Drafts `CONTEXT.md` from the template, grounding every claim in a file.
3. Shows you the draft before writing anything. On confirm, writes the file and prints a
   receipt.

For a multi-repo workspace it generates one `CONTEXT.md` per repo (each at its repo root)
plus a top-level workspace `CONTEXT.md` that maps "which repo owns what."

The generated `CONTEXT.md` is what makes every subsequent agent session faster: a fresh
agent orients in minutes instead of re-deriving the project from scratch.

---

## Step 4 — Check the cockpit: `/status`

```
/status
```

This is the **cockpit** — a single-screen, read-only health view that shows the state of
every part of the framework in your workspace:

```
╔═══════════════════════════════════════════════════════════════╗
║  CREW STATUS — my-project               2026-06-04            ║
╠═══════════════════════════════════════════════════════════════╣
║  Install      ✅ wired (2 repos, packs: python-fastapi)       ║
║  Orientation  ✅ 2/2 repos oriented                           ║
║  Learning     📚 3 memories (1 feedback, 2 project)           ║
║  Freshness    ✅ docs current                                  ║
║  Safety       ✅ git-guard + secret-scan wired (branch: main) ║
║  Open work    🐛 1 open issue                                  ║
╚═══════════════════════════════════════════════════════════════╝

Next actions:
  (all green — nothing needed)
```

Every `⚠️` line names the one command that closes the gap. Run `/status` at the start of
any session where you want a quick health-check.

---

## Step 5 — Fill in the context files

These two files are the **context contract** — the highest-leverage thing you do after
install. See [docs/THE-METHOD.md](../THE-METHOD.md) → "The context contract" for the full
rationale, and [docs/INSTALL.md](../INSTALL.md) → "Filling in the context files" for the
questions each file should answer.

| File | Role |
|---|---|
| `CLAUDE.md` | The **rules** — house style, constraints, prohibited patterns, links to deeper docs |
| `CONTEXT.md` | The **orientation** — what this repo owns, its data model, its contracts, its domain glossary |

**The freshness rule is the whole point:** any change that alters contracts, endpoints, or
data shape must update `CONTEXT.md` in the *same* change. The `critic`/`auditor` treat
stale orientation as a review-blocker.

---

## Step 6 — Your first slice

Describe a concrete goal to the main session, which acts as `lead-agent`:

```
"Add a health-check endpoint at GET /health — follow the workflow spec."
```

You should see the crew:
1. Read `CLAUDE.md` / `CONTEXT.md` / `docs/AGENT-WORKFLOW.md`.
2. Open a `feat/` branch via `/new-slice-branch`.
3. Dispatch the appropriate domain lead (e.g. `dev-lead`).
4. Run the quality pipeline (critic → fixer → auditor).
5. Stop and ask **you** to merge — the human merge gate never moves.

If the crew tries to merge to the main branch itself, the `CLAUDE.md` isn't reinforcing the
human-merge gate hard enough — add a line. That gate is non-negotiable.

For planning a larger release, use [docs/WAVE-PLAN-TEMPLATE.md](../WAVE-PLAN-TEMPLATE.md)
to structure work as waves of parallel slices before dispatching any leads.

---

## What just happened (the full picture)

After completing these steps your workspace has:

- All 15 agents, 18 skills, 5 commands, 6 workflows live and discoverable.
- Two safety backstops active on every Bash call and every file write.
- Three loop sensors active: onboarding goes silent, learning watches for durable lessons,
  freshness watches for doc drift.
- A real `CONTEXT.md` that gives every future agent a running start.
- A memory index (`.claude/memory/MEMORY.md`) where lessons will accumulate.

The workspace is now alive. The three loops do the rest over time.

See [The Three Loops](./three-loops.md) for the full story of how the workspace grows.

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
