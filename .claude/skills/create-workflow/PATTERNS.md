# Workflow patterns (copy-paste templates)

Three shapes cover almost everything. Start from the closest one, then adapt. Read a
matching sibling in `.claude/workflows/` for a real, working example.

Every sweeping workflow opens the same way: a **Resolve phase** that classifies the repo
universe (never a hardcoded array). The snippet below is shared by all three patterns —
paste it once at the top.

```js
// ── Resolve the repo universe (RESOLVER.md) — shared by every sweeping workflow. ──
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
```

---

## Pattern A — fan-out → synthesize (audits / reports, READ-ONLY)
One agent per repo in parallel, then a single synthesizer over all results.
Real example: `build-status-audit.js`.

```js
export const meta = {
  name: 'thing-audit',
  description: 'Audit X across all repos and synthesize a verdict.',
  whenToUse: 'When you want a code-grounded report on X across the workspace.',
  phases: [
    { title: 'Resolve', detail: 'discovery agent classifies the repo universe' },
    { title: 'Survey', detail: 'one Explore agent per repo' },
    { title: 'Synthesize', detail: 'merge into one verdict' },
  ],
}

// (paste the shared Resolve snippet here — gives you `repos`)

const REPO_SCHEMA = { type: 'object', additionalProperties: false,
  required: ['repo', 'finding'],
  properties: { repo: { type: 'string' }, finding: { type: 'string' },
    flag: { type: 'boolean' } } }

phase('Survey')
const results = (await parallel(repos.map(r => () =>
  agent(`Audit ONLY "${r.name}" (path "${r.path}", class ${r.class}) for X. Read-only. Return the object.`,
    { label: `audit:${r.name}`, phase: 'Survey', schema: REPO_SCHEMA, agentType: 'Explore' })
))).filter(Boolean)

phase('Synthesize')
const synthesis = await agent(
  `Synthesize these per-repo findings into a matrix + verdict:\n${JSON.stringify(results, null, 2)}`,
  { label: 'synthesis', phase: 'Synthesize' })

return { source: manifest.source, results, synthesis }
```

---

## Pattern B — discover → apply (DOER sweeps, writes code)
Parallel detect (read-only) → filter to the affected set → parallel apply in **worktrees**,
DRY-RUN by default. Real examples: `hygiene-fix-sweep.js`, `cross-repo-migration.js`.

```js
export const meta = {
  name: 'fix-sweep',
  description: 'Apply fix Y to every repo that needs it; verify each; PR each (unless dry-run).',
  whenToUse: 'To roll fix Y across all repos in one shot.',
  phases: [
    { title: 'Resolve', detail: 'discovery agent classifies the repo universe' },
    { title: 'Detect', detail: 'which repos need it' },
    { title: 'Fix', detail: 'apply + verify in isolation, PR unless dry-run' },
  ],
}

const DRY_RUN = !(args && args.dryRun === false)

// (paste the shared Resolve snippet here — gives you `repos`)

const DETECT = { type: 'object', additionalProperties: false,
  required: ['repo', 'needsFix', 'reason'],
  properties: { repo:{type:'string'}, needsFix:{type:'boolean'}, reason:{type:'string'} } }
const FIX = { type: 'object', additionalProperties: false,
  required: ['repo', 'outcome', 'summary'],
  properties: { repo:{type:'string'},
    outcome:{type:'string', enum:['PR_OPENED','DRY_RUN_READY','VERIFY_FAILED','SKIPPED','ERROR']},
    summary:{type:'string'}, diff:{type:'string'}, prUrl:{type:'string'} } }

phase('Detect')
log(`fix-sweep — DRY_RUN=${DRY_RUN}`)
const detected = (await parallel(repos.map(r => () =>
  agent(`Read-only: does "${r.name}" (path "${r.path}") need fix Y? Return the object.`,
    { label:`detect:${r.name}`, phase:'Detect', schema:DETECT, agentType:'Explore' })
))).filter(Boolean)
const byName = Object.fromEntries(repos.map(r => [r.name, r]))
const todo = detected.filter(d => d.needsFix)
log(`${todo.length} repos need the fix`)
if (todo.length === 0) return { dryRun: DRY_RUN, detected, fixed: [] }

phase('Fix')
const fixed = (await parallel(todo.map(t => () => {
  const r = byName[t.repo] || { name: t.repo, path: t.repo, class: 'SERVICE', language: '' }
  return agent(`Fix Y in "${r.name}" (path "${r.path}", class ${r.class}) — isolated worktree. Problem: ${t.reason}.
