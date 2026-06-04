// _doctrine.js — SINGLE SOURCE OF TRUTH for the THREE script-layer disciplines every
// workflow must obey, so quality is a script-asserted proof and never a prompt's promise:
//   1. universal-handoff helper          (withResume / resumingAgent)
//   2. file-first FINISH gate for audits (fileFindingsOrBlock — every finding
//      SCRIPT-guaranteed onto the board, deduped + labelled + quarantined)
//   3. DoD FINISH gate for doers         (finishDoerOrBlock — tree-clean +
//      verify-GREEN + PR-opened, SCRIPT-asserted, verdict MUST be APPROVED)
//
// HOW WORKFLOWS USE THIS: the Workflow runtime is a sandbox — no import/require/fs/
// Date.now/Math.random at script layer, and no module loader. So a workflow does NOT
// import this file; it pastes the CANONICAL REGION below (between the two delimiter
// lines) byte-identical, stripping the leading `export ` keyword (workflows inline as
// bare const/function). The check-doctrine-drift.sh hash-gate extracts each workflow's
// region and sha-compares it to this canonical region — drift is a BLOCKED write, the
// same zero-drift discipline as the single-sourced secret-patterns. When this file
// changes, update HERE first, then re-sync every workflow's inlined region.
//
// The load-bearing realization that shapes the two finish helpers: the SCRIPT LAYER
// cannot run `gh`, `git`, or the verify command (it has no Bash/fs). So a
// "script-guaranteed" finish is implemented as: the script spawns a single-purpose
// AGENT (filer = junior-worker / verifier = tester) with a tight return schema, then
// the SCRIPT ASSERTS the structured proof before allowing return/PR. The guarantee
// lives in the assertion, not in a prompt's good intentions.
//
// GENERICITY: this file hardcodes no repo/tracker/verify identity. Callers pass the
// target repo via opts.repo (workflows resolve it from skills-config.json in their own
// resolve phase) and the CI-equivalent command via opts.verifyInstruction. The region
// stays project-agnostic so any consumer's workflows can inline it unchanged.
//
// ─────────────────────────────────────────────────────────────────────────────
// EVERYTHING BETWEEN THE DELIMITERS IS WHAT A WORKFLOW INLINES (strip `export `).
// The DOCTRINE_BLOCK_DELIMITERS / DEDUP_* constants that NAME the delimiters live
// OUTSIDE the region (a region cannot contain a literal copy of its own fence text
// without breaking the extractor) — see the bottom of this file.
// ─────────────────────────────────────────────────────────────────────────────

// ─── BEGIN _doctrine.js canonical (do not edit) ───

// withResume(schema) — MODULE 1. Pure. Returns a NEW schema with the two
// context-budget escape fields merged into properties; never mutates the input and
// leaves `required` untouched (the escape fields stay optional).
export function withResume(schema) {
  return { ...schema, properties: { ...schema.properties,
    _status: { type: 'string', enum: ['done', 'partial', 'failed'], description: 'done unless you hit a context limit with work left' },
    _resumeFrom: { type: 'string', description: 'if _status=partial: exactly what remains, so a fresh instance continues' },
  } }
}
// resumingAgent(basePrompt, opts) — MODULE 1. The UNIVERSAL handoff wrapper around
// agent(): EVERY agent() in EVERY workflow goes through this. Wraps opts.schema via
// withResume, loops to opts.maxAttempts (default 4), re-calls a FRESH agent() with a
// resume note when the prior returned _status==='partial', labels retries :r2/:r3…,
// returns the last result (null if the underlying agent errored every attempt —
// callers already .filter(Boolean)).
export async function resumingAgent(basePrompt, opts) {
  const schema = withResume(opts.schema)
  const cap = opts.maxAttempts || 4
  let resumeNote = '', attempts = 0, result = null
  while (attempts < cap) {
    attempts++
    const prompt = `${basePrompt}\n\nCONTEXT-BUDGET ESCAPE (fallback): finish the task and return _status="done". If you approach your context limit with work still left, STOP at a safe boundary, persist/commit what is complete, and return _status="partial" with _resumeFrom describing EXACTLY what remains.${resumeNote ? `\n\nRESUME: a prior instance got partway. ${resumeNote} Continue from there — do not redo finished work.` : ''}`
    result = await agent(prompt, { ...opts, label: `${opts.label}${attempts > 1 ? `:r${attempts}` : ''}` })
    if (!result || result._status !== 'partial') break
    resumeNote = result._resumeFrom || 'finish what remains'
    log(`${opts.label} returned PARTIAL (attempt ${attempts}) — resuming fresh agent.`)
  }
  return result
}

