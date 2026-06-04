// repos.config.example.js — CONSUMER-FILLABLE repo manifest for this workspace.
//
// Copy this file to `.claude/workflows/repos.config.js` and fill in your repos,
// OR delete the example entries and rely on auto-discovery (see RESOLVER.md). The
// installer (`/install`) generates a starter `repos.config.js` for you from what
// it detects on disk; this example documents the shape so you can hand-edit it.
//
// ────────────────────────────────────────────────────────────────────────────
// WHY THIS FILE EXISTS
// Workflows must not hardcode a repo list — that drifts the moment a repo is
// added and silently omitted from a sweep. Instead, every workflow resolves its
// repo universe through a fixed precedence (RESOLVER.md): explicit args →
// THIS file → .gitmodules → marker-based auto-discovery. This file is the
// highest-fidelity rung: when present and filled, it is authoritative.
//
// LANGUAGE-AGNOSTIC BY DESIGN
// The `class` is a GENERIC role, NOT a tech stack — it decides which verify
// COMMAND BUCKET a repo uses, not what language it's in. Language is a separate
// field. A Java service and a Python service are both class SERVICE; the
// language field (java / python / …) selects the actual verify/lint/test
// commands from .claude/skills-config.json. See that file's `verify` block.
//
//   CLASS      What it means (how you verify it)
//   ───────    ─────────────────────────────────────────────────────────────
//   SERVICE    A deployable backend/app service. Runs the full verify chain
//              (lint + test + coverage) for its language.
//   LIBRARY    A shared package / SDK / module consumed by others. Verify =
//              lint + test (typically no service-run, no coverage-floor gate by
//              default — override per-repo if you want one).
//   UI         A frontend app. Verify = lint + build + test (per the node
//              defaults, or whatever its language resolves to).
//   INFRA      Infrastructure-as-code (terraform / pulumi / …). Verify = the
//              infra defaults (validate + fmt-check). Never language-verified.
//
// SHAPE-AGNOSTIC
// `path` is relative to the workspace root. For a MONOREPO, point multiple
// entries at subdirectories of one git root. For a MULTI-REPO workspace, each
// entry is its own git root (a sibling dir or a submodule). For a SINGLE repo,
// you may not need this file at all — auto-discovery handles it.

/** @typedef {('SERVICE'|'LIBRARY'|'UI'|'INFRA')} RepoClass */

/**
 * @typedef {Object} RepoEntry
 * @property {string}    name      Stable identifier, used in workflow args & by-repo overrides.
 * @property {string}    path      Path relative to the workspace root (a dir or '.').
 * @property {RepoClass} class     Generic verify-bucket role (see header).
 * @property {string}   [language] Optional explicit language (java|node|python|go|infra|…).
 *                                 If omitted, the installer / resolver infers it from file
 *                                 markers in `path`. Set it to pin the choice.
 */

/** @type {RepoEntry[]} */
export const REPOS = [
  // ── EXAMPLE ENTRIES — replace these with your repos, or delete and rely on
  //    auto-discovery. They are illustrative only; nothing here is real.

  // A backend service in a multi-repo workspace (its own git root):
  { name: 'example-api',     path: 'example-api',     class: 'SERVICE', language: 'python' },

  // A shared library consumed by other repos:
  { name: 'example-core',    path: 'example-core',    class: 'LIBRARY', language: 'python' },

  // A frontend app:
  { name: 'example-web',     path: 'example-web',     class: 'UI',      language: 'node' },

  // Infrastructure-as-code:
  { name: 'example-infra',   path: 'example-infra',   class: 'INFRA' },

  // A monorepo example: several services under one git root. Note the shared
  // path prefix — these are subdirectories of a single git checkout, not
  // separate clones.
  // { name: 'billing',  path: 'services/billing',  class: 'SERVICE', language: 'java' },
  // { name: 'catalog',  path: 'services/catalog',  class: 'SERVICE', language: 'java' },
  // { name: 'web',      path: 'apps/web',          class: 'UI',      language: 'node' },
]

// Convenience views (optional — workflows may compute these themselves).
export const SERVICES  = REPOS.filter((r) => r.class === 'SERVICE')
export const LIBRARIES = REPOS.filter((r) => r.class === 'LIBRARY')
export const UIS       = REPOS.filter((r) => r.class === 'UI')
export const INFRA     = REPOS.filter((r) => r.class === 'INFRA')
export const ALL_REPOS = REPOS
