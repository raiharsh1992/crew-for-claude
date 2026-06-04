export const meta = {
  name: 'cross-repo-migration',
  description: 'Apply ONE well-specified change across many repos: discover which repos are affected, apply the change in an isolated worktree per repo, verify each (via the configured verify map), and (unless dry-run) open a PR per repo. For bump-a-shared-dep / rename-a-cross-service-event / add-a-CI-gate style sweeps.',
  whenToUse: 'When the SAME mechanical change must land in multiple repos (bump a shared dep, rename a cross-service event, add a CI gate, swap a deprecated import). Pass the change spec via args.',
  phases: [
    { title: 'Resolve', detail: 'discovery agent classifies the repo universe (RESOLVER.md)' },
    { title: 'Discover', detail: 'find which repos the change actually affects' },
    { title: 'Apply', detail: 'change + verify per repo in isolation, PR each (unless dry-run)' },
  ],
}

const DRY_RUN = !(args && args.dryRun === false)

// args.change = { title, instruction, grepHint?, repos? }
//   title       — short slug for branch/PR names (e.g. "bump-core-0-2-0")
//   instruction — the EXACT change to make, written for a dev-lead
//   grepHint    — optional regex to find affected repos in Discover
//   repos       — optional explicit repo list (scopes the Resolve step)
const change = (args && args.change) || null
if (!change || !change.instruction || !change.title) {
  return { error: 'cross-repo-migration requires args.change = { title, instruction, grepHint?, repos? }. Aborting — nothing done.' }
}

// ── Resolve the repo universe (RESOLVER.md) — NO hardcoded repo arrays. ──
const RESOLVE_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repos', 'source'],
  properties: {
    source: { type: 'string' },
    repos: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['name', 'path', 'class'],
        properties: {
          name: { type: 'string' },
          path: { type: 'string' },
          class: { type: 'string', enum: ['SERVICE', 'LIBRARY', 'UI', 'INFRA'] },
          language: { type: 'string' },
        },
      },
    },
    gaps: { type: 'array', items: { type: 'string' } },
  },
}

phase('Resolve')
log(`cross-repo-migration "${change.title}" — DRY_RUN=${DRY_RUN}`)
const manifest = await agent(
  `You are the Resolve-phase discovery agent. Determine this workspace's repo universe per .claude/workflows/RESOLVER.md (args.repos -> repos.config.js -> .gitmodules -> marker auto-discovery; stop at first non-empty rung).
${change.repos && change.repos.length ? `The caller scoped this sweep to these repo names: ${JSON.stringify(change.repos)} — restrict the manifest to those.` : 'No explicit repo scope was given — return the full universe.'}
Return repos[{name,path,class,language}], a gaps[] list, and the source rung. Read-only.`,
  { label: 'resolve', phase: 'Resolve', schema: RESOLVE_SCHEMA, agentType: 'Explore' }
)
const CANDIDATES = (manifest && manifest.repos) || []
log(`Resolve complete: ${CANDIDATES.length} candidate repos via ${manifest && manifest.source}`)
if (CANDIDATES.length === 0) {
  return { error: 'Resolve found no candidate repos. Fill .claude/workflows/repos.config.js or scope via args.change.repos.', manifest }
}

const DISCOVER_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'affected', 'reason'],
  properties: {
    repo: { type: 'string' },
    affected: { type: 'boolean' },
    reason: { type: 'string' },
    matchCount: { type: 'number', description: 'how many sites the grepHint matched, if used' },
  },
}

const APPLY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'outcome', 'summary'],
  properties: {
    repo: { type: 'string' },
    outcome: { type: 'string', enum: ['PR_OPENED', 'DRY_RUN_READY', 'VERIFY_FAILED', 'NO_CHANGE_NEEDED', 'ERROR'] },
    summary: { type: 'string' },
    diff: { type: 'string' },
    prUrl: { type: 'string' },
    verifyResult: { type: 'string' },
  },
}

phase('Discover')

const discovered = await parallel(CANDIDATES.map((r) => () =>
  agent(
    `Determine whether the repo "${r.name}" (path "${r.path}") is affected by this change:

CHANGE: ${change.instruction}
${change.grepHint ? `Look for sites matching: ${change.grepHint}` : ''}

Read-only. Report affected=true ONLY if the change genuinely applies here (the pattern exists / the dep is used / the gate is missing). Do NOT edit anything. Return the structured object.`,
    { label: `discover:${r.name}`, phase: 'Discover', schema: DISCOVER_SCHEMA, agentType: 'Explore' }
  )
)).filter(Boolean)

const byName = Object.fromEntries(CANDIDATES.map((r) => [r.name, r]))
const affected = discovered.filter((d) => d.affected)
log(`Discover complete: ${affected.length}/${CANDIDATES.length} affected — ${affected.map((a) => a.repo).join(', ') || 'none'}`)

if (affected.length === 0) {
  return { dryRun: DRY_RUN, change: change.title, source: manifest.source, discovered, applied: [], note: 'No repos affected by this change.' }
}

phase('Apply')

const applied = await parallel(affected.map((a) => () => {
  const r = byName[a.repo] || { name: a.repo, path: a.repo, class: 'SERVICE', language: '' }
  return agent(
    `You are applying a cross-repo change to "${r.name}" (path "${r.path}", class ${r.class}${r.language ? `, language ${r.language}` : ''}) in an ISOLATED worktree. You own this one repo's change end-to-end and obey docs/AGENT-WORKFLOW.md.

CHANGE TO MAKE: ${change.instruction}

Rules:
- Make ONLY this change. No scope creep, no opportunistic refactors, no formatting churn beyond what the change requires.
- Honor your project's CLAUDE.md rules.
- Stage files BY EXPLICIT NAME (never git add -A — it may sweep in scratch).
- If on inspection the change turns out not to be needed here, outcome="NO_CHANGE_NEEDED" and stop.

Then:
1. Create branch "chore/${change.title}-${r.name}".
2. Prove it: resolve this repo's verify command from .claude/skills-config.json (verify.byRepo.${r.name}.overrides.verify -> verify.defaults[${r.language ? `"${r.language}"` : 'this-repo-language'}].verify -> the built-in fallback for its language×class), then run that command from the repo root. Capture the result; it must be GREEN.
${DRY_RUN
  ? '3. DRY RUN: do NOT push/PR. outcome="DRY_RUN_READY", put the unified diff in "diff". If verify failed -> "VERIFY_FAILED".'
  : `3. If GREEN: commit ("chore(${r.name}): ${change.title}"), push, open a PR to the default branch titled "[${r.name}] ${change.title}". outcome="PR_OPENED", set prUrl. If verify failed, do NOT push -> "VERIFY_FAILED".`}

Return the structured object.`,
    { label: `apply:${r.name}`, phase: 'Apply', schema: APPLY_SCHEMA, isolation: 'worktree', agentType: 'dev-lead' }
  )
})).filter(Boolean)

return { dryRun: DRY_RUN, change: change.title, source: manifest.source, discovered, applied }
