export const meta = {
  name: 'drift-audit',
  description: 'The honest mirror: fan out across every repo and detect three kinds of drift — (1) doc-vs-code (CONTEXT.md stale vs actual tables/endpoints/surfaces), (2) copy-vs-source (files that should be identical across repos but diverged, e.g. shared hooks), (3) config-vs-baseline (your project\'s hygiene-baseline / CI gates). Read-only: reports drift per repo per axis; you decide what to fix.',
  whenToUse: 'Periodically, or before a release / handoff, to catch every kind of rot in one pass. Pair with hygiene-fix-sweep (fixes the config axis) once the report is in. Drift is the recurring failure mode of a multi-repo workspace — this is the standing check for it.',
  phases: [
    { title: 'Resolve', detail: 'discovery agent classifies the repo universe (RESOLVER.md)' },
    { title: 'Scan', detail: 'one auditor per repo checks doc/copy/config drift' },
    { title: 'Synthesize', detail: 'consolidated drift matrix + severity + recommended remediation per axis' },
  ],
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
const manifest = await agent(
  `You are the Resolve-phase discovery agent. Determine this workspace's repo universe per .claude/workflows/RESOLVER.md (args.repos -> repos.config.js -> .gitmodules -> marker auto-discovery; stop at first non-empty rung). Return repos[{name,path,class,language}], a gaps[] list, and the source rung. Read-only.`,
  { label: 'resolve', phase: 'Resolve', schema: RESOLVE_SCHEMA, agentType: 'Explore' }
)
const repos = (manifest && manifest.repos) || []
log(`Resolve complete: ${repos.length} repos via ${manifest && manifest.source}`)
if (repos.length === 0) {
  return { error: 'Resolve found no repos. Fill .claude/workflows/repos.config.js or run from a workspace with project markers.', manifest }
}

// One structured finding per repo, with a sub-result per drift axis.
const DRIFT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repo', 'anyDrift', 'axes'],
  properties: {
    repo: { type: 'string' },
    anyDrift: { type: 'boolean', description: 'true if ANY axis drifted' },
    axes: {
      type: 'object', additionalProperties: false,
      required: ['docVsCode', 'configVsBaseline'],
      properties: {
        docVsCode: {
          type: 'object', additionalProperties: false,
          required: ['drifted', 'detail'],
          properties: {
            drifted: { type: 'boolean' },
            detail: { type: 'string', description: 'what in CONTEXT.md is stale vs the actual models/routers/events/surfaces, or "fresh"' },
          },
        },
        configVsBaseline: {
          type: 'object', additionalProperties: false,
          required: ['drifted', 'detail'],
          properties: {
            drifted: { type: 'boolean' },
            detail: { type: 'string', description: "violations of the project's hygiene baseline (CI gates loosened, coverage gate not single-sourced/imprecise, lint not run on tests, etc.), or \"compliant\"" },
          },
        },
        copyVsSource: {
          type: 'object', additionalProperties: false,
          required: ['drifted', 'detail'],
          properties: {
            drifted: { type: 'boolean' },
            detail: { type: 'string', description: 'shared/propagated files that diverged from their canonical source (e.g. .claude/hooks/*.sh vs the workspace-root copies, stale per-repo command copies), or "n/a / in sync"' },
          },
        },
      },
    },
    severity: { type: 'string', enum: ['none', 'low', 'medium', 'high'], description: 'worst-axis severity; doc-vs-code on a repo with live tables = high' },
  },
}

phase('Scan')
log(`drift-audit — scanning ${repos.length} repos across 3 per-repo axes`)

