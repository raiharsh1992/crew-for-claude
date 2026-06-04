# Workflow authoring rules (the non-negotiables)

These are the things that break a workflow or make it unsafe. Every one has bitten in
practice. Read before authoring.

## 1. `meta` must be a PURE LITERAL
The script MUST begin with `export const meta = {…}`, and that object is a pure literal —
**no variables, function calls, spreads, or template interpolation** inside it. Required:
`name`, `description`. Optional: `whenToUse`, `phases`, `model`.
- `meta.name` MUST equal the filename slug (`build-status-audit` ↔ `build-status-audit.js`).
- `phases` titles must match the strings you pass to `phase('…')` in the body.

## 2. It's JavaScript, NOT TypeScript
- No type annotations (`: string[]`), no interfaces, no generics — they fail to parse.
- The body runs in an async context — `await` directly at top level is fine.
- Standard JS built-ins are available **EXCEPT** `Date.now()`, `Math.random()`, and
  argless `new Date()` — they throw (they would break resume). Vary agent prompts/labels
  by index for "randomness"; pass timestamps via `args` and stamp results after the run.
- No filesystem / Node API access from the script itself (the agents it spawns have tools;
  the orchestration script does not).

## 3. Default to `pipeline()`, not a barrier
`parallel()` is a **barrier** — it waits for ALL thunks before returning. Only correct when
stage N genuinely needs the WHOLE prior result set at once (dedup/merge across everything,
early-exit on total count, "compare against the other findings").

`pipeline(items, stage1, stage2, …)` runs each item through all stages independently with
**no barrier between stages** — item A can be in stage 3 while B is still in stage 1.
Wall-clock = slowest single chain, not sum-of-slowest-per-stage. This is the DEFAULT for
multi-stage work.

A middle transform (flatten/map/filter with no cross-item dependency) does NOT justify a
barrier — do it inside a pipeline stage. Smell test: if you wrote
`const a = await parallel(...); const b = transform(a); const c = await parallel(b…)` and
`transform` has no cross-item dependency, rewrite as a pipeline.

## 4. Always use `schema` for structured per-item output
Pass a JSON Schema as `opts.schema` and `agent()` returns the validated object (the agent
is forced to call StructuredOutput; the model retries on mismatch). Without it you get raw
text you must parse. Use `additionalProperties: false` and a tight `required` list.

## 5. `.filter(Boolean)` every parallel/pipeline result
A thunk that throws (or whose agent errors / the user skips mid-run) resolves to `null` —
the call itself never rejects. Always `.filter(Boolean)` before using results.

## 6. Concurrency + total caps
Concurrent `agent()` calls are capped at ~16 per workflow; excess queue. You may still pass
100 items to `parallel()`/`pipeline()` — they all complete, ~16 at a time. Lifetime total
is capped at 1000 (a runaway backstop). Don't design for >1000 agent calls.

## 7. Pick the right `agentType`
- `Explore` — read-only search/audit (fast, reads excerpts, doesn't review deeply). Use it
  for the Resolve discovery agent and all read-only scans.
- `dev-lead` / `fixer` — write code (give them `isolation: 'worktree'` when parallel).
- `critic` / `auditor` — review gates (read-only; no Write tool by design).
- omit → the default workflow subagent.
Match the cheapest capable type. Don't put `dev-lead` on a read-only audit.

## 8. `isolation: 'worktree'` ONLY when agents mutate files in parallel
It's expensive (~200-500ms + disk per agent). Use it for doers that edit/commit across
repos so they don't collide. Don't use it for read-only audits — wasteful.

## 9. Doers default to DRY-RUN
```js
const DRY_RUN = !(args && args.dryRun === false)
```
In dry-run: do the work in worktrees, run the verify, but STOP before push/PR — report the
diff you WOULD open. Only `{ dryRun: false }` arms real pushes/PRs. A first-run bug must not
open a dozen junk PRs.

## 10. Bake the project safety net into every doer prompt
- **No auto-merge to the default branch.** Doers open PRs; the user merges (single human chokepoint).
- **Stage by explicit name, never `git add -A`** (a tree may contain scratch) — say so in the prompt.
- **CONTEXT.md freshness** — if a slice changes tables/endpoints/events/contracts, update
  CONTEXT.md in the same change (binding rule). Tell the dev-lead agent this.
- **Your project's CLAUDE.md rules** — name the specific rules the change must honor (e.g.
  whatever security/data-isolation/audit/logging conventions your project enforces) so the
  spawned agent applies them. Don't hand-wave "follow the rules" — point at CLAUDE.md.
- The PreToolUse hooks + branch protection still apply to every spawned agent — they can't
  force-push the default branch, `rm -rf`, or write a secret. The dry-run default is the
  *additional* author-side guard.

## 11. Repo lists come from the RESOLVER, never hand-typed
A sweeping workflow MUST open with a **Resolve phase** that spawns one discovery agent
returning the classified manifest, per
[`../../workflows/RESOLVER.md`](../../workflows/RESOLVER.md): the agent walks
args.repos → `repos.config.js` → `.gitmodules` → marker auto-discovery and stops at the
first non-empty rung. The orchestration script has **no filesystem access**, so it cannot
read repos.config or .gitmodules itself — the discovery agent is the only correct path.
A hand-typed array reads as "covered everything" when it silently omits any repo added
after it was written. Fan the real work over `manifest.repos`.

## 11a. Verify commands come from the config map, never hardcoded
When a doer *proves* a change (CI-equivalence), the agent running the verify resolves the
command from `.claude/skills-config.json`'s language×class verify map
(`verify.byRepo.<name>.overrides.<stage>` → `verify.defaults[<language>].<stage>` →
built-in fallback). Do NOT bake a concrete toolchain (`pytest`, `npm test`, `mvn`, …) into
the workflow body — that defeats the language-agnostic design and breaks on the next repo
type.

## 12. Validate before declaring done
```bash
node --check .claude/workflows/<name>.js
```
Run it. A syntax error is a silently dead workflow. Then add the README row and confirm
`meta.name` == filename slug.

## 13. Don't auto-run a writing workflow
Launching spawns many agents and burns tokens — explicit user opt-in only. Offer a dry-run;
never fire `{ dryRun: false }` unprompted.
