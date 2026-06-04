# The Three Loops — Auto-Learning, Auto-Growing Workspace

This is the marquee feature of this release. Read the full rationale and design decisions in
[docs/adr/0002-the-three-loops-auto-growing-workspace.md](../adr/0002-the-three-loops-auto-growing-workspace.md).

---

## The problem: forward flow only

The framework's core mechanisms — the context contract, tiered routing, the quality pipeline,
the human merge gate — are all **forward flow**: a human invokes a skill, agents produce
output, the human merges. Every mechanism is *pull*. Nothing happens unless someone runs it.

The result: a correction made in one session dies with the context window. A fresh agent
re-earns every lesson. Documentation drifts silently until someone manually runs an audit.
And a developer who opens the framework in a repo for the first time sees a blank workspace
that requires significant manual setup before any agent can be useful.

**The three loops add back-flow.** The workspace now orients itself, gets smarter with use,
and stays honest with the code — without being told to.

---

## The sensor/actuator pattern

Every loop is built on the same pattern:

```
  SENSOR                        ACTUATOR
  (notices the moment)          (acts — proposes, then writes)
  ─────────────────────         ──────────────────────────────
  cheap deterministic hook  →   skill the user can see and approve
  no model cost                 proposes every tracked-file edit
  fires at session events       never writes silently
  never writes                  never fires unprompted on tracked files
  never blocks                  sends a one-line receipt on write
  fails silent                  fails safe
```

**The trust invariant is "propose, never silently auto-write."** A fact going into a
version-controlled file (`CLAUDE.md`, `CONTEXT.md`, an ADR) changes how every future agent
behaves — that is exactly the kind of edit a human must see and approve. The sensor notices;
the actuator drafts, shows, and writes only on confirmation.

Low-stakes agent memory (personal preferences, working style) may be written directly — but
always announced in a one-line receipt, never silently.

---

## Loop 1 — Onboarding

**Goal:** from the moment Claude Code opens in any folder, the workspace reaches "alive and
oriented" in minutes — regardless of whether the folder is empty, an existing project, or a
pulled multi-repo workspace.

### Sensor: `onboard.sh` (SessionStart)

A pure-bash hook that fires at every session start. It checks whether the crew is installed
(`.claude/skills-config.json` exists) and whether `CONTEXT.md` is authored (not the
untouched template). When the crew is not yet installed, it detects the folder shape and
surfaces the one right offer:

| Folder shape | What the sensor offers |
|---|---|
| Empty / new project | Scaffold `CLAUDE.md` + `CONTEXT.md` from templates, then run `/install` |
| Existing single repo | Run `/orient` to generate a real `CONTEXT.md`, then run `/install` |
| Multi-repo workspace | Run `/install --dry-run` to resolve the universe, then `/orient` per repo |

The sensor goes **silent** once the crew is installed AND `CONTEXT.md` is authored. It does
not fire every session — only when something is genuinely missing.

### Actuator: `/orient` + `/install`

`/orient` is the **wow moment**. It reads an existing repo — entry points, data model, public
surface, domain vocabulary, cross-module contracts — and generates a real `CONTEXT.md` from
the actual code. It uses `/survey-code` for unfamiliar or large areas.

Before writing anything, it shows you the full draft (or section headers + key tables for a
large repo) and writes only on confirmation. It never clobbers an authored `CONTEXT.md` —
if one exists and is not the untouched template, it shows what it would add or correct and
lets you merge.

`/install` wires the machinery (see [Getting Started](./getting-started.md) and
[docs/INSTALL.md](../INSTALL.md)).

> **Constraint:** `/install` v1 is configure-in-place only. It works with repos already on
> disk. Clone-into-workspace and new-workspace modes are planned fast-follows.

---

## Loop 2 — Learning

**Goal:** a lesson learned once is never re-explained. A correction, a locked decision, a
preference — any of these should survive the current session and be available to every future
session for free.

### Sensor: `suggest-memory.sh` (Stop)

A Stop hook that reads the last user message from the session transcript after each agent
turn. It matches a precision-tuned set of "durable lesson" phrases:

- `from now on` / `always` / `never`
- `we decided` / `I prefer` / `don't do that again`
- A correction with a pattern ("that was wrong — the right way is...")
- A locked technical decision

When a match fires, the hook emits a **one-line nudge** suggesting `/remember`. It never
writes, never blocks, and fails silent on any parse error (a missed nudge is preferable to a
spurious one). A recursion guard (`stop_hook_active`) prevents it from triggering on its own
output.

### Actuator: `/remember`

`/remember` routes each learnable fact to its proper home:

| Kind | Looks like | Home | In git? |
|---|---|---|---|
| **Rule / constraint** | "Never call the API client directly — always go through the gateway." | `CLAUDE.md` (root or module) | yes |
| **Orientation / fact** | "The billing tables live in `svc-ledger`, not `svc-orders`." | `CONTEXT.md` | yes |
| **Load-bearing decision** | "We chose Postgres LISTEN/NOTIFY over a broker because…" | a new ADR under `docs/adr/` | yes |
| **Preference / working-style** | "I like terse PR descriptions." / "Always show me the diff first." | `.claude/memory/<slug>.md` + index line in `MEMORY.md` | optional |
| **One-off correction** | "That import was wrong." | nowhere (it's already fixed; only persist if it reveals a pattern) | — |

For rules, orientation, and decisions — all version-controlled files — `/remember` drafts the
exact text, shows it with the target location, and writes only on confirmation. For
preferences, it writes directly but announces the save in a one-line receipt.

### The memory store

Team memories live in `.claude/memory/`. Each memory is one file (`<slug>.md`) with
frontmatter (`name`, `description`, `type`). The index is `.claude/memory/MEMORY.md`.

At session start, the framework's `CLAUDE.md` template carries an instruction to read
`MEMORY.md` — this is the mechanism that makes accumulated lessons reach context. The index
holds only one-line pointers; pull the full file for any memory whose hook line is relevant
to the task.

**Sharing stance:** team memories (`.claude/memory/*.md`, not `*.local.md`) are tracked in
git — every team member gets every lesson. Personal preferences (`*.local.md`) are
gitignored.

`/install` seeds an empty `MEMORY.md` and wires the gitignore stance on first install.

---

## Loop 3 — Freshness

**Goal:** the docs never silently drift from the code. The `drift-audit` workflow already
detects doc-vs-code drift but was pull — nobody ran it. Loop 3 makes it automatic.

### Sensor: `check-freshness.sh` (SessionStart)

A SessionStart hook with one cheap heuristic: count code-bearing commits since `CONTEXT.md`'s
last commit that did NOT also touch `CONTEXT.md`. (A commit that updated the doc in the same
change honored the freshness rule and does not count.) When this count exceeds
`STALE_THRESHOLD` (default: 15), the sensor emits a nudge toward `drift-audit`.

The sensor:
- Stays silent on un-installed repos (that's Loop 1's territory) and on repos without an
  authored `CONTEXT.md` (Loop 1 needs to run first).
- Is explicitly a **heuristic** — it may nudge when nothing user-facing changed, or stay
  quiet when one commit changed a lot. It is a tripwire for the real audit, not the audit
  itself.
- Never claims drift as fact — only suggests the audit.

### Actuator: `drift-audit` workflow

`drift-audit` is the honest mirror. It detects three drift types per repo:

- **doc-vs-code** — `CONTEXT.md` freshness vs. the actual code surface.
- **config-vs-baseline** — hygiene gates against the configured baseline.
- **copy-vs-source** — diverged propagated files.

Like all actuators, it proposes `CONTEXT.md` patches before writing. The user reviews and
confirms. The propose-never-auto-write rule holds throughout.

---

## The cockpit: `/status`

`/status` is the read-only health dashboard for all three loops and the rest of the
workspace. It is not a loop — it is the view of all three loops at once.

```
╔═══════════════════════════════════════════════════════════════╗
║  CREW STATUS — my-project               2026-06-04            ║
╠═══════════════════════════════════════════════════════════════╣
║  Install      ✅ wired (2 repos, packs: python-fastapi)       ║
║  Orientation  ⚠️  1/2 repos oriented                          ║
║  Learning     📚 7 memories (2 feedback, 3 project, 2 ref)    ║
║  Freshness    ⚠️  svc-api ~18 commits behind                  ║
║  Safety       ✅ git-guard + secret-scan wired (branch: main) ║
║  Open work    🐛 4 open issues                                 ║
╚═══════════════════════════════════════════════════════════════╝

Next actions:
  • svc-payments not oriented → /orient
  • svc-api docs ~18 commits behind → drift-audit
```

**Every `⚠️` line names the one command that closes the gap.** The cockpit's job is to turn
state into the next action — one glance, no investigation required.

Rules: purely read-only, no heavy scans, no network calls unless asked. The point is a fast
glance; `drift-audit` is the actual audit.

---

## Why the loops compound

Each loop is useful on its own. Together they compound:

1. **Onboarding** means a new session on any repo reaches useful context in minutes, not
   hours. Every future session starts from a real `CONTEXT.md`.
2. **Learning** means corrections and decisions made once are never re-explained. The cost
   of a mistake is paid once; the benefit of the correction is paid forever.
3. **Freshness** means the `CONTEXT.md` that onboarding generates stays honest as the code
   evolves — the two loops reinforce each other.

The payoff scales with use. The longer a project runs with the framework, the more the
workspace reflects hard-won knowledge that would otherwise live only in the team's heads.

---

*Crew for Claude — MIT License — © 2026 Crew for Claude contributors*
