---
name: orient
description: Generate a real, accurate CONTEXT.md for a repo from its actual code — the orientation half of the context contract — so a fresh agent (or human) can navigate it in minutes. Reads the code, extracts the data model / public surface / module map / domain glossary, drafts CONTEXT.md from the template, and PROPOSES it before writing. Use on first install of an existing repo, when CONTEXT.md is missing or still the untouched template, or when the user says "orient this repo" / "generate a CONTEXT.md" / "what is this codebase". The actuator half of the onboarding loop (Loop 1).
---

# Orient — turn an existing repo into an oriented one

This is the **wow-moment** of the onboarding loop: point the crew at a repo it has never
seen and, minutes later, it *understands* it — a real `CONTEXT.md` with the data model, the
public surface, the module map, and a domain glossary, generated from the **actual code**,
not guessed.

`CONTEXT.md` is the single highest-leverage artifact in the whole kit (see
[docs/THE-METHOD.md](../../docs/THE-METHOD.md) → "the context contract"): it's what lets a
fresh session orient in minutes instead of re-deriving the project. This skill produces a
*real* one. The discipline, as everywhere in this kit: **draft, show, write on confirm** —
never silently drop a generated file into the repo.

---

## Phase 1 — Read the code (don't guess)

The output is only as good as the read. Be thorough and **ground every claim in a file**.

1. **Map the shape.** Entry points, top-level packages/modules, the build manifest
   (`pyproject.toml` / `package.json` / `pom.xml` / `go.mod` / `Cargo.toml`). For an
   unfamiliar or large area, invoke **`/survey-code`** to get a module/caller map first.
2. **Find the data model.** Migrations, ORM models, schema files, type definitions. Extract
   the *key entities*, what each owns, and their relationships — the shape and the *why*,
   not a schema dump.
3. **Find the public surface.** Routes/controllers (HTTP), CLI commands, published
   events/topics, exported library API. Note auth/access requirements where visible.
4. **Find the domain language.** The recurring nouns in the code — the terms a newcomer
   would have to learn. These become the glossary. Prefer the codebase's own words.
5. **Find the one file to read first** — the single file that best reveals how the repo
   works (a reference endpoint, the core model, the main entry point).
6. **Note cross-module contracts** — what this repo depends on / is depended on by, and the
   shape of that dependency (an event, an ID reference, an API call).

If something is genuinely unclear from the code, **mark it `<TODO: confirm with maintainer>`**
in the draft rather than inventing it. An honest gap beats a confident fabrication — the
whole point of `CONTEXT.md` is that it's *trustworthy*.

---

## Phase 2 — Draft from the template

Fill [templates/CONTEXT.md.template](../../templates/CONTEXT.md.template) section by section
from what Phase 1 found:

- **What this repo owns** — the responsibility boundary, and what it explicitly does NOT own.
- **The one file to read first** — with the path and one line on why.
- **Data model** — the entity table (Entity / Owns / Key relationships), grounded in the
  schema files; point at the schema, explain the shape.
- **Endpoints / public surface** — the surface table, grouped by resource, with access notes.
- **Cross-module contracts** — the dependency shapes.
- **Domain glossary** — the terms, each defined in one line, in the codebase's own vocabulary.

Keep it **dense and true**. Every table row should be checkable against a file. This is a
navigation aid, not prose — bias to tables and file pointers over paragraphs.

For a **multi-repo workspace**, generate **one `CONTEXT.md` per repo** (each at its repo
root), plus — if there's a workspace root — a top-level `CONTEXT.md` that is the glossary +
"which repo owns what" map. Run the repos in sequence; each is its own draft-show-confirm.

---

## Phase 3 — Propose, then write

Show the drafted `CONTEXT.md` (the whole file for a small repo; the section headers + the
data-model and surface tables for a large one) and ask for confirmation before writing.

- **Never overwrite an authored `CONTEXT.md`.** If one exists and is *not* the untouched
  template, do NOT clobber it — show what you'd add/correct and let the user merge, or offer
  to refresh only the stale sections. Only a missing file or a recognizably-untouched
  template gets written wholesale.
- On confirm, `Write` the file(s). Then print a one-line receipt per file:
  `Wrote CONTEXT.md for <repo> — N entities, M endpoints, K glossary terms.`

---

## Phase 4 — Close the loop into the next step

After writing, point at the natural next action:
- If the crew isn't installed yet → suggest `/install --dry-run` to wire hooks + verify map.
- If it is installed → the repo is now oriented; suggest the first slice or a wave plan.
- Remind: **keep it fresh** — any change that alters tables/endpoints/contracts updates
  `CONTEXT.md` in the *same* change (the freshness rule). The drift sensor (Loop 3) will
  nudge if it goes stale.

---

## How this composes

- **Onboarding sensor** (`onboard.sh`, SessionStart) surfaces the offer to run this on a
  fresh existing repo. This skill is the actuator it points to.
- **`/survey-code`** is the read primitive for Phase 1 on unfamiliar/large code.
- **`/install`** wires the machinery; `/orient` fills the context contract. Run orient
  before or right after install — orientation makes every later agent sharper.
- **`drift-audit`** / the freshness sensor keep what this generates honest over time.
