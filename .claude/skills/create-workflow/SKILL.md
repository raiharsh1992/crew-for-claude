---
name: create-workflow
description: Author a new durable, named multi-agent Workflow and save it to .claude/workflows/ so it can be run by name across sessions and tracked in git. Use when the user wants to "create a workflow", "make a new workflow", "add a workflow", turn a repeated multi-repo/multi-agent chore into a reusable one, or promote a one-off workflow run into the durable library.
---

# Create a Workflow

A **workflow** is a JavaScript orchestration script the **main session** launches via the
`Workflow` tool. It fans work out to many isolated agents deterministically
(`parallel()` / `pipeline()` / loops) and returns one structured result. It is the right
tool for **breadth** (the same thing across many repos / items); the interactive **lead**
flow is the right tool for **depth** (one slice, human-in-loop). Don't build a workflow
for something a single lead does better.

Durable workflows live in **`.claude/workflows/<name>.js`** — named, git-tracked, reusable
across sessions. (A one-off `Workflow({ script: … })` run only persists in the session dir
and is lost when that session is cleaned. This skill produces the durable kind.)

## When a workflow is the right tool

✅ Good fits — **breadth + repetition**:
- The same mechanical change across many repos (bump a dep, add a CI gate, rename an event)
- An audit/report fanned across all repos (build status, hygiene, CONTEXT.md freshness)
- A find → adversarially-verify → synthesize review pass
- A pipeline that grinds through a known work-list unattended

❌ Not a workflow — use a **lead** instead:
- One exploratory slice needing judgment at each step
- Anything where you want to see and react to each intermediate result
- A single-file change

If unsure, ask the user one question: *"is this the-same-thing-across-many, or one-deep-thing?"* Many → workflow. Deep → lead.

## Process

1. **Scope it.** Get from the user (ask only what's missing):
   - The goal in one sentence.
   - Is it **read-only** (audit/report) or a **doer** (writes code / opens PRs)?
   - What does it fan out over — repos? findings? a work-list passed in `args`?
   - What's the per-item output shape (→ becomes a JSON `schema`)?

2. **Pick the shape** (see [PATTERNS.md](PATTERNS.md) for full templates):
   - **fan-out → synthesize** (`parallel` then one synth agent) — audits.
   - **discover → apply** (`parallel` detect, then `parallel` fix) — doer sweeps.
   - **find → verify → synthesize** (`pipeline`) — reviews. **Default to `pipeline()`**, not a barrier, unless a stage genuinely needs ALL prior results at once.

3. **Draft the script.** Start from a PATTERNS.md template. Hard rules in [RULES.md](RULES.md) — read it; the `meta` literal rule and the JS-not-TS limits bite every time.

4. **Resolve repo coverage — NEVER hand-type a repo list.** If the workflow sweeps "every
   repo," it MUST open with a **Resolve phase** that spawns one discovery agent returning
   the classified manifest (per [`../../workflows/RESOLVER.md`](../../workflows/RESOLVER.md):
   args → `repos.config.js` → `.gitmodules` → marker auto-discovery). The orchestration
   script has no filesystem access, so this discovery agent is the only correct way to
   learn the repo universe. A hardcoded array is a real defect — it silently skips repos
   added later.

5. **Resolve verify from the config map — never hardcode a toolchain.** If the workflow
   *proves* a change, the agent running the verify reads `.claude/skills-config.json`'s
   language×class verify map (`verify.byRepo.<name>.overrides` → `verify.defaults[<lang>]`
   → fallback). Don't bake `pytest` / `npm test` / `mvn` into the workflow body.

6. **Doers default to DRY-RUN.** If it writes code, start the body with:
   ```js
   const DRY_RUN = !(args && args.dryRun === false)
   ```
   In dry-run it does the work in worktrees + verifies, but STOPS before push/PR and reports the diff it *would* open. Use `isolation: 'worktree'` on any agent that mutates files in parallel.

7. **Validate before saving as "done".**
   ```bash
   node --check .claude/workflows/<name>.js
   ```
   A syntax error = a dead workflow. Always run this.

8. **Register + document.** Add a row to `.claude/workflows/README.md`. Confirm the `meta.name` matches the filename slug.

9. **Offer a dry-run, don't auto-run.** Tell the user how to invoke it; offer to dry-run a doer so they see behavior before arming. Do NOT launch a writing workflow unprompted — running it spawns many agents and burns tokens (explicit opt-in only).

## Minimal skeleton

```js
export const meta = {
  name: 'my-workflow',                 // MUST equal the filename slug; pure literal only
  description: 'One line — what it does and why.',
  whenToUse: 'When to reach for this.',
  phases: [
    { title: 'Resolve', detail: 'discovery agent classifies the repo universe' },
    { title: 'Survey', detail: '…' },
    { title: 'Synthesize', detail: '…' },
  ],
}

// (doer only) dry-run by default
const DRY_RUN = !(args && args.dryRun === false)

// ── Resolve the repo universe (RESOLVER.md) — never hardcode a list. ──
const RESOLVE_SCHEMA = { type: 'object', additionalProperties: false,
  required: ['repos', 'source'],
  properties: { source: { type: 'string' },
    repos: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['name', 'path', 'class'],
      properties: { name: { type: 'string' }, path: { type: 'string' },
        class: { type: 'string', enum: ['SERVICE','LIBRARY','UI','INFRA'] },
        language: { type: 'string' } } } },
    gaps: { type: 'array', items: { type: 'string' } } } }

phase('Resolve')
const manifest = await agent(
  `Resolve this workspace's repo universe per .claude/workflows/RESOLVER.md (args.repos -> repos.config.js -> .gitmodules -> marker auto-discovery; first non-empty rung wins). Return repos[{name,path,class,language}], gaps[], and source. Read-only.`,
  { label: 'resolve', phase: 'Resolve', schema: RESOLVE_SCHEMA, agentType: 'Explore' })
const repos = (manifest && manifest.repos) || []
if (repos.length === 0) return { error: 'Resolve found no repos.', manifest }

const ITEM_SCHEMA = { type: 'object', additionalProperties: false,
  required: ['repo', 'result'],
  properties: { repo: { type: 'string' }, result: { type: 'string' } } }

phase('Survey')
const found = (await parallel(repos.map(r => () =>
  agent(`Do X for "${r.name}" (path "${r.path}"). Return the object.`,
    { label: `survey:${r.name}`, phase: 'Survey', schema: ITEM_SCHEMA, agentType: 'Explore' })
))).filter(Boolean)

phase('Synthesize')
const summary = await agent(`Synthesize:\n${JSON.stringify(found, null, 2)}`,
  { label: 'synthesize', phase: 'Synthesize' })

return { found, summary }
```

## How the user runs it afterward

```
Workflow({ name: "my-workflow" })                          # read-only, or doer dry-run
Workflow({ name: "my-workflow", args: { dryRun: false } }) # arm a doer for real PRs
Workflow({ name: "my-workflow", args: { … } })             # parameterized input
```

## Reference

- [RULES.md](RULES.md) — the non-negotiable authoring rules (meta literal, JS-not-TS, pipeline-default, barrier-only-when, concurrency cap, resolver + verify-map, the project safety net).
- [PATTERNS.md](PATTERNS.md) — copy-paste templates for the three workflow shapes + the schema/dry-run/worktree/resolver idioms.
- The existing library in `.claude/workflows/` is the living reference — read a sibling before inventing.
