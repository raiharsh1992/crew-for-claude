# Installing the crew into your project

This kit drops into **any** repo or workspace — brand new or existing, single repo or
multi-repo, one language or polyglot. The kit itself hardcodes **nothing** about your
project: the repo universe, the verify commands, the language pack, and the issue tracker
all live in per-project config that **`/install` generates for you** (the reasoning is in
[adr/0001-projects-self-configure-via-install-resolver-packs.md](adr/0001-projects-self-configure-via-install-resolver-packs.md)).

> **The onboarding loop greets you.** Once you copy `.claude/` in and open Claude Code,
> the `onboard.sh` sensor fires at session start, detects the folder shape (empty / single
> repo / multi-repo), and surfaces the right offer. You do not need to remember the install
> steps — the sensor tells you what to run. It goes silent once the crew is installed and
> `CONTEXT.md` is authored.
>
> **On an existing repo, reach for `/orient` and `/status` first:**
> - **`/orient`** — reads the codebase and generates a real `CONTEXT.md` (data model,
>   public surface, module map, glossary). The single highest-leverage action on a new repo.
> - **`/status`** — the cockpit: a one-screen read-only view of install state, orientation,
>   what the crew has learned, doc freshness, safety-hook wiring, and open work. Every `⚠️`
>   line names the command that closes the gap.

---

## Prerequisites

- [Claude Code](https://claude.com/claude-code) installed and authenticated.
- A git repo (the kit assumes git; the safety hooks and workflow are git-based).
- That's it. No services to run, no dependencies to install.

---

## The happy path — copy `.claude/` in, then run `/install`

```bash
# 1. Copy the crew in (adjust the source path to wherever you cloned this kit).
#    Bring packs/ + docs/ too if you want language scaffolding and the binding spec.
cp -r /path/to/crew-for-claude/.claude  ./.claude
cp -r /path/to/crew-for-claude/packs    ./packs    # optional: stack packs
cp -r /path/to/crew-for-claude/docs     ./docs     # optional: workflow spec + ADRs
```
On Windows PowerShell, swap `cp -r` for `Copy-Item -Recurse`.

Then **open Claude Code in the repo and run the installer:**

```
/install --dry-run        # show the plan, write NOTHING — always start here
/install                  # apply the plan
/install --repos a,b,c    # scope to a named subset (skips full discovery)
```

`/install` runs **Detect → Scope → Wire**:

- **Detect** — classifies the stack(s) by file markers (`pom.xml`→java, `package.json`+lockfile
  →node, `pyproject.toml`/`requirements.txt`→python, `go.mod`→go, `*.tf`→infra; multi-hit =
  polyglot) and infers the shape (monorepo / multi-repo / single).
- **Scope** — resolves *which* repos the crew manages, via the precedence ladder in
  [../.claude/workflows/RESOLVER.md](../.claude/workflows/RESOLVER.md):
  `--repos → repos.config.js → .gitmodules → marker auto-discovery`. (v1 is
  configure-in-place over repos already on disk; clone-into-workspace is a fast-follow.)
- **Wire** — generates the project's config, **idempotently, never clobbering a file you
  wrote**: `repos.config.js` (the manifest), `.claude/skills-config.json` (the verify map +
  tracker), the hook globs, the matching language pack, the `CLAUDE.md`/`CONTEXT.md`
  templates *only if absent*, seeds `.claude/memory/MEMORY.md` (the learning-loop index),
  wires the five Claude Code hooks into `.claude/settings.json` (the two safety backstops +
  three-loop sensors), and installs the commit-message naming guard shim at
  `.git/hooks/commit-msg`.

It ends with a report: detected languages + shape, the resolved repo manifest, every wire
action, activated packs, and — mandatory — the **gaps** (a detected language with no active
pack, so partial coverage never looks complete).

> **Existing repo?** The only extra work is harvesting your conventions into `CLAUDE.md` /
> `CONTEXT.md`. `/install` leaves an existing `CLAUDE.md` untouched; if it's still the bare
> template, ask the `lead-agent`: *"Read this codebase and draft CLAUDE.md and CONTEXT.md
> from templates/ — use what's actually here."* Review the drafts (only you hold the domain
> *why*, habit #6), then commit. Your existing rules win on conflicts.

---

## What `/install` generates (the config you own)

| File | Role |
|---|---|
| `.claude/workflows/repos.config.js` | the **repo universe** — `{name, path, class, language}` per repo. Workflows resolve through this; nothing inlines a repo list. See `repos.config.example.js`. |
| `.claude/skills-config.json` | the **verify map** (`verify.defaults.<language>.{verify,lint,test}` + per-repo `verify.byRepo` overrides) **and** the issue-tracker block (`github`/`local`/`none` + label vocabulary). See `skills-config.{example,schema}.json`. |
| `.claude/hooks/hook-globs.env` | project-specific hook values (e.g. `PROTECTED_BRANCH`, test-secret allowlist). |
| `packs/<lang>/` activation | stack-specific scaffolding (commands, hooks, verify defaults) copied/flagged on when that language is detected. |
| `.claude/memory/MEMORY.md` | the **learning-loop index** (seeded empty; the learning loop fills it over time). The `.gitignore` stance is also set: team memories tracked, `*.local.md` personal memories gitignored. |
| `.claude/settings.json` hook entries | five Claude Code hooks wired: the two safety backstops (PreToolUse) + three-loop sensors (SessionStart + Stop). The commit-message naming guard is wired via a `.git/hooks/commit-msg` shim (tracked script; separate mechanism). |

The **verify map is why one crew serves any stack**: an agent calls "the verify command for
this repo" and it resolves `byRepo.overrides → defaults[language] → built-in fallback` — so
`/verify-service`, `slice-ship`, and `cross-repo-migration` work unchanged on a Java service
and a Python service.

---

## Manual fallback (what `/install` does under the hood)

If you'd rather wire it by hand (or `/install` can't classify an unusual layout), do the
steps the installer would, in order:

```bash
# 1. Copy the crew in (as above).
# 2. Author .claude/workflows/repos.config.js from repos.config.example.js — list your repos.
# 3. Author .claude/skills-config.json from skills-config.example.json — set the verify map
#    for each language you use + the issueTracker block. Validate against the schema.
# 4. Copy packs/<your-lang>/ commands+hooks into .claude/ if a pack exists for your stack.
# 5. Instantiate CLAUDE.md + CONTEXT.md from templates/ and fill them in.
# 6. Wire the hooks in .claude/settings.json (see "The safety hooks" below).
```

This is the same end state `/install` produces — the installer just does it idempotently and
detects the stack for you.

---

## Filling in the context files

These two files are the **context contract** (see [THE-METHOD.md](THE-METHOD.md)). They
are what keeps agents from drifting on a large codebase. Treat them as load-bearing.

**`CLAUDE.md` — the rules.** Answer:
- What is this project, in two sentences?
- What's the stack, and what are the non-negotiable conventions?
- What are the auto-fail conditions (the things that must never ship)?
- Where do the deeper docs live (link, don't duplicate)?
- A pointer to `docs/AGENT-WORKFLOW.md` as the binding workflow.

**`CONTEXT.md` — the orientation.** Answer:
- What does this repo own? (its data model, endpoints, contracts)
- What's the one file to read first?
- A domain glossary — the project's vocabulary, so agents don't invent synonyms.

**The freshness rule is the whole point:** any change that alters contracts, endpoints,
or data shape updates `CONTEXT.md` in the *same* change. The crew's `critic`/`auditor`
treat stale orientation as a review-blocker. This is what a vector index can never do.

---

## The hooks

`/install` wires all six core hooks for you. If you are going manual, add them to
`.claude/settings.json` yourself. There are two families:

**Safety backstop (PreToolUse — fail safe / over-block):**

- **`block-dangerous-git.sh`** (on `Bash`) — blocks genuinely irreversible operations
  (force-push to the protected branch, `reset --hard`, `clean -f`, `rm -rf`, destructive DB
  ops) *regardless of your permission mode*, while allowing normal feature-branch flow. Also
  warns on parallel-session collision. Set `PROTECTED_BRANCH` in `hook-globs.env` if your
  main branch is not `main`/`master`.
- **`block-secrets-in-writes.sh`** (on `Write|Edit|MultiEdit|NotebookEdit`) — scans content
  about to be written for credential shapes (`secret-patterns.sh`) and blocks the write
  before a credential ever lands in the tree. A test-secret allowlist is configurable in
  `hook-globs.env`.

**Three-loop sensors (SessionStart / Stop — fail silent / nudge-only):**

- **`onboard.sh`** (SessionStart) — Loop 1 sensor: detects un-installed or un-oriented
  repos and surfaces the right install/orient offer per folder shape. Goes silent once
  installed and `CONTEXT.md` is authored.
- **`check-freshness.sh`** (SessionStart) — Loop 3 sensor: counts code-bearing commits
  since `CONTEXT.md`'s last commit. Over `STALE_THRESHOLD` (default 15) → nudges toward
  `drift-audit`.
- **`suggest-memory.sh`** (Stop) — Loop 2 sensor: reads the last user message for
  durable-lesson phrases; emits a one-line nudge toward `/remember`. Never writes, never
  blocks.

**Naming guard (git hook):**

- **`check-commit-msg.sh`** (git `commit-msg` hook) — rejects commit messages naming a
  model vendor or tier, when `attributionTrailer` is configured in `skills-config.json`
  (default OFF). `/install` wires the shim at `.git/hooks/commit-msg` automatically.

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
          { "type": "command", "command": ".claude/hooks/onboard.sh" },
          { "type": "command", "command": ".claude/hooks/check-freshness.sh" }
      ] }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/block-dangerous-git.sh" }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/block-secrets-in-writes.sh" }
        ]
      }
    ],
    "Stop": [
      { "hooks": [
          { "type": "command", "command": ".claude/hooks/suggest-memory.sh" }
      ] }
    ]
  }
}
```

On Windows, run them via Git Bash or WSL (they are bash scripts). Language-specific hooks
(e.g. the Python venv rule guard — one `.venv` at the repo root, every Python command runs
inside it) live in their pack and are wired only when that pack is activated.

See [`.claude/hooks/README.md`](../.claude/hooks/README.md) for the full contract of each
hook, the secret-patterns single-source design, and the allow/block details.

---

## Verify the install

Run `/status` first:

```
/status
```

This gives you the cockpit view: install state, orientation, learning state, doc freshness,
safety-hook wiring, and open work — all in one screen. Every `⚠️` line names the command
that closes the gap. If everything is green, the install is complete.

Then try a small scoped task — ask the `lead-agent`: *"Add a health-check endpoint, follow
the workflow spec."* You should see it:
1. Read `CLAUDE.md` / `CONTEXT.md` / `docs/AGENT-WORKFLOW.md`,
2. Open a `feat/` branch via `/new-slice-branch`,
3. Dispatch a `dev-lead`,
4. Run the quality pipeline (critic → fixer → auditor),
5. Stop and ask **you** to merge.

If the crew tries to merge to the main branch itself, your `CLAUDE.md` is not emphasizing
the human-merge gate hard enough — strengthen it. That gate is the one rule that never bends.

---

## Renaming the crew (optional)

The agent/skill names (`lead-agent`, `dev-lead`, …) are a starting point. If you want
your own vocabulary, rename the files in `.claude/agents/` and `.claude/skills/` and
update the cross-references. Keep the *roles* and the *routing* — those are the method;
the names are paint.

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