// ── MODULE 2 — the board vocabulary schemas (one definition, all workflows) ──

// VERDICT_SCHEMA — the critic→fixer→auditor verdict shape.
export const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['verdict', 'summary'],
  properties: {
    verdict: { type: 'string', enum: ['APPROVED', 'CONDITIONAL', 'REJECTED'] },
    summary: { type: 'string' },
    conditions: { type: 'array', items: { type: 'string' } },
    sacredRuleViolations: { type: 'array', items: { type: 'string' } },
  },
}
// VERIFY_SCHEMA — the un-fakeable CI-equivalence proof shape.
export const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['green', 'output'],
  properties: { green: { type: 'boolean' }, output: { type: 'string' } },
}
// PR_SCHEMA — the PR-opening agent's return.
export const PR_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['outcome', 'summary'],
  properties: {
    outcome: { type: 'string', enum: ['PR_OPENED', 'DRY_RUN_READY', 'BLOCKED', 'ERROR'] },
    summary: { type: 'string' }, prUrl: { type: 'string' },
  },
}
// FILING_SCHEMA — the filer-agent (junior-worker) return, ONE entry per finding.
// `relatedTo` carries the SEMANTIC dedup proposals the filer surfaced for a human to
// triage (machine proposes, never auto-merges the judgment).
export const FILING_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['filed'],
  properties: {
    filed: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['dedupKey', 'action'],
        properties: {
          dedupKey: { type: 'string' },
          issueNumber: { type: 'number' },
          issueUrl: { type: 'string' },
          action: { type: 'string', enum: ['created', 'updated', 'already-current', 'dry-run'] },
          severity: { type: 'string' },
          category: { type: 'string' },
          service: { type: 'string' },
          relatedTo: {
            type: 'array',
            items: {
              type: 'object', additionalProperties: false, required: ['issue', 'why'],
              properties: { issue: { type: 'number' }, why: { type: 'string' } },
            },
          },
        },
      },
    },
  },
}
// FINISH_PROOF_SCHEMA — the verifier-agent (tester) return for the doer finish-gate.
export const FINISH_PROOF_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['treeClean', 'stagedByName', 'verifyGreen', 'contextNeeded', 'contextFresh'],
  properties: {
    treeClean: { type: 'boolean' },
    stagedByName: { type: 'boolean' },
    noAddAllTraces: { type: 'boolean' },
    verifyGreen: { type: 'boolean' },
    contextFresh: { type: 'boolean' },
    contextNeeded: { type: 'boolean' },
    branch: { type: 'string' },
    stagedFiles: { type: 'array', items: { type: 'string' } },
    verifyTail: { type: 'string' },
  },
}
// FINDING_SCHEMA — the normalized finding shape audits feed to the filer.
export const FINDING_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['service', 'file', 'findingType', 'severity', 'category', 'title', 'detail'],
  properties: {
    service: { type: 'string' },
    file: { type: 'string' },
    findingType: { type: 'string' },
    severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'info'] },
    category: { type: 'string' },
    title: { type: 'string' },
    detail: { type: 'string' },
    recommendation: { type: 'string' },
    fixGate: { type: 'string' },
  },
}

// ── MODULE 5 (data half) — the dedup/label constants the hook + filer share ──
// These are INSIDE the region because the in-region helpers reference them (shape A:
// every cross-reference must resolve in-scope when a workflow inlines the region).
// Only the self-referential DOCTRINE_BLOCK_DELIMITERS lives OUTSIDE (a region cannot
// contain a literal copy of its own fence text without breaking the extractor).
// The dedup-key FORMAT is `AUTOFILE:<service>:<normalized-file>:<findingType>`.
export const DEDUP_KEY_PREFIX = 'AUTOFILE:'
// repo is null by default — GENERIC: the target board is project-specific, so callers
// MUST pass opts.repo (workflows resolve it from skills-config.json issueTracker.repo
// in their resolve phase). quarantine is a sane cross-project default label.
export const DEDUP_LABELS = { quarantine: 'triage:needs-review', repo: null }

