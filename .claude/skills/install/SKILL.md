---
name: install
description: Install (configure-in-place) the crew-for-claude into a repo or workspace already on disk. Detects the language(s) and project shape, resolves the repo universe, and wires up repos.config.js, skills-config.json, hooks, and the context files — idempotently, never clobbering user-authored files. Use when setting up the crew in an existing project, onboarding a new workspace shape (java monorepo / python multi-repo / polyglot), or re-running setup after adding a repo. Supports --dry-run (prints the plan, writes nothing).
---

# Install the crew (configure-in-place)

This skill wires the crew into a project **already on disk**. It runs three phases
— **DETECT → SCOPE → WIRE** — and is safe to re-run: every write is idempotent and
**never clobbers a user-authored file** (a filled `CLAUDE.md`, an edited agent, a
hand-tuned command).

> **v1 scope: configure-in-place ONLY.** This installs the crew into repos that
> are already checked out in the workspace. Two other modes are **documented
> fast-follow, NOT built in v1**:
> - **clone-into-workspace** — clone a named set of remote repos, then configure.
> - **new-workspace** — scaffold a fresh empty workspace and the first repo.
>
> If the user asks for either, say it's a planned fast-follow and offer to
> configure-in-place what's already on disk instead. Do not improvise a clone flow.

## Always start with `--dry-run`

`--dry-run` runs DETECT + SCOPE + computes the full WIRE plan and **prints it
without writing a single file**. It is the auditor's entry point and the safe way
to preview. Run it first, show the plan, then run the real install once the plan
looks right.

```
/install --dry-run        # show the plan, write nothing
/install                  # apply the plan
/install --repos a,b,c    # scope to a named subset (skips full discovery)
```

---

## Phase 1 — DETECT (classify languages + infer shape)

Read-only. Figure out what's here. Full marker table and shape rules:
[reference/detect.md](reference/detect.md). Summary:

1. **Classify by file markers** (a directory containing any marker is a candidate
   repo for that language):
   - `pom.xml` / `build.gradle` / `build.gradle.kts` → **java**
   - `package.json` **+** a lockfile (`pnpm-lock.yaml` / `yarn.lock` /
     `package-lock.json`) → **node**
   - `pyproject.toml` / `setup.cfg` / `requirements.txt` → **python**
   - `go.mod` → **go**
   - `Cargo.toml` → **rust**
   - `*.tf` → **infra**
   - **Multi-hit = polyglot**: a repo (or workspace) matching several markers
     records the **set** of languages, not just the first.

2. **Infer project shape**:
   - **monorepo** — one git root, markers in subdirectories.
   - **multi-repo** — multiple git roots: several `.git` dirs, a `.gitmodules`
     superproject, or sibling repo dirs each with their own `.git`.
   - **single** — one git root, markers at the root.

3. **Record gaps, don't drop them.** A detected language with **no matching pack**
   (only `python-fastapi` is active today; java/node/go are spec-only) is recorded
   as a **gap** and surfaced in the report — never silently omitted. The user
   learns coverage is partial instead of being misled.

Output of this phase: `{ languages[], shape, candidateRepos[], gaps[] }`.

---

## Phase 2 — SCOPE (resolve the repo universe — configure-in-place)

Resolve **which repos** the crew will manage, using the binding precedence in
[../../workflows/RESOLVER.md](../../workflows/RESOLVER.md):

```
args (--repos) → .claude/workflows/repos.config.js → .gitmodules → marker auto-discovery
```

Stop at the first rung that yields a non-empty set (or union rung-2 with rung-4 if
the user wants belt-and-suspenders — default is first-non-empty). For each repo,
carry `{ name, path, class, language }`. Class (SERVICE/LIBRARY/UI/INFRA) is the
generic verify-bucket role; language selects the actual commands. See
[reference/scope.md](reference/scope.md) for the class-inference rules.

**Out of v1 (state explicitly if relevant):** clone-into-workspace and
new-workspace. This phase only resolves repos already present on disk.

