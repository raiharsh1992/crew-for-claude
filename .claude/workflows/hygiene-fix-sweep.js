export const meta = {
  name: 'hygiene-fix-sweep',
  description: 'Apply ONE CONFIGURED baseline-config fix across every repo that still lacks it: detect the violation, apply the fix in an isolated worktree, verify each (via the configured verify map), and (unless dry-run) open a PR per repo. The baseline rule is passed in args (e.g. a coverage-precision config, a CI-gate setting, a lint-config line) — this is the standing anti-drift sweep for your project\'s hygiene baseline.',
  whenToUse: 'To roll a single hygiene-baseline config fix across all repos in one shot instead of one-repo-at-a-time, or any time you suspect repos have drifted off a baseline config rule.',
  phases: [
    { title: 'Resolve', detail: 'discovery agent classifies the repo universe (RESOLVER.md)' },
    { title: 'Detect', detail: 'one Explore agent per repo checks for the baseline violation' },
    { title: 'Fix', detail: 'for each violating repo, apply + verify the fix in an isolated worktree, open PR unless dry-run' },
  ],
}

// args.dryRun defaults TRUE — do the work + verify, but STOP before push/PR.
// Pass { dryRun: false } to arm it for real PRs.
const DRY_RUN = !(args && args.dryRun === false)

// args.baseline = { title, detect, fix, scope?, classes? }
//   title    — short slug for branch/PR names + commit messages.
//   detect   — read-only instruction: how to tell if a repo VIOLATES the baseline.
//   fix      — the EXACT, minimal fix to apply (config-only, no scope creep).
//   scope    — optional human note describing which repos this applies to.
//   classes  — optional array of RepoClass values to restrict the sweep
//              (e.g. ['SERVICE','LIBRARY'] to skip UI/INFRA). Default: all.
//
// DEFAULT (if no args.baseline given): a coverage-precision baseline example for
// Python repos — ensures the coverage gate uses a precise threshold and is
// single-sourced in project config (not duplicated on the test command line).
const baseline = (args && args.baseline) || {
  title: 'coverage-precision',
  detect:
    'Check this repo for a single-sourced, precise coverage gate. For a Python repo: pyproject.toml [tool.coverage.report] should have BOTH "precision = 2" AND exactly ONE "fail_under = <N>"; the CI workflow should NOT pass a competing "--cov-fail-under" flag on the test line (that competes with the config and lets a value below the floor round up to pass). A repo VIOLATES the baseline if precision=2 is missing, fail_under is duplicated across config+CI, or CI still carries the redundant flag. For a non-Python repo, treat as "not applicable" (needsFix=false).',
  fix:
    'Apply EXACTLY this fix (config-only, no scope creep): (1) ensure "precision = 2" is present and exactly ONE "fail_under = <N>" in pyproject.toml [tool.coverage.report] — keep the repo\'s existing floor value, do NOT raise or lower it; (2) remove any redundant "--cov-fail-under=..." from the CI test line (keep "--cov-report=xml"); (3) touch nothing else.',
  classes: ['SERVICE', 'LIBRARY'],
}
const RESTRICT = (baseline.classes && baseline.classes.length) ? baseline.classes : null

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
log(`hygiene-fix-sweep "${baseline.title}" — DRY_RUN=${DRY_RUN}`)
const manifest = await agent(
  `You are the Resolve-phase discovery agent. Determine this workspace's repo universe per .claude/workflows/RESOLVER.md (args.repos -> repos.config.js -> .gitmodules -> marker auto-discovery; stop at first non-empty rung). Return repos[{name,path,class,language}], a gaps[] list, and the source rung. Read-only.`,
  { label: 'resolve', phase: 'Resolve', schema: RESOLVE_SCHEMA, agentType: 'Explore' }
)
let repos = (manifest && manifest.repos) || []
if (RESTRICT) repos = repos.filter((r) => RESTRICT.includes(r.class))
log(`Resolve complete: ${repos.length} candidate repos via ${manifest && manifest.source}${RESTRICT ? ` (restricted to ${RESTRICT.join('/')})` : ''}`)
if (repos.length === 0) {
  return { error: 'Resolve found no candidate repos. Fill .claude/workflows/repos.config.js or adjust args.baseline.classes.', manifest }
}