const perRepo = (await parallel(repos.map((r) => () => {
  const isUI = r.class === 'UI'
  const isInfra = r.class === 'INFRA'
  return agent(
    `Drift audit of ONE repo: "${r.name}" (path "${r.path}", class ${r.class}${r.language ? `, language ${r.language}` : ''}). Read-only — detect, do not fix. Check three drift axes:

AXIS 1 — doc-vs-code (CONTEXT.md freshness, the BINDING rule):
  Read the repo's CONTEXT.md (if present). Compare its claims (tables, endpoints, events, cross-service contracts, state machines, surfaces) against the ACTUAL code:
  ${isUI
    ? '- UI: compare CONTEXT.md routes/backend-for-frontend-endpoints/surfaces against the real source pages + route handlers.'
    : isInfra
      ? '- INFRA: compare CONTEXT.md\'s described resources/modules against the actual IaC files.'
      : '- Backend: compare CONTEXT.md tables against the models + migrations; endpoints against the routers/handlers; events against the producer/consumer code and any events manifest.'}
  Drifted = CONTEXT.md describes something the code no longer matches, OR the code added tables/endpoints/events/surfaces CONTEXT.md never mentions. If the repo has no domain code yet (scaffold/designed) or no CONTEXT.md, doc-vs-code is "fresh / n/a".

AXIS 2 — config-vs-baseline (your project's hygiene baseline / CI gates):
  ${isUI ? 'UI repo — check its CI gates against the project baseline for UI (lint/build/test present and blocking). If the project has no documented UI baseline, mark "compliant (UI, n/a)".'
    : isInfra ? 'INFRA repo — check its CI gates (validate / fmt-check) against the project baseline, or mark "compliant (infra, n/a)".'
    : 'Check this repo\'s CI workflow + project config against the project\'s documented hygiene baseline (e.g. type-check blocking not advisory, lint run on tests too, coverage gate single-sourced and precise — not duplicated/loosened on the command line). Drifted = any documented gate is loosened or missing. If the project documents no baseline, mark "compliant (no baseline documented)".'}

AXIS 3 — copy-vs-source (propagated files that diverged):
  Files that are meant to be BYTE-IDENTICAL across repos (commonly .claude/hooks/*.sh) should match their canonical source at the workspace-root ".claude/hooks/". If this repo has its own .claude/hooks/, note whether they match the root copies. Also flag any stale per-repo .claude/commands/ copies that duplicate the root commands (root is the single source of truth; a lingering per-repo copy is copy-drift). Drifted = a propagated file diverged from canonical, or a stale per-repo copy persists.

Return the structured object. Set anyDrift=true if ANY axis drifted; severity = worst axis (doc-vs-code on a repo with real tables = high; a stale per-repo command copy = low).`,
    { label: `drift:${r.name}`, phase: 'Scan', schema: DRIFT_SCHEMA, agentType: 'Explore' }
  )
}))).filter(Boolean)

phase('Synthesize')

const drifted = perRepo.filter((r) => r.anyDrift)
log(`Scan complete: ${drifted.length}/${perRepo.length} repos show drift on >=1 axis`)

const synthesis = await agent(
  `You are the lead drift auditor. Produce the consolidated DRIFT REPORT for this workspace from the per-repo findings below.

Structure the report:
1. DRIFT MATRIX — table: repo x {doc-vs-code, config-vs-baseline, copy-vs-source} with a one-word status each (ok / DRIFT) + severity.
2. HIGH-SEVERITY FIRST — every high/medium drift, with the specific stale item and the fix.
3. BY AXIS — group the findings: (a) doc-vs-code (which CONTEXT.md files are stale — the binding freshness rule), (b) config-vs-baseline (which repos violate the baseline — note these are fixable via the hygiene-fix-sweep workflow), (c) copy-vs-source (diverged hooks / stale per-repo command copies).
4. REMEDIATION — concrete next actions, cheapest first. Note which drift is mechanically fixable (config -> hygiene-fix-sweep) vs needs a dev-lead (doc-vs-code -> update CONTEXT.md in a PR).

Be honest and specific — cite repos. If a repo is clean, don't pad. This report is the honest mirror; its value is that it doesn't flatter.

Per-repo findings:
${JSON.stringify(perRepo, null, 2)}`,
  { label: 'synthesis', phase: 'Synthesize' }
)

return { source: manifest.source, perRepo, drifted: drifted.map((r) => r.repo), synthesis }
