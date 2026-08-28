# ADR-0001 — Consuming projects self-configure; the framework hardcodes nothing project-specific

**Status:** Accepted
**Date:** 2026-06-04
**Deciders:** framework maintainers
**Supersedes:** the manual `cp`-based install described in earlier `docs/INSTALL.md` (now the fallback path)

---

## Context

crew-for-claude is a **portable agent framework** meant to drop into *any* codebase — a Java
monorepo, a Python multi-repo, a polyglot multi-language workspace, a single repo, however
the consumer's project is shaped. Its capability tiers (agents, skills, commands, hooks,
workflows) only deliver value if they can operate against a project the framework's authors
have never seen.

Two forces collide:

1. **The capabilities need to know the project** — the multi-repo workflows need the repo
   universe; the verify/quality steps need the per-language build/test commands; the hooks
   need the source/test path globs; the file-first-bug command needs the issue tracker. A
   framework that hardcodes these is married to one project and one stack.

2. **A generic product cannot hardcode any of them** — there is no canonical repo list, no
   single verify command, no one language. Inlining a fixed repo array or a `verify.sh`
   literal (as the framework's origin project did, with a 26-repo manifest copied into
   every workflow) is exactly the coupling that makes a framework non-portable. It also
   drifts: copies of a hardcoded list diverge silently.

The framework must therefore push **all project-specific knowledge out of its own assets and
into per-project configuration that each consuming project owns** — so a service/project/
module configures itself, and the framework neither knows nor cares about the specifics.

## Decision

**Every project that adopts this framework self-configures. The framework's shipped assets
contain zero project-specific or stack-specific facts.** Concretely:

1. **An installer wires the project, not the maintainer.** The `/install` skill
   (`.claude/skills/install/`) runs a **Detect → Scope → Wire** flow against the target:
   - **Detect** — classify the project by file markers (`pom.xml`/`build.gradle` → java,
     `package.json` + lockfile → node, `pyproject.toml`/`requirements.txt` → python,
     `go.mod` → go, `*.tf` → infra, …), multi-hit for polyglot, and infer shape
     (monorepo / multi-repo / single).
   - **Scope** — resolve the repo/module universe (v1: configure-in-place over repos that
     already exist on disk; clone-into-workspace and new-workspace are documented
     fast-follows).
   - **Wire** — generate the project's config (`repos.config`, `.claude/skills-config.json`,
     hook globs), idempotently, **never clobbering user-authored files**.

2. **The repo universe is resolved, never inlined.** Per `.claude/workflows/RESOLVER.md`,
   every multi-repo workflow opens with a `phase('Resolve')` that spawns a discovery agent
   returning the classified repo manifest, resolved in precedence order:
   **`args` → `repos.config` → `.gitmodules` → marker-based auto-discovery.** No workflow
   contains a hardcoded repo list. (This replaces the origin project's copied-into-every-
   workflow manifest and the "keep the copies identical" discipline it required — the
   coupling is gone by construction, not by vigilance.)

3. **Quality commands are configured per language × class, not hardcoded.** The verify /
   lint / test commands live in `.claude/skills-config.json` as a 2-D map:
   `verify.defaults.<language>.{verify,lint,test}` with per-repo overrides
   (`verify.byRepo.<name>.overrides`). Resolution order is
   **byRepo.overrides → defaults[language] → built-in fallback.** Agents call "the verify
   command for this repo," which resolves through the config — so the same `dev-lead`,
   `slice-ship`, and `cross-repo-migration` work unchanged on a Java service and a Python
   service.

4. **Stack-specific scaffolding lives in activatable packs, not in core.** Per
   `packs/PACK-SPEC.md`, a language pack (`packs/<lang>/`) declares its markers, commands,
   hooks, and verify defaults in `pack.json`. `/install` activates a pack only when it
   detects that language. Core ships one real pack (`packs/python-fastapi/`) and spec-only
   stubs for java/node/go; a detected language with no pack is recorded as a gap, never
   silently dropped. Core hooks are language-agnostic (git-safety, secret scanning);
   language-specific enforcement (e.g. venv structure) is pack-scoped.

**The net effect: a service/project picks its own configuration independently — its repo
membership, its verify commands, its language pack, its issue tracker — and the framework
does not need to know, change, or worry about any of it.** Adding a new project, a new
language, or a new repo is a config/pack change in the consuming project (or a new pack),
never an edit to a shipped framework asset.

## Alternatives considered

