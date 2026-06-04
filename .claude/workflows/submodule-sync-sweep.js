export const meta = {
  name: 'submodule-sync-sweep',
  description: 'After a merge wave in a superproject, find every submodule whose parent pointer is stale (parent records an older commit than the submodule default branch) and bump it. Each bump lands on a branch in an isolated worktree; unless dry-run, opens the parent PR(s).',
  whenToUse: 'After merging one or more submodule PRs to their default branch, to sync the parent superproject pointers — the mechanical step you otherwise do by hand every wave. Only applies to a workspace that is a git superproject with submodules.',
  phases: [
    { title: 'Detect', detail: 'compare each submodule default-branch tip vs the parent pointer' },
    { title: 'Bump', detail: 'stage stale pointers + open the parent PR (unless dry-run)' },
  ],
}

const DRY_RUN = !(args && args.dryRun === false)

const DETECT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['stale', 'summary'],
  properties: {
    summary: { type: 'string' },
    isSuperproject: { type: 'boolean', description: 'false if this workspace has no .gitmodules (nothing to sweep)' },
    stale: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['submodule', 'parentSha', 'tipSha'],
        properties: {
          submodule: { type: 'string', description: 'submodule path' },
          parentSha: { type: 'string', description: 'short sha the parent currently points at' },
          tipSha: { type: 'string', description: 'short sha of the submodule remote default-branch tip' },
          behindBy: { type: 'string', description: 'e.g. "3 commits" or "unknown"' },
        },
      },
    },
  },
}

const BUMP_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['outcome', 'summary'],
  properties: {
    outcome: { type: 'string', enum: ['PR_OPENED', 'DRY_RUN_READY', 'NOTHING_STALE', 'ERROR'] },
    summary: { type: 'string' },
    bumped: { type: 'array', items: { type: 'string' }, description: 'submodule paths bumped' },
    prUrl: { type: 'string' },
    diff: { type: 'string', description: 'git diff of the pointer changes (gitlink shas)' },
  },
}

phase('Detect')
log(`submodule-sync-sweep starting — DRY_RUN=${DRY_RUN}`)

const detect = await agent(
  `In the parent (superproject) repo at the workspace root, find every submodule whose recorded pointer is BEHIND its remote default-branch tip.

First: if there is no .gitmodules at the workspace root, this is not a superproject — return isSuperproject=false, stale=[]. Otherwise, for each submodule listed in .gitmodules:
1. Get the SHA the parent currently records (the gitlink sha): \`git ls-tree HEAD <submodule-path>\` from the workspace root.
2. Determine the submodule's remote default branch (origin/HEAD, commonly main or master) and fetch its tip: \`git -C <submodule-path> fetch origin\` then \`git -C <submodule-path> rev-parse --short origin/<default-branch>\`.
3. If they differ AND the remote tip is ahead, it's stale.
Do NOT modify anything. Return isSuperproject=true and the structured list of stale submodules only (skip up-to-date ones).`,
  { label: 'detect-stale', phase: 'Detect', schema: DETECT_SCHEMA, agentType: 'Explore' }
)

if (detect && detect.isSuperproject === false) {
  return { dryRun: DRY_RUN, stale: [], note: 'Workspace is not a git superproject (no .gitmodules) — nothing to sweep.' }
}

const stale = (detect && detect.stale) || []
log(`Detect complete: ${stale.length} stale pointer(s) — ${stale.map((s) => s.submodule).join(', ') || 'none'}`)

if (stale.length === 0) {
  return { dryRun: DRY_RUN, stale: [], note: 'All parent submodule pointers are up to date — nothing to bump.' }
}

phase('Bump')

const bump = await agent(
  `You are syncing stale submodule pointers in the parent (superproject) repo at the workspace root. Working in an isolated worktree.

Stale submodules to bump (submodule -> target tip sha):
${stale.map((s) => `- ${s.submodule}: ${s.parentSha} -> ${s.tipSha}`).join('\n')}

Steps:
1. From the default branch, create branch "chore/sync-submodule-pointers".
2. For each stale submodule: enter it, checkout + pull --ff-only its remote default branch, return to the parent.
3. Stage ONLY those submodule paths BY EXPLICIT NAME (never \`git add -A\` — the tree may contain scratch).
4. Show \`git diff --cached\` (the gitlink sha changes) and put it in "diff".
${DRY_RUN
  ? '5. DRY RUN: DO NOT commit/push/PR. outcome="DRY_RUN_READY", list bumped submodules.'
  : '5. Commit "chore: sync submodule pointers — post-merge wave", push the branch, open a PR to the parent default branch listing the bumped submodules. outcome="PR_OPENED", set prUrl.'}

Return the structured object.`,
  { label: 'bump', phase: 'Bump', schema: BUMP_SCHEMA, isolation: 'worktree', agentType: 'dev-lead' }
)

return { dryRun: DRY_RUN, stale, bump }
