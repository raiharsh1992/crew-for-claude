# Verify Service (CI-equivalence pre-flight)

Run the local CI-equivalence proof for a repo before opening a PR: $ARGUMENTS

This is the MANDATORY pre-PR gate from `docs/AGENT-WORKFLOW.md` — it mirrors the repo's CI
exactly so you never burn CI rounds on "passes-locally-but-not-in-CI".

`$ARGUMENTS` = the repo name (e.g. `billing-service`).

## Run it

The verify command is NOT hardcoded — it is **resolved from
`.claude/skills-config.json`** for this repo's language×class. Resolve it in this order and
run the result from the repo root:

1. `verify.byRepo["$ARGUMENTS"].overrides.verify` — a per-repo override, if present.
2. else `verify.defaults[<language>].verify` — the language default (the `<language>` is
   `verify.byRepo["$ARGUMENTS"].language`, or inferred from file markers).
3. else the built-in fallback for that language (e.g. Python: lint + type-check +
   `pytest --cov`; Node: lint + build + test; infra: validate + fmt-check).

```bash
# From the repo root. Example resolved Python chain (yours comes from the config map):
#   <lint>  &&  <type-check>  &&  <test-with-coverage>
```

## What CI-equivalence means

The verify command should run the SAME stages your CI runs, in the same order, against the
same fixtures — so a green local run predicts a green CI run. For a typical backend service
that is: install deps in a clean environment, format/lint check, type-check (blocking),
apply migrations against a real local DB, run tests with the coverage floor.

## When to run it

- **Once, when the slice is done** — not per commit (pre-commit covers per-commit).
- **In PARALLEL with the critic/auditor pass** — they're independent; don't serialize.
- Open the PR ONLY when this reports GREEN.

## If it fails

Investigate the ROOT CAUSE (don't just retry). Common local≠CI gaps:
- the type-checker targets a pinned interpreter version — a different local version can
  hide/expose errors
- CI uses fresh-environment install + CI DB credentials — match them
- lint runs on the test sources too, not just the app sources

Fix on the feature branch, re-run, then open the PR.

## Notes

- The verify map is language- and class-aware: a SERVICE runs the full chain, a LIBRARY
  typically lint+test, a UI lint+build+test, INFRA validate+fmt-check. The config map
  encodes this — you don't branch on it here.
- This command does NOT push or open a PR — it only proves green. Opening the PR is a
  separate, deliberate step.