- **Inline a manifest + a fixed toolchain (the origin project's approach).** Simple, works
  for one project. Rejected: non-portable by definition, and the copied-manifest pattern
  drifts (the origin project repeatedly hit "a repo was silently omitted from a sweep").
- **Require the consumer to hand-edit every workflow/command for their stack.** Maximally
  flexible, zero magic. Rejected: defeats "drop in and go"; every consumer re-does the same
  genericization the framework should own once.
- **A single flat verify command (one `verify.sh` the consumer writes).** Simpler than the
  2-D map. Rejected: a polyglot or multi-class workspace genuinely needs different commands
  per language and per repo-class; a flat command forces the consumer to re-implement that
  dispatch themselves.
- **Auto-discovery only, no config file.** Zero setup. Rejected as the *sole* mechanism:
  heuristics can't always classify correctly or pin a repo set; the config file lets a
  consumer be explicit. Auto-discovery is kept as the **fallback** so day-one works without
  a config, with config + args overriding.

## Consequences

**Positive**
- The framework is genuinely project- and language-agnostic; the same assets serve any
  consumer.
- Per-project knowledge lives in one obvious place each consumer owns
  (`repos.config` + `skills-config.json` + active packs) — easy to read, diff, and audit.
- New language support is additive (a new pack), isolated (activating one pack never
  touches another), and doesn't require touching core.
- The drift class that plagued the origin project (copied repo lists, hardcoded toolchains)
  is structurally eliminated — there is nothing to keep in sync.

**Negative / costs**
- More moving parts than a hardcoded setup: an installer, a resolver contract, a config
  schema, and a pack spec must all exist and stay coherent.
- The resolver indirection means a workflow can't "just read the repo list" — it must spawn
  a discovery phase (a deliberate constraint of the workflow runtime, documented in
  RESOLVER.md).
- Auto-discovery heuristics can misclassify an unusual layout; the config file is the
  escape hatch, but the consumer must know to use it.

**Follow-ups**
- `/install` v1 is configure-in-place only; **clone-into-workspace** and **new-workspace**
  scoping modes are a planned fast-follow.
- Only `python-fastapi` ships as a real pack; **java / node / go** packs are spec-only
  (see `packs/PACK-SPEC.md`) until authored.

## References

- `.claude/skills/install/SKILL.md` (+ `reference/{detect,scope,wire}.md`) — the installer
- `.claude/workflows/RESOLVER.md` — the repo-resolution contract
- `.claude/skills-config.example.json` + `.claude/skills-config.schema.json` — the verify map
- `packs/PACK-SPEC.md` — the pack contract

---

## Migration status & remaining work (resume point for a fresh session)

This decision was implemented by porting the framework's capability tiers in from the origin
project. The work was sliced; **Slices 1–2 are DONE on disk, Slice 3 + the audit REMAIN.** A
fresh session in this repo should pick up from here — the framework can finish its own port
using its own tiers (the agents, `/create-workflow`, the workflows, and `/install` all exist).

### DONE (verified on disk)
- **Slice 1 — keystone:** the installer (`/install`), the resolver contract
  (`repos.config.example.js` + `RESOLVER.md`), the 2-D verify map
  (`skills-config.{example,schema}.json`), the `packs/` model (`PACK-SPEC.md` + real
  `python-fastapi` pack + java/node/go stubs), and all core hooks (`secret-patterns.sh`,
  `block-secrets-in-writes.sh`, the collision-guard appended to `block-dangerous-git.sh`,
  the venv hook scoped into the python pack). All shell `bash -n` clean, JSON valid.
- **Slice 2 — capabilities:** 6 genericized workflows (`build-status-audit`,
  `cross-repo-migration`, `slice-ship`, `hygiene-fix-sweep` (parameterized),
  `submodule-sync-sweep` (renamed from pointer-bump-sweep), `drift-audit` (the
  origin-specific 4th "distribution" axis dropped)) — every one resolver-driven with NO
  inlined repo array and NO hardcoded verify toolchain; the `create-workflow` skill; 4 core
  commands (`verify-service`, `new-slice-branch`, `bump-pointer`, `file-bug`); and the
  8 python-FastAPI pack commands. All workflows `node --check` clean; `meta.name` == slug.
- **This ADR** (the self-config decision) + the `docs/adr/` practice it establishes.

Verified gates so far: zero origin-project proper nouns across the shipped surface **except**
the one stray file below; no absolute paths; no inlined repo arrays; no hardcoded verify
toolchains in core.

### DONE — Slice 3 (docs + stitch + cleanup) — 2026-06-04
1. **Docs** — the new tiers are now visible:
   - root `README.md`: capability list updated (commands / workflows / `create-workflow` /
     `/install` / `packs/`), the **5-layer model** table added (command → skill → workflow →
     lead → orchestrator, cheap→expensive), Quick-start re-pointed at `/install`, and a
     self-config callout linking this ADR.
   - `docs/INSTALL.md`: rewritten around "copy `.claude/` in → run `/install`" (Detect →
     Scope → Wire); the manual `cp` recipe kept as the under-the-hood fallback; the verify
     map + `repos.config.js` + pack activation + the **two** core hooks documented.
   - `docs/THE-METHOD.md`: 5-layer-model section added with the workflow(breadth)-vs-
     lead(depth)-vs-command(cheap-repeat) distinction made load-bearing.
   - `docs/AGENT-WORKFLOW.md`: a Workflows section (resolver + verify-map + DRY-RUN, orchestrator-
     only) + command pointers in the cheat-sheet.
2. **Stitched the concepts into the agent files:**
   - `lead-agent.md`: added `Workflow` to its tools + a "Workflows: breadth, when leads are
     depth" section (library, DRY-RUN, `/create-workflow`).
   - `dev-lead.md`: added a Commands section (`/new-slice-branch`, `/verify-service`,
     `/file-bug`, `/bump-pointer`) + an explicit "you don't hold `Workflow` — report breadth up".
   - `architect.md`: brief format gained a **Workflow** routing line; prose tells it to
     recommend a workflow when a slice is the same change across many repos.
3. **Cleanup (closed the LAST origin-project leak):**
   - **Deleted `.claude/agents/pa-agent.md`** — the stray duplicate carrying the only live
     origin-project proper nouns; nothing unique lost (its workflow-ownership concept now
     lives in `lead-agent.md`).
   - **Rename-consistency sweep:** the 3 stale `pa-agent` refs in
     `.claude/skills/context-handoff/{SKILL,FILE-FORMAT}.md` → `lead-agent`. No `_repos.js` /
     `verify-service.ps1` refs remain. The `submodule-sync-sweep` README "Rename note" is a
     deliberate migration breadcrumb, not a dangling ref, and is kept.

### Audit gates — RUN THIS SESSION, all green
- `Run a project-specific-terms sweep (business names, client names, personal handles) before publishing`
  → only this ADR (which *documents* the grep command itself); `.claude`/`packs` surface clean.
- all 6 `.claude/workflows/*.js` pass `node --check`; every `meta.name` == filename slug.
- no workflow inlines a repo array; no core workflow hardcodes `pytest`/`npm`/`mvn`/`gradle`.
- `skills-config.{example,schema}.json` + `settings.json` parse; all 3 core hooks `bash -n` clean.
- every file referenced by the edited docs exists (link-target sweep passed).

### INDEPENDENT AUDIT — PASSED (2026-06-04)
A 6-dimension independent multi-agent audit (fresh `auditor` agents, not the author; each
re-ran the actual checks — node --check, jsonschema validation, live hook exit codes —
rather than re-reading the diff) returned **all 6 dimensions PASS, zero blockers/majors/
minors.** Dimensions: origin-leak+abs-paths, workflows, packs+core-hooks+config, the Python
venv rule, docs+agent-stitch, /install genericity against java/node fixtures (incl. the
cross-check that the python venv hook is pack-scoped and never wired for java/node).

A FIRST audit pass had REJECTED the build (1 blocker + 3 majors + 4 minors) — all 8 were
fixed and re-verified by the second pass:
- venv hook rewritten **segment-aware** (split on `&& || ; | &`, judge each segment) — fixed
  the false-allow blocker (`pip install x # python -m venv .venv` no longer slips through),
  the false-block of the canonical create+activate+install one-liner, and the raw-fallback
  fail-open (now over-blocks on a python token when no JSON parser is present).
- `skills-config.example.json` now validates against its schema (`$comment` allowed on the
  two value-constrained maps).
- `alembic downgrade base` moved OUT of the core git guard into a new pack hook
  `packs/python-fastapi/hooks/block-destructive-migrations.sh` (core is language-neutral).
- secret allowlist switched to **exact-span match** (`grep -vxE`) so a real secret embedding
  a fixture token no longer slips; also fixed a Windows-backslash basename bug and exempted
  the `secret-patterns.sh` SSOT from the write hook (it must contain example shapes).
- stale `/grill-with-docs` → `/interrogate-plan`; "venv-structure guard" → full venv-rule wording.

5 cosmetic nits remain (all flagged "does not block ship"): node pack marker AND-lockfile
note, scope.md java class example, PROTECTED_BRANCH default vs this repo's `master` branch.
The first two nits (hooks-README second-hook mention, README 7-lead diagram) were fixed.

### REMAINING
- **Commit + push** (normal PR flow). Until merged this remains **uncommitted on disk**.
