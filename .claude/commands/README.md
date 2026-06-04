# Commands layer

Project slash-commands. A command is a **prompt template** — a `.md` whose body is injected
as instructions when you type `/<name>`, with `$ARGUMENTS` substituted. No agents, no logic
— the cheapest reusable action (vs skills = conditional knowledge, workflows = multi-agent
orchestration).

## Single source of truth (root only)

These **core** commands live at the workspace root (`.claude/commands/`) and are inherited
by every sub-repo via the directory-tree config merge — exactly like `.claude/agents/` and
`.claude/skills/`. **There is ONE copy of each command.** Editing the root copy updates it
everywhere; never re-introduce per-repo copies (they drift and breed bugs — that's the
exact failure this layout kills).

**Consequence:** a repo opened *standalone* (outside the workspace tree) won't see these
commands — same as it wouldn't see the root agents/skills. The crew workflow always opens
at the workspace root, so the merge always applies.

## Core vs pack commands (the split)

| | Core (here, `.claude/commands/`) | Pack (e.g. `packs/python-fastapi/commands/`) |
|---|---|---|
| **Scope** | Stack-agnostic choreography + the resolved verify gate | Stack-SPECIFIC scaffolding (a model, a router, a migration, …) |
| **Genericity** | No toolchain, no framework names — everything is resolved from config | Framework patterns ARE the point (the pack is the sanctioned home for stack specifics) |
| **Activation** | Always present | Copied/activated by `/install` when it detects that stack |

When `/install` activates a pack, that pack's commands become available alongside these
core ones. The pack commands carry a banner saying they're an example for their stack —
adapt or replace them for your project.

## The core commands

| Command | Does |
|---|---|
| `/verify-service <repo>` | The pre-PR CI-equivalence proof. Resolves the repo's verify command from `skills-config.json` (language×class map) — no hardcoded toolchain. |
| `/new-slice-branch <slice>` | Open `feat/<slice>` off the default branch + scaffold the DESIGN doc + gate-tier reminder (per `docs/AGENT-WORKFLOW.md`). |
| `/bump-pointer <submodule…>` | Post-merge parent submodule pointer bump, stage-by-explicit-name (superproject workspaces only). |
| `/file-bug <desc>` | File an issue on the configured tracker per the FILE-FIRST rule. Reads `issueTracker` (github/local/none) + label vocabulary from `skills-config.json`. |
| `/status [repo]` | The **cockpit**: a one-screen, read-only health view — install state, orientation, what the crew has learned (Loop 2 memory), doc freshness (Loop 3), safety-hook wiring, open work. Every ⚠️ line names the one command that closes the gap. |

## Relationship to workflows

Some commands have a fan-out WORKFLOW sibling for the bulk case:
- `/bump-pointer` (one/few) ↔ `submodule-sync-sweep` workflow (all stale, post-wave)
- `/new-slice-branch` + manual pipeline ↔ `slice-ship` workflow (full pipeline, un-fakeable verify)

Use the **command** for a single interactive action; use the **workflow** for fan-out
across many repos/items.

## Maintaining

- Edit the ONE root copy. Never re-introduce per-repo copies.
- Keep core commands free of stack/toolchain specifics — those belong in a pack. If a
  command would name `pytest`/`npm`/`mvn`, it's either pack material or it should resolve
  from the verify map.
- New repos inherit these automatically — nothing to copy on clone.