Make ONLY this change, honor your project's CLAUDE.md rules, stage by explicit name (no git add -A), create a branch, then prove it: resolve this repo's verify command from .claude/skills-config.json (byRepo.overrides -> defaults[language] -> fallback) and run it. Must be GREEN.
${DRY_RUN ? 'DRY RUN: do NOT push/PR — outcome="DRY_RUN_READY", put the diff in "diff".'
          : 'If GREEN: commit, push, open a PR to the default branch — outcome="PR_OPENED", set prUrl.'}
Return the object.`,
    { label:`fix:${r.name}`, phase:'Fix', schema:FIX, isolation:'worktree', agentType:'dev-lead' })
}))).filter(Boolean)

return { dryRun: DRY_RUN, source: manifest.source, detected, fixed }
```

---

## Pattern C — find → verify → synthesize (REVIEWS, use `pipeline`)
Each review dimension flows through verify as soon as IT finishes — no barrier. Adversarial
verify kills plausible-but-wrong findings. Real shape behind `slice-ship.js`'s gate.

The DIMENSIONS below are EXAMPLES — replace them with the review lenses that matter for
YOUR project (pull the specifics from your CLAUDE.md: whatever security, data-isolation,
audit, secret-handling, or correctness rules you enforce).

```js
export const meta = {
  name: 'branch-review',
  description: 'Review a branch across dimensions; adversarially verify each finding.',
  whenToUse: 'Before merging a risky branch — multi-lens review with verification.',
  phases: [{ title: 'Review' }, { title: 'Verify' }],
}

// EXAMPLE dimensions — swap for your project's actual review rules.
const DIMENSIONS = [
  { key: 'secrets',     prompt: 'Find hardcoded/committed credentials.' },
  { key: 'authz',       prompt: 'Find access-control gaps on protected operations.' },
  { key: 'validation',  prompt: 'Find unvalidated external input reaching a sink.' },
  { key: 'coverage',    prompt: 'Find public functions with no golden-path + edge test.' },
]
const FINDINGS = { type:'object', additionalProperties:false, required:['findings'],
  properties:{ findings:{ type:'array', items:{ type:'object', additionalProperties:false,
    required:['title','file'], properties:{ title:{type:'string'}, file:{type:'string'} } } } } }
const VERDICT = { type:'object', additionalProperties:false, required:['isReal','why'],
  properties:{ isReal:{type:'boolean'}, why:{type:'string'} } }

const results = await pipeline(
  DIMENSIONS,
  d => agent(`Review the current branch: ${d.prompt} Return {findings}.`,
        { label:`review:${d.key}`, phase:'Review', schema:FINDINGS }),
  review => parallel((review.findings || []).map(f => () =>
    agent(`Adversarially verify — try to REFUTE: "${f.title}" in ${f.file}. Default isReal=false if uncertain.`,
          { label:`verify:${f.file}`, phase:'Verify', schema:VERDICT })
      .then(v => ({ ...f, verdict: v }))))
)
const confirmed = results.flat().filter(Boolean).filter(f => f.verdict && f.verdict.isReal)
return { confirmed }
```

---

## Idioms cheat-sheet

| Need | Do |
|---|---|
| Resolve the repo universe | the shared **Resolve phase** snippet → `manifest.repos` (never a hardcoded array) |
| Resolve a verify command | agent reads `skills-config.json` verify map (`byRepo.overrides` → `defaults[language]` → fallback) |
| Per-item structured output | `agent(prompt, { schema })` → returns validated object |
| Drop failed items | `.filter(Boolean)` after parallel/pipeline |
| Parallel writers, no collision | `isolation: 'worktree'` per agent |
| Cheapest reader | `agentType: 'Explore'` |
| Progress group | `phase('X')` + `{ phase: 'X' }` on agents inside parallel/pipeline |
| Narrator line for the user | `log('…')` |
| Parameterized input | read `args.foo`; guard + early-return if required args missing |
| Dry-run default | `const DRY_RUN = !(args && args.dryRun === false)` |
| Loop until budget | `while (budget.total && budget.remaining() > 50_000) { … }` |
| Resume after edit | user re-runs `Workflow({ scriptPath, resumeFromRunId })` — unchanged calls cached |
