export const meta = {
  name: 'build-status-audit',
  description: 'Ground-truth audit across the workspace: per-repo what is BUILT (code+tests+CI) vs DESIGNED (design/spec docs only) vs PLANNED (stub only), to verify a "design locked" claim before spinning up design + build leads.',
  whenToUse: 'Before kicking off a build phase / dispatching leads, when the plan docs claim "design is locked" and you want code-grounded truth, or to reconcile what is actually built vs documented across all repos.',
  phases: [
    { title: 'Resolve', detail: 'one discovery agent classifies the repo universe (RESOLVER.md)' },
    { title: 'Survey', detail: 'one Explore agent per repo reports build vs design vs plan' },
    { title: 'Synthesize', detail: 'merge into a single status matrix + readiness verdict' },
  ],
}

// ── Resolve the repo universe (RESOLVER.md) — NO hardcoded repo arrays. ──
// The orchestration script cannot read the filesystem; a discovery agent does
// it, honoring args.repos -> repos.config.js -> .gitmodules -> auto-discovery.
const RESOLVE_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['repos', 'source'],
  properties: {
    source: { type: 'string', description: 'which rung produced the list: args | repos.config | gitmodules | auto-discovery' },
    repos: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['name', 'path', 'class'],
        properties: {
          name: { type: 'string' },
          path: { type: 'string', description: 'path relative to the workspace root' },
          class: { type: 'string', enum: ['SERVICE', 'LIBRARY', 'UI', 'INFRA'] },
          language: { type: 'string', description: 'java|node|python|go|infra|… or "" if unknown' },
        },
      },
    },
    gaps: { type: 'array', items: { type: 'string' }, description: 'detected languages with no installed pack' },
  },
}

phase('Resolve')
const manifest = await agent(
  `You are the Resolve-phase discovery agent. Determine this workspace's repo universe per .claude/workflows/RESOLVER.md, walking the precedence ladder and stopping at the first non-empty rung:
1. If args.repos was provided (${args && args.repos ? JSON.stringify(args.repos) : 'none'}), use exactly those.
2. Else read .claude/workflows/repos.config.js — if present and non-empty, return its REPOS (resolve each path against the workspace root).
3. Else read .gitmodules — list submodule paths, then marker-detect class/language on each.
4. Else marker-auto-discover the workspace (pom.xml/build.gradle->java, package.json+lockfile->node, pyproject.toml/setup.cfg/requirements.txt->python, go.mod->go, *.tf->infra/INFRA). Infer class from shape (UI framework->UI, *.tf->INFRA, package-only->LIBRARY, else SERVICE).
Return the structured manifest: repos[{name,path,class,language}], a gaps[] list (detected languages with no pack), and the source rung. Read-only — discover, do not modify.`,
  { label: 'resolve', phase: 'Resolve', schema: RESOLVE_SCHEMA, agentType: 'Explore' }
)

const repos = (manifest && manifest.repos) || []
log(`Resolve complete: ${repos.length} repos via ${manifest && manifest.source}${manifest && manifest.gaps && manifest.gaps.length ? ` — gaps: ${manifest.gaps.join(', ')}` : ''}`)
if (repos.length === 0) {
  return { error: 'Resolve found no repos. Fill .claude/workflows/repos.config.js or run from a workspace with project markers.', manifest }
}

const REPO_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['repo', 'status', 'evidence', 'designDocs', 'gaps'],
  properties: {
    repo: { type: 'string' },
    status: { type: 'string', enum: ['BUILT', 'PARTIAL', 'DESIGNED', 'PLANNED', 'SCAFFOLD', 'EMPTY'] },
    statusReason: { type: 'string', description: 'one line justifying the status enum' },
    evidence: {
      type: 'object',
      additionalProperties: false,
      required: ['hasModels', 'hasRouters', 'hasMigrations', 'hasTests', 'hasCI', 'approxSourceFiles'],
      properties: {
        hasModels: { type: 'boolean' },
        hasRouters: { type: 'boolean' },
        hasMigrations: { type: 'boolean' },
        hasTests: { type: 'boolean' },
        hasCI: { type: 'boolean' },
        approxSourceFiles: { type: 'number', description: 'count of non-boilerplate source files, excluding scaffold/template boilerplate' },
        latestRelevantCommit: { type: 'string', description: 'short hash + subject of most recent substantive commit, or "n/a"' },
      },
    },
    designDocs: {
      type: 'array',
      description: 'BRIEF-*.md / DESIGN-*.md / spec / api.yaml etc found in the repo, with one-line note on completeness',
      items: { type: 'string' },
    },
    builtSurfaces: { type: 'array', items: { type: 'string' }, description: 'concrete endpoints/pages/tables/modules actually implemented in code' },
    gaps: { type: 'array', items: { type: 'string' }, description: 'designed-but-not-built, or plan-only, gaps' },
  },
}

