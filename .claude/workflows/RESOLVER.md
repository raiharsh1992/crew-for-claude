# The Resolver — how a workflow finds its repo universe

A workflow that sweeps "every repo" must first answer: **which repos?** Hardcoding
the list rots — a repo added next week is silently skipped. The Resolver is the
fixed contract every workflow uses to answer that question the same way, so the
answer is correct as the workspace grows and identical across workflows.

This document is the **binding contract**. Workflows reference it; they do not
re-invent resolution.

---

## The resolution precedence (highest fidelity first)

A workflow resolves its repo universe by walking this ladder and **stopping at the
first rung that yields a non-empty result**:

1. **Explicit `args`** — the caller named the repos directly
   (`Workflow({ name, args: { repos: ['billing','web'] } })`). Most specific;
   always wins. Use it to scope a sweep to a subset.

2. **`.claude/workflows/repos.config.js`** — the consumer-filled manifest
   (shape in [`repos.config.example.js`](repos.config.example.js)). When present
   and non-empty, it is authoritative: it carries the stable `name`, the `path`,
   the generic `class` (SERVICE/LIBRARY/UI/INFRA), and optional pinned
   `language`. This is the rung you want filled for a stable workspace.

3. **`.gitmodules`** — if the workspace is a superproject with submodules and no
   `repos.config.js`, each submodule path is a repo. Class/language are then
   inferred by marker detection (rung 4's detector) on each submodule path.

4. **Marker-based auto-discovery** — the fallback that always works. Walk the
   workspace for project markers and treat each marked directory as a repo:

   | Marker(s) | Inferred language |
   |---|---|
   | `pom.xml`, `build.gradle`, `build.gradle.kts` | java |
   | `package.json` + a lockfile (`pnpm-lock.yaml` / `yarn.lock` / `package-lock.json`) | node |
   | `pyproject.toml`, `setup.cfg`, `requirements.txt` | python |
   | `go.mod` | go |
   | `Cargo.toml` | rust |
   | `*.tf` | infra (class INFRA) |

   Class is inferred from shape: a marked dir that is a UI framework (Next/Vite/
   etc. in `package.json`) → UI; `*.tf` → INFRA; a package-only repo (library
   manifest, no service entrypoint) → LIBRARY; otherwise → SERVICE. A detected
   **language with no installed pack** is recorded as a **gap** (reported), not
   dropped — so the user knows coverage is partial rather than being silently
   misled.

> Rungs 2–4 are not mutually exclusive in spirit: `repos.config.js` may be
> *partial*, listing some repos and leaving others to auto-discovery. A workflow
> that wants belt-and-suspenders coverage unions rung 2 with rung 4 and dedupes
> by path. The default, simplest behavior is "first non-empty rung wins"; a
> workflow that needs the union says so explicitly.

---

## The Resolve-phase discovery agent (the pattern workflows MUST use)

**Workflow orchestration scripts cannot read the filesystem directly.** They run
in an isolated JS context with no module loader and no `fs` — they fan work out to
agents and collect structured results. So a workflow cannot itself walk the tree
for `pom.xml` or parse `.gitmodules`.

The pattern that resolves this: **every sweeping workflow opens with a Resolve
phase that spawns ONE short-lived discovery agent.** That agent does have file
and shell access. Its entire job:

1. Check `args.repos` — if the caller named repos, echo them back, done.
2. Else read `.claude/workflows/repos.config.js` — if present and non-empty,
   return its `REPOS` array (resolving each `path` against the workspace root).
3. Else read `.gitmodules` — if it has submodules, list their paths, then run
   the marker detector on each to fill in class/language.
4. Else run marker auto-discovery across the workspace (the table above).
5. Return a **single structured manifest**: an array of
   `{ name, path, class, language }` plus a `gaps[]` list (detected languages
   with no pack) and a `source` field naming which rung produced the result.

The workflow then fans its real work (verify / migrate / audit / …) across that
manifest. Because discovery is one cheap agent at the front, the expensive
parallel phase always operates on a correct, current universe — and the manifest
is logged, so every run records exactly which repos it touched and why.

### Sketch (illustrative — not a runnable file)

```
// Inside a workflow's orchestration:
const manifest = await resolvePhase({
  // The discovery agent's instructions, in order of precedence:
  //   1. honor args.repos if given
  //   2. else parse repos.config.js
  //   3. else parse .gitmodules + marker-detect each submodule
  //   4. else marker-auto-discover the workspace
  // Return { repos:[{name,path,class,language}], gaps:[...], source:'repos.config' }
  args,
})

if (manifest.gaps.length) {
  // Surface, don't drop: "detected go in ./payments but no go pack installed"
}

await parallel(manifest.repos.map((r) => verifyRepo(r)))  // the real work
```

---

## Contract summary (what every workflow guarantees)

- Resolution **always** goes args → `repos.config.js` → `.gitmodules` →
  auto-discovery, in that order, via a Resolve-phase discovery agent.
- The `class` selects the verify **bucket**; the `language` selects the actual
  **commands** from `.claude/skills-config.json`. The two are orthogonal — this
  is what makes the framework language- and shape-agnostic.
- A detected language with no pack is a **reported gap**, never a silent drop.
- The manifest (repos touched + `source` rung + gaps) is logged on every run.