// normalizeFilePath(file) — deterministic, script-computed (no Date.now/Math.random):
// lowercases, strips a leading ./ or absolute-drive prefix, collapses path separators.
// Used to build the STABLE dedupKey so a re-run UPDATES the same issue instead of
// duplicating. GENERIC: no project-specific repo-name prefix is stripped (the crew has
// no fixed repo-naming convention); service+file+type still gives a stable identity.
function normalizeFilePath(file) {
  return String(file || '')
    .toLowerCase()
    .replace(/^[./\\]+/, '')
    .replace(/[/\\]+/g, '/')
    .trim()
}
// dedupKeyFor(finding) — `AUTOFILE:service:normalize(file):findingType`. Line/column
// deliberately excluded (they churn) — service+file+type is the stable identity of
// "this kind of problem here." Embedded in the issue body as an HTML-comment marker.
function dedupKeyFor(finding) {
  return `${DEDUP_KEY_PREFIX}${finding.service}:${normalizeFilePath(finding.file)}:${finding.findingType}`
}

// ── MODULE 3 — fileFindingsOrBlock(findings, opts) — the board-filing guarantee ──
// Makes audit filing SCRIPT-GUARANTEED. The script normalizes findings + computes a
// stable dedupKey for each (deterministically, no agent), spawns ONE filer agent
// (junior-worker — mechanical gh/git, cheapest capable) that SEMANTICALLY dedups
// against the whole board then files, and the SCRIPT ASSERTS full coverage before
// returning. A finding the script can't map to an issue BLOCKS.
//   findings : FINDING_SCHEMA[]
//   opts = { repo, dryRun, quarantineLabel, label } (helpers are in-scope — shape A)
//   opts.repo is REQUIRED (no project default) — resolve it from config before calling.
// Returns { filed, blocked, unfiled }.
export async function fileFindingsOrBlock(findings, opts) {
  opts = opts || {}
  const repo = opts.repo || DEDUP_LABELS.repo
  const quarantine = opts.quarantineLabel || DEDUP_LABELS.quarantine
  const dryRun = !!opts.dryRun
  const list = (findings || []).filter(Boolean)
  if (list.length === 0) return { filed: [], blocked: false, unfiled: [] }
  if (!repo) return { filed: [], blocked: true, unfiled: list.map(dedupKeyFor), error: 'no target repo: pass opts.repo (resolve from skills-config.json issueTracker.repo)' }

  // (1) SCRIPT computes the stable dedupKey for every finding — deterministic.
  const withKeys = list.map(f => ({ ...f, dedupKey: dedupKeyFor(f) }))
  const wantKeys = withKeys.map(f => f.dedupKey)

  // (2) ONE filer agent (junior-worker) does the SEMANTIC board-scan + dedup + file.
  const filerPrompt = `You are a junior-worker FILING audit findings onto the GitHub board for repo "${repo}". You have Bash — run \`gh\`. ${dryRun ? 'DRY RUN: do NOT create/comment any issue — instead report the exact gh command you WOULD run for each, with action="dry-run".' : ''}

STEP 0 — ensure the quarantine label exists (idempotent):
  gh label create "${quarantine}" --repo ${repo} --color FBCA04 --description "machine-surfaced finding awaiting human triage" 2>/dev/null || true

STEP 1 — read the WHOLE existing board ONCE for SEMANTIC dedup:
  gh issue list --repo ${repo} --state all --limit 400 --json number,title,labels,body
  Keep this in mind while filing each finding below.

For EACH finding (process ALL ${withKeys.length}; its precomputed dedupKey is authoritative — embed it, never recompute it):
  a) EXACT match — search the board for the dedup-key marker:
       gh issue list --repo ${repo} --search "<dedupKey>" --state all
     If an issue carries the marker \`<!-- dedup-key: <dedupKey> -->\` → it is the SAME problem.
       gh issue comment <N> --repo ${repo} --body "<refreshed detail>"   → action="updated", set issueNumber/issueUrl.
  b) NO exact marker, but a PLAUSIBLY-SIMILAR existing issue (same bug, near-dup title/body) →
       gh issue create the NEW issue, and in its body add a line:
         "Proposed related/duplicate: #<N> — <one-line why>"
       add the "${quarantine}" label, set action="created", and record relatedTo:[{issue:<N>, why:"…"}].
       Optionally also: gh issue comment <N> --body "Possible duplicate: this new finding #<new>".
     The MACHINE PROPOSES; a HUMAN decides — never auto-merge the judgment.
  c) NO match at all → gh issue create fresh → action="created".

Every CREATED issue MUST carry, in the body, the literal marker line on its own line:
    <!-- dedup-key: <dedupKey> -->
and MUST be created with these labels (assert each is in the --label flags):
    --label "severity:<finding.severity>" --label "category:<finding.category>" --label "service:<finding.service>" --label "${quarantine}"
    (plus --label "fix-gate:<finding.fixGate>" when fixGate is present)
Body format: Source (file paths), Detail, Reproduction, Impact, Recommendation, Owner/Routing, Fix gate.

FINDINGS (JSON; dedupKey is authoritative):
${JSON.stringify(withKeys, null, 2)}

Return FILING_SCHEMA: one \`filed\` entry per finding, each with its dedupKey, action, and (created/updated) issueNumber+issueUrl, plus relatedTo when you proposed a relationship. You MUST return one entry per finding — do not skip any.`

  const fileOnce = async (subset, labelSuffix) => resumingAgent(
    filerPrompt + (subset !== withKeys ? `\n\nRETRY — file ONLY these still-unfiled dedupKeys: ${subset.map(f => f.dedupKey).join(', ')}` : ''),
    { label: `${opts.label || 'file-findings'}${labelSuffix || ''}`, phase: 'File', schema: FILING_SCHEMA, agentType: 'junior-worker' }
  )

  let result = await fileOnce(withKeys, '')
  let filed = (result && result.filed) || []
  let filedKeys = new Set(filed.filter(e => e.dedupKey && (dryRun || typeof e.issueNumber === 'number')).map(e => e.dedupKey))
  let unfiled = wantKeys.filter(k => !filedKeys.has(k))

  // (3) ONE bounded retry of just the unfiled subset before BLOCKING.
  if (unfiled.length > 0) {
    const retrySet = withKeys.filter(f => unfiled.includes(f.dedupKey))
    const retry = await fileOnce(retrySet, ':retry')
    const more = (retry && retry.filed) || []
    filed = filed.concat(more)
    more.forEach(e => { if (e.dedupKey && (dryRun || typeof e.issueNumber === 'number')) filedKeys.add(e.dedupKey) })
    unfiled = wantKeys.filter(k => !filedKeys.has(k))
  }

  // (4) SCRIPT ASSERTS full coverage — the guarantee. Anything unmapped BLOCKS.
  const blocked = unfiled.length > 0
  if (blocked) {
    log(`fileFindingsOrBlock: BLOCKED — ${unfiled.length}/${wantKeys.length} findings NOT confirmed on the board: ${unfiled.join(', ')}`)
  }
  return { filed, blocked, unfiled }
}

