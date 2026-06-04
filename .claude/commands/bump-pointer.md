# Bump Submodule Pointer

Bump the parent superproject's pointer for a submodule after its default branch moved: $ARGUMENTS

This is the post-merge choreography from `docs/AGENT-WORKFLOW.md`. After ANY merge to a
submodule's default branch, the parent superproject's recorded pointer is stale and must be
bumped. (Applies only when your workspace is a git superproject with submodules.)

`$ARGUMENTS` = one or more submodule names (e.g. `billing-service`), or empty to bump every
stale pointer.

## Steps

```bash
# 1. Parent (superproject) repo, fresh branch off the default branch
git fetch origin
git checkout <default-branch>
git pull --ff-only origin <default-branch>
git checkout -b chore/bump-<submodule>-pointer

# 2. For EACH submodule to bump: advance it to its default-branch tip
cd <submodule>
git fetch origin
git checkout <default-branch>
git pull --ff-only origin <default-branch>
cd ..

# 3. Stage ONLY the submodule path(s) BY EXPLICIT NAME (never git add -A — may sweep scratch)
git add <submodule>            # repeat per submodule; the gitlink sha is what changes

# 4. Confirm what changed (should be only gitlink sha bumps)
git diff --cached

# 5. Commit + push + open the parent PR
git commit -m "chore: bump <submodule> pointer — <one-line summary of what merged>"
git push -u origin chore/bump-<submodule>-pointer
# open PR to the parent default branch
```

## Rules

- **Multiple submodule bumps** from the same merge wave can land in ONE parent PR.
- **Stage by explicit name** — never `git add -A`/`git add .` in the parent tree (it may
  contain scratch).
- The parent PR still goes through the normal gate (CI + user merge). No agent merges to
  the parent default branch.

## Quick check: which pointers are stale?

```bash
git submodule status            # '+' prefix = submodule moved ahead of the recorded pointer
```

## Automation note

For bumping MANY stale pointers at once, the `submodule-sync-sweep` WORKFLOW does this as a
fan-out (detect-all-stale → bump → PR). Use this command for a one-or-few bump; use the
workflow for a whole post-wave sweep.