const DETECT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'needsFix', 'reason'],
  properties: {
    repo: { type: 'string' },
    needsFix: { type: 'boolean' },
    reason: { type: 'string', description: 'what is missing/wrong, or "already compliant" / "not applicable"' },
  },
}

const FIX_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'outcome', 'summary'],
  properties: {
    repo: { type: 'string' },
    outcome: { type: 'string', enum: ['PR_OPENED', 'DRY_RUN_READY', 'VERIFY_FAILED', 'SKIPPED', 'ERROR'] },
    summary: { type: 'string' },
    diff: { type: 'string', description: 'the unified diff that was / would be applied' },
    prUrl: { type: 'string', description: 'PR URL if opened, else ""' },
    verifyResult: { type: 'string', description: 'verify command outcome' },
  },
}

phase('Detect')
const detected = await parallel(repos.map((r) => () =>
  agent(
    `Audit ONLY the repo "${r.name}" (path "${r.path}", class ${r.class}${r.language ? `, language ${r.language}` : ''}) for this baseline rule:

BASELINE "${baseline.title}":
${baseline.detect}

Set needsFix=true ONLY if the repo genuinely violates the baseline. Read-only — do not edit anything. Return the structured object.`,
    { label: `detect:${r.name}`, phase: 'Detect', schema: DETECT_SCHEMA, agentType: 'Explore' }
  )
)).filter(Boolean)

const byName = Object.fromEntries(repos.map((r) => [r.name, r]))
const violating = detected.filter((d) => d.needsFix)
log(`Detect complete: ${violating.length}/${repos.length} repos need the fix — ${violating.map((v) => v.repo).join(', ') || 'none'}`)

if (violating.length === 0) {
  return { dryRun: DRY_RUN, baseline: baseline.title, source: manifest.source, detected, fixed: [], note: `All candidate repos already compliant with the "${baseline.title}" baseline.` }
}

phase('Fix')
const fixed = await parallel(violating.map((v) => () => {
  const r = byName[v.repo] || { name: v.repo, path: v.repo, class: 'SERVICE', language: '' }
  return agent(
    `You are applying the "${baseline.title}" baseline fix to repo "${r.name}" (path "${r.path}", class ${r.class}${r.language ? `, language ${r.language}` : ''}). Working in an ISOLATED git worktree — your edits will not collide with other agents.

Detected problem: ${v.reason}

Apply EXACTLY this fix (no scope creep):
${baseline.fix}

Honor your project's CLAUDE.md rules. Then:
1. Create a branch "fix/${baseline.title}-${r.name}".
2. Prove it: resolve this repo's verify command from .claude/skills-config.json (verify.byRepo["${r.name}"].overrides.verify -> verify.defaults[language].verify -> the built-in fallback for its language×class) and run it from the repo root. Capture the result; it must be GREEN.
3. Stage files BY EXPLICIT NAME (never git add -A — it may sweep in scratch).
${DRY_RUN
  ? '4. DRY RUN: DO NOT push, DO NOT open a PR. Set outcome="DRY_RUN_READY" and put the exact unified diff in "diff". If verify failed, outcome="VERIFY_FAILED".'
  : `4. If verify is GREEN: commit (message "chore(${r.name}): adopt ${baseline.title} baseline"), push the branch, open a PR to the default branch with title "[${r.name}] hygiene: ${baseline.title}". Set outcome="PR_OPENED" and prUrl. If verify FAILED, do NOT push — outcome="VERIFY_FAILED".`}

Return the structured object with the diff and verify result.`,
    { label: `fix:${r.name}`, phase: 'Fix', schema: FIX_SCHEMA, isolation: 'worktree', agentType: 'dev-lead' }
  )
})).filter(Boolean)

return { dryRun: DRY_RUN, baseline: baseline.title, source: manifest.source, detected, fixed }
