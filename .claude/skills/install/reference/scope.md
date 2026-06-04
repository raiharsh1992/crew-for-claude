# SCOPE phase — reference

Resolve **which repos** the crew manages (configure-in-place only in v1), and
assign each a `class` + `language`. Output: the resolved repo manifest + the
precedence rung that produced it.

## Precedence (binding — from RESOLVER.md)

Walk these in order; stop at the first that yields a non-empty set:

1. **`args.repos`** (`--repos a,b,c`) — caller named them. Most specific. When
   given, skip discovery and just resolve names → paths against the workspace.
2. **`.claude/workflows/repos.config.js`** — read its `REPOS` array. Authoritative
   when present and non-empty. Resolve each `path` against the workspace root.
3. **`.gitmodules`** — each submodule path is a repo; run marker detection
   (DETECT) on each to fill class/language.
4. **Marker auto-discovery** — the DETECT candidates become the manifest.

Default behavior is **first non-empty rung wins**. If the user asks for full
coverage, union rung 2 (config) with rung 4 (discovery) and dedupe by path —
useful when `repos.config.js` is partial.

## Assigning `class` (the generic verify bucket)

`class` is orthogonal to language — it picks the verify **bucket**, not the
commands. Infer it per repo:

- **INFRA** — the repo's markers are `*.tf` (or other IaC). Forced INFRA.
- **UI** — `package.json` declares a frontend framework (Next.js, Vite, React,
  Vue, Svelte, Angular, etc.) as a dependency. A node repo that builds a UI.
- **LIBRARY** — a package manifest with **no** service/app entrypoint: a published
  package (`pyproject.toml` with no app server, a `package.json` with `"main"`/
  `"exports"` and no framework, a Go module that's a library, etc.). Consumed by
  others.
- **SERVICE** — everything else with a buildable backend/app entrypoint. The
  default when shape is ambiguous and the pack's `classHint` is SERVICE.

When inference is genuinely ambiguous, fall back to the matching pack's
`classHint`, then to SERVICE, and note the assumption in the report.

## Assigning `language`

- If `repos.config.js` pinned a `language`, use it.
- Else use the DETECT result. For a multi-hit (polyglot) repo, pick the
  **primary** language by the repo's class (a UI → node; a service whose markers
  are mostly python → python) and record the others as secondary in the report.
- A language with no active pack still gets recorded — it becomes a **gap** (see
  detect.md), and its `verify.byRepo` entry is written with the language but no
  resolved commands until a pack exists.

## v1 boundary — state it when relevant

This phase resolves **only repos already on disk**. Two modes are **documented
fast-follow, NOT in v1**:

- **clone-into-workspace** — given a list of remote URLs, clone then configure.
- **new-workspace** — scaffold an empty workspace + first repo, then configure.

If asked for either, name it as planned, and offer configure-in-place for what's
present. Do not improvise a clone/scaffold flow.

## Output shape

```jsonc
{
  "source": "repos.config",   // which rung produced this: args | repos.config | gitmodules | auto-discovery
  "repos": [
    { "name": "api", "path": "api", "class": "SERVICE", "language": "python" },
    { "name": "web", "path": "web", "class": "UI",      "language": "node"   }
  ],
  "assumptions": [ "web: class inferred UI from next dependency" ]
}
```
