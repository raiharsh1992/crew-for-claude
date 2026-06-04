# DETECT phase — reference

Read-only classification of what's on disk. Produces
`{ languages[], shape, candidateRepos[], gaps[] }`.

## Marker → language table

A directory containing **any** marker below is a candidate repo for that language.
Detection is by file presence, not content (content checks only refine class — see
scope.md).

| Marker file(s) | Language | Notes |
|---|---|---|
| `pom.xml` | java | Maven |
| `build.gradle`, `build.gradle.kts` | java | Gradle |
| `package.json` **plus** a lockfile (`pnpm-lock.yaml` / `yarn.lock` / `package-lock.json`) | node | Lockfile selects the package manager: pnpm-lock→pnpm, yarn.lock→yarn, package-lock.json→npm. A `package.json` with NO lockfile is a weak signal — record it but flag "no lockfile". |
| `pyproject.toml`, `setup.cfg`, `requirements.txt` | python | Any one suffices. |
| `go.mod` | go | |
| `Cargo.toml` | rust | |
| `*.tf` | infra | Class is forced to INFRA. |

## Multi-hit = polyglot

A single repo can match several markers (e.g. a Python service with a `*.tf`
deploy dir, or a Node UI inside a Java monorepo). Record the **set** of languages
for that scope — do **not** stop at the first match. The crew is polyglot by
design; dropping the second language is a silent coverage hole.

## Shape inference

Decide the workspace shape from git topology + marker placement:

- **single** — exactly one git root (`.git` at the workspace root, no nested
  repos), markers at or near that root. The simplest case.
- **monorepo** — one git root, but markers live in **subdirectories** (e.g.
  `services/billing/pom.xml`, `apps/web/package.json`). One checkout, many
  buildable units. Each marked subdir becomes a repo entry with a shared git
  root.
- **multi-repo** — **multiple** git roots. Signals, any of:
  - several `.git` directories (sibling repos each independently cloned),
  - a `.gitmodules` superproject (the workspace is a parent with submodules),
  - sibling directories each containing their own `.git`.
  Each git root (or submodule) is its own repo entry.

When signals conflict (e.g. a `.gitmodules` AND markers in subdirs of the parent),
prefer **multi-repo** if there are real nested git roots; otherwise monorepo. When
unsure, report both candidates and ask.

## Gaps — record, never drop

After classifying, cross-reference each detected language against installed packs:

- `python` → `python-fastapi` pack is **active** → covered.
- `java` / `node` / `go` → packs are **spec-only** → **gap**: "detected
  `<language>` in `<path>`, pack `<id>` is spec-only — no verify commands will be
  installed for it."
- `rust` (or any language with no pack at all) → **gap**: "detected `<language>`,
  no pack exists."

Gaps go into the `gaps[]` output and MUST appear in the final report. A detected-
but-unsupported language is surfaced, never silently omitted — the user decides
whether to author a pack (see `packs/PACK-SPEC.md`) or proceed with partial
coverage.

## Output shape

```jsonc
{
  "languages": ["python", "node"],          // the union across the workspace
  "shape": "multi-repo",                     // single | monorepo | multi-repo
  "candidateRepos": [
    { "path": "api",  "languages": ["python"], "gitRoot": "api"  },
    { "path": "web",  "languages": ["node"],   "gitRoot": "web"  }
  ],
  "gaps": [
    { "language": "node", "path": "web", "reason": "pack 'node' is spec-only" }
  ]
}
```
