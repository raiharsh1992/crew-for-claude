# New Slice Branch

Open a feature branch for a slice and scaffold its design doc: $ARGUMENTS

Per `docs/AGENT-WORKFLOW.md` — the dev-lead owns a `feat/<slice-name>` branch end-to-end.
`$ARGUMENTS` = the slice name (e.g. `billing-tier-2`).

## Steps

```bash
# From the target repo (not a superproject root)
git fetch origin
git checkout <default-branch>          # usually main or master
git pull --ff-only origin <default-branch>
git checkout -b feat/$ARGUMENTS
# Do NOT push the empty branch — push only when there's real work.
```

Branch name examples: `feat/billing-tier-2` · `feat/auth-jwt-extensions` ·
`feat/catalog-wave-2`.

## Scaffold the design doc (if one doesn't exist)

Create `BRIEF-$ARGUMENTS.md` / `DESIGN-$ARGUMENTS.md` in the repo if the slice needs a
design pass. Minimal DESIGN stub:

```markdown
# DESIGN-$ARGUMENTS

## Scope
- in: <what this slice delivers>
- out: <what's explicitly deferred to a follow-up slice>

## Approach
- <architecture / file layout / key interfaces — 3–5 bullets>

## Project-rule touchpoints (from your CLAUDE.md)
- <data-isolation rule>: <where it applies>
- <auth / write-protection rule>: <which operations>
- <audit / state-change rule>: <which changes>
- migrations: <which tables; if any>

## Cross-service impact
- <events emitted/consumed, shared-schema changes, token claims> or "None"

## Implementation checklist (commit groups)
- [ ] <commit group 1 — ~200–500 LOC>
- [ ] <commit group 2>

## Gate tier
- FULL | LEAN — <one-line reason; any doubt = FULL>
```

## Then

1. **Read the reading list** (AGENT-WORKFLOW.md): this doc → BRIEF → DESIGN → the repo's
   CLAUDE.md → CONTEXT.md → existing code.
2. **Classify the gate tier** (FULL vs LEAN) — default FULL; any change touching the
   high-risk surfaces your CLAUDE.md names (auth, data isolation, audit, money,
   cross-service, new public endpoint, schema migration) = FULL.
3. Decide solo-vs-delegate per commit group; build; run the quality pipeline; prove
   `/verify-service <repo>` green; open the PR.

## Note

For taking a clear-scope slice through the FULL pipeline deterministically (impl → critic →
fixer → auditor → verify → PR, with the verify gate un-fakeable), use the `slice-ship`
WORKFLOW instead of driving it by hand.