// ── MODULE 4 — finishDoerOrBlock(opts) — the doer finish-gate ──
// Makes a doer's PR SCRIPT-GUARANTEED. After the critic→fixer→auditor pipeline
// produces a VERDICT_SCHEMA, the script spawns a verifier agent (tester — has Bash)
// that runs git status / staging-shape / the verify command on the branch and returns
// FINISH_PROOF_SCHEMA. The script computes the gate; a PR opens ONLY if it is open.
// CRITICAL: gate requires verdict === 'APPROVED' (CONDITIONAL is NOT open — a
// CONDITIONAL verdict must not ship caveated work).
//   opts = { verdict, service, branch, dryRun, verifyInstruction, contextNeeded,
//            prTitle, prBodyHint, baseBranch, label } (helpers + schemas in-scope)
// Returns { gateOpen, proof, pr, blockedReasons }.
export async function finishDoerOrBlock(opts) {
  opts = opts || {}
  const { verdict, service, branch } = opts
  const dryRun = !!opts.dryRun
  const contextNeeded = !!opts.contextNeeded
  const baseBranch = opts.baseBranch || 'the default branch'

  // (1) verifier agent (tester) returns the structured finish proof.
  const proof = await resumingAgent(
    `You are a tester producing the DEFINITIVE FINISH PROOF for service "${service}" on branch "${branch}" (shared checkout). You have Bash. Do NOT edit code — only inspect + run + report. On the branch:
  - git status --porcelain  → treeClean = NO output (no scratch, no untracked/dirty). Report stagedFiles (git diff --cached --name-only) and branch.
  - Confirm staging was by EXPLICIT name: inspect the last commit + reflog for any \`git add -A\`/\`git add .\` shape → noAddAllTraces = true if none found; stagedByName = true if every staged path was named explicitly.
  - CI-equivalence proof: ${opts.verifyInstruction || 'run the project CI-equivalent verify command for ' + service + ' (resolved from skills-config.json verify map)'} → verifyGreen = true ONLY if it reports GREEN. Put the output tail in verifyTail.
  - contextNeeded = ${contextNeeded}. If true, check CONTEXT.md freshness vs the diff (tables/endpoints/events/contracts) → contextFresh. If contextNeeded is false, set contextFresh = true.
Return FINISH_PROOF_SCHEMA. Be honest — a false GREEN here ships a broken PR.`,
    { label: `${opts.label || 'finish-verify'}`, phase: 'Gate', schema: FINISH_PROOF_SCHEMA, agentType: 'tester' }
  )

  // (2) SCRIPT computes the gate. === 'APPROVED' — CONDITIONAL is NOT open.
  const v = verdict && verdict.verdict
  const blockedReasons = []
  if (v !== 'APPROVED') blockedReasons.push(`verdict=${v} (must be APPROVED — CONDITIONAL/REJECTED do not open the gate)`)
  if (!proof) blockedReasons.push('no finish proof returned')
  if (proof && !proof.treeClean) blockedReasons.push('tree not clean (scratch/untracked/dirty)')
  if (proof && !proof.stagedByName) blockedReasons.push('staging not by explicit name')
  if (proof && proof.noAddAllTraces === false) blockedReasons.push('found git add -A / add . traces')
  if (proof && !proof.verifyGreen) blockedReasons.push('CI-equivalence not GREEN')
  if (proof && contextNeeded && !proof.contextFresh) blockedReasons.push('CONTEXT.md stale vs contract changes')

  const gateOpen = v === 'APPROVED' && proof && proof.treeClean && proof.stagedByName &&
    proof.noAddAllTraces !== false && proof.verifyGreen && (!contextNeeded || proof.contextFresh)

  // (3) ONLY if gateOpen does the PR-opening agent run (DRY_RUN → no push).
  let pr
  if (!gateOpen) {
    pr = { outcome: 'BLOCKED', summary: `Doer finish-gate CLOSED — ${blockedReasons.join('; ')}. No PR; returned for rework.` }
    return { gateOpen, proof, pr, blockedReasons }
  }
  pr = await resumingAgent(
    `"${service}" branch "${branch}" passed the doer finish-gate (auditor APPROVED, tree-clean, staged-by-name, verify GREEN${contextNeeded ? ', CONTEXT fresh' : ''}). ${dryRun
      ? 'DRY RUN: do NOT push or open a PR. Report outcome="DRY_RUN_READY" + one-line summary of what WOULD open.'
      : `Push the branch and open a PR to ${baseBranch}. Title "${opts.prTitle || `[${service}] ${branch}`}". Body: the project PR template — ${opts.prBodyHint || 'summary, the verify=GREEN proof, auditor verdict APPROVED, gate tier'}. Do NOT merge (human merge gate). outcome="PR_OPENED", set prUrl.`}`,
    { label: `${opts.label || 'finish'}:pr`, phase: 'Gate', schema: PR_SCHEMA, agentType: 'dev-lead' }
  )
  return { gateOpen, proof, pr, blockedReasons }
}

// ─── END _doctrine.js canonical ───

// ── MODULE 5 (the self-referential half) — the drift-gate contract constants ──
// These NAME the canonical region's fence lines, so they MUST live OUTSIDE the
// region (a region cannot contain a literal copy of its own delimiters without
// breaking the extractor). The hook (check-doctrine-drift.sh) and the workflows
// share this ONE definition — the same single-source discipline as the secret-patterns.

// DOCTRINE_BLOCK_DELIMITERS — the exact fence lines check-doctrine-drift.sh greps
// for. The ONLY doctrine constant that lives outside the region, because it names
// the region's own fence. DEDUP_KEY_PREFIX/DEDUP_LABELS are defined ONCE inside the
// region above (the in-region helpers reference them) and re-exported from there.
export const DOCTRINE_BLOCK_DELIMITERS = {
  begin: '// ─── BEGIN _doctrine.js canonical (do not edit) ───',
  end: '// ─── END _doctrine.js canonical ───',
}