phase('Survey')

async function auditRepo(r) {
  const isUI = r.class === 'UI'
  const prompt = `You are auditing ONE repository in this workspace. The workspace root is the directory you are launched in. Audit ONLY this repo at path: "${r.path}" (name "${r.name}", class ${r.class}${r.language ? `, language ${r.language}` : ''}).

Your job: determine the TRUE build status from the CODE and GIT, not from plan docs. Plan docs lead reality; code is truth.

Do this:
1. List the repo's top-level structure and ${isUI ? 'its UI source tree (pages/routes, components)' : 'its application source tree (models, routers/handlers, services, schemas) and any migrations directory'}.
2. Count substantive source files (exclude scaffold/template boilerplate — a freshly-cloned template has a known baseline of empty wireframe files; only count files with real domain logic).
3. ${isUI
    ? 'Identify which actual pages/routes exist with real content vs scaffold placeholder. Note backend-for-frontend route handlers. Note if it is still "scaffold only" or has functional surfaces.'
    : 'Identify which routers/endpoints, models/tables, and migrations actually exist in code. A migration count beyond the initial baseline signals real schema.'}
4. Find any BRIEF-*.md, DESIGN-*.md, plan.md, CONTEXT.md, api spec, schema files in the repo. For each, note whether it is a full design pack or a stub.
5. Check for tests (test files present + roughly how many) and CI (a CI workflow file present, e.g. .github/workflows/).
6. Run a short git log on this repo to see recent substantive commits. Pick the most recent NON-trivial one.

Then assign a status:
- BUILT = real models+routers+migrations(beyond baseline)+tests+CI, recent feature commits. A working service/app.
- PARTIAL = some real domain code but incomplete (e.g. one phase done, later phases not).
- DESIGNED = BRIEF/DESIGN docs present and substantive, but little/no domain CODE beyond scaffold.
- PLANNED = only a plan.md stub, no design pack, no code.
- SCAFFOLD = freshly cloned template, no domain code, no design docs.
- EMPTY = essentially nothing.

Be skeptical and precise. Distinguish "design doc exists" from "code exists". Return the structured object.`
  return agent(prompt, { label: `audit:${r.name}`, phase: 'Survey', schema: REPO_SCHEMA, agentType: 'Explore' })
}

const results = (await parallel(repos.map((r) => () => auditRepo(r)))).filter(Boolean)

phase('Synthesize')

const synthesis = await agent(
  `You are the lead auditor. Below are per-repo build-status findings for this workspace (JSON array). Produce a synthesis.

The CONTEXT you must judge against: the project's plan docs may CLAIM the design + architecture phase is LOCKED and approved, with per-repo BRIEF/DESIGN docs and dev streams ready to pick up independently.

Your synthesis must answer, grounded ONLY in the per-repo evidence:
1. A STATUS MATRIX: each repo -> BUILT / PARTIAL / DESIGNED / PLANNED / SCAFFOLD, one-line evidence.
2. WHAT IS WHOLLY BUILT (code+tests+CI, working).
3. WHAT IS WHOLLY DESIGNED (BRIEF/DESIGN present, not yet built).
4. WHAT IS ONLY PLAN/BRIEF (stub-level, needs a full design pass).
5. VERDICT on any "design is locked" claim: is it TRUE (every in-scope repo has a complete design pack ready for build), PARTIALLY TRUE (some designed, some still plan-only), or OVERSTATED (docs ahead of reality)? Cite specific repos.
6. The DELTA for a build pass: what design/architecture work genuinely REMAINS vs is already done. Be concrete about which repos/surfaces still need design vs just need building.

Per-repo findings:
${JSON.stringify(results, null, 2)}`,
  { label: 'synthesis', phase: 'Synthesize' }
)

return { source: manifest.source, perRepo: results, synthesis }
