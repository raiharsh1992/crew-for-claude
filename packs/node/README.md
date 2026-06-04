# node pack — FUTURE (spec-only)

Placeholder pack for Node.js projects (npm / pnpm / yarn). **Not yet active** — no
commands or hooks. It exists so auto-discovery can report "detected node" against
a real pack id.

The package manager is resolved by lockfile: `pnpm-lock.yaml` → pnpm,
`yarn.lock` → yarn, `package-lock.json` → npm. Note that a `package.json` plus a
UI framework dependency makes a repo **class UI**, not SERVICE — the resolver
distinguishes them by shape.

To turn this into a working pack, follow ["Authoring a new pack"](../PACK-SPEC.md).
