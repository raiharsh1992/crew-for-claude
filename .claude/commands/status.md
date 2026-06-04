# Crew Status (the cockpit)

Produce a single-screen health view of this workspace — what's wired, what the crew has
learned, and where the docs have drifted from the code. Scope (optional): $ARGUMENTS
(a repo name to focus on; empty = the whole workspace).

This is the **cockpit** for the three-loop system (see
[docs/adr/0002-the-three-loops-auto-growing-workspace.md](../../docs/adr/0002-the-three-loops-auto-growing-workspace.md)).
It is **read-only** — it reports state and points at the actuator for each gap; it changes
nothing.

## Assemble the view (cheap reads only — no heavy scans)

Gather these and render the compact dashboard below. Each line is a one-glance signal with
the next action if it's not green.

1. **Install state** — does `.claude/skills-config.json` exist? If not → not installed;
   the next action is `/install --dry-run`. If yes, read it for the repo manifest, the
   active packs, and the issue tracker.

2. **Orientation state** — for each repo in the manifest (or the root for a single repo):
   does `CONTEXT.md` exist and is it authored (not the untouched template — check it no
   longer contains the `<PROJECT NAME>` / `<PROJECT / MODULE NAME>` placeholder)? Un-oriented
   repos' next action is `/orient`.

3. **Learning state (Loop 2)** — read `.claude/memory/MEMORY.md` and count the index lines
   (memories captured), grouped by section (user / feedback / project / reference). Show the
   count and the 2–3 most recent or most load-bearing hooks. Zero memories on a repo with
   real history is itself a signal — the crew hasn't been taught anything yet.

4. **Freshness state (Loop 3)** — for each oriented repo, cheaply estimate doc staleness the
   same way the freshness sensor does: count code commits since `CONTEXT.md`'s last commit
   that didn't also touch it (`git log <last-context-commit>..HEAD -- <code globs>` minus the
   doc-fresh commits). Flag repos over the threshold; their next action is `drift-audit`.

5. **Safety backstop state** — confirm the core hooks are wired in `.claude/settings.json`
   (`block-dangerous-git.sh`, `block-secrets-in-writes.sh`) and that `PROTECTED_BRANCH`
   resolves to this repo's actual default branch (the git-guard auto-detects from
   `origin/HEAD`; confirm it isn't silently pointing at a non-existent branch).

6. **Open work** — if the issue tracker is `local`, count open issue files under its
   configured path; if `github`, note that `gh issue list` would show them (don't call it
   unless asked). Keep this cheap.

## Render it like this

```
╔═══════════════════════════════════════════════════════════════╗
║  CREW STATUS — <workspace name>                <date>          ║
╠═══════════════════════════════════════════════════════════════╣
║  Install      ✅ wired (N repos, packs: …)   | ⚠️ not installed ║
║  Orientation  ✅ 3/3 repos oriented          | ⚠️ 1 missing     ║
║  Learning     📚 7 memories (2 feedback, 3 project, …)         ║
║  Freshness    ✅ docs current                | ⚠️ svc-x ~18 behind║
║  Safety       ✅ git-guard + secret-scan wired (branch: master)║
║  Open work    🐛 4 open issues                                 ║
╚═══════════════════════════════════════════════════════════════╝

Next actions:
  • <repo> not oriented → /orient
  • <repo> docs ~N commits behind → drift-audit
  • (only list real gaps; if all green, say "all green — nothing needed")
```

Use ✅ / ⚠️ / 🐛 / 📚 to make state glanceable. Keep it to one screen. Adapt rows to what's
actually present (a single-repo workspace doesn't need per-repo breakdowns).

## Rules

- **Read-only.** Never write, never run a heavy scan, never call the network unless the user
  asks. The point is a *fast* glance, not an audit (`drift-audit` is the audit).
- **Every ⚠️ line names its actuator** — the one command that closes that gap. The cockpit's
  value is turning state into the next action.
- If nothing is wired yet, collapse to a single line: "Crew not installed here — run
  `/install --dry-run` to see the plan," and stop.