Output of this phase: the resolved repo manifest + which precedence rung produced
it.

---

## Phase 3 — WIRE (generate config + hooks + context — idempotent)

Apply (or, under `--dry-run`, print) the plan. **The cardinal rule: never clobber
a user-authored file.** Full idempotency + merge rules:
[reference/wire.md](reference/wire.md). What WIRE does:

1. **`.claude/workflows/repos.config.js`** — generate from the resolved manifest
   (from `repos.config.example.js`'s shape). If it already exists, **merge** new
   repos in and leave existing entries untouched; never overwrite the file
   wholesale.

2. **`.claude/skills-config.json`** — create or extend. Set the issue-tracker
   block (reuse `bootstrap-skills` conventions — default `local`), the `verify`
   2-D map (seed `verify.defaults[<language>]` from each active pack's
   `verifyDefaults`), `verify.byRepo` pins from the manifest, and `packs.<id>`
   activation flags. **Only fill stages/keys the user hasn't set** — never
   overwrite a user value.

3. **`.claude/hooks/hook-globs.env`** — generate the env file the hook scripts can
   source for project-specific values (e.g. `PROTECTED_BRANCH`, extra
   test-secret allowlist entries). Idempotent; preserve user edits.

4. **Activate packs** — for each detected language with an **active** pack: copy
   the pack's hooks into `.claude/hooks/`, add their matcher entries to
   `.claude/settings.json`, copy declared commands into `.claude/commands/`
   (skip-if-exists), and set `packs.<id>: true`. A **spec-only** pack contributes
   only a recorded gap, nothing copied.

5. **Context files** — instantiate `CLAUDE.md` / `CONTEXT.md` from `templates/`
   **only if absent**. If present, **do not overwrite** — report that they exist
   and (if they look like untouched templates) offer to refresh; otherwise leave
   them and prompt the user to harvest their conventions. The instantiated
   `CLAUDE.md` carries the **"at session start, read `.claude/memory/MEMORY.md`"**
   instruction — that line is what makes the learning loop's memory actually reach
   context, so do not strip it.

6. **`.claude/memory/`** — seed `.claude/memory/MEMORY.md` (the learning-loop index)
   from this kit's copy **only if absent**, and ensure the `.gitignore` carries the
   memory sharing stance (`/.claude/memory/*.local.md` ignored; team memories tracked).
   Idempotent; never clobber an existing index.

7. **`.claude/settings.json`** — ensure ALL the core hook matchers are wired, plus any
   activated pack hooks. Idempotent — add only what's missing:
   - **Safety backstop (PreToolUse):** `block-dangerous-git.sh` on `Bash`,
     `block-secrets-in-writes.sh` on `Write|Edit|MultiEdit|NotebookEdit`.
   - **Three-loop sensors:** `onboard.sh` + `check-freshness.sh` on `SessionStart`
     (onboarding + freshness), and `suggest-memory.sh` on `Stop` (learning). These
     are what make the workspace auto-orient and auto-learn — wiring them is part of a
     complete install, not optional (see `docs/adr/0002`).

Under `--dry-run`, print every one of these as a planned action (CREATE / MERGE /
SKIP-EXISTS / ACTIVATE-PACK / GAP) and **write nothing**.

---

## Report

End with: detected languages + shape, the resolved repo manifest (+ precedence
rung used), every WIRE action taken (or planned, under dry-run), activated packs,
and the **gaps** (detected languages with no active pack). The gaps line is
mandatory — never let a partial-coverage install look complete.

## Reuse + relationship to other skills

- Reuses `bootstrap-skills`' `skills-config.json` issue-tracker/labels/docs
  conventions — this skill is the superset that also wires verify/packs/hooks.
- If only the issue-tracker config is needed (no repo/pack wiring), `bootstrap-skills`
  alone still works; `/install` calls the same shape.
- For workspace shapes and resolution details, the binding doc is
  [../../workflows/RESOLVER.md](../../workflows/RESOLVER.md).
