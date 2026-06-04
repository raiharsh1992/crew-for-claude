---
name: remember
description: Capture a durable lesson, decision, correction, or preference so the crew never has to re-learn it. Routes each fact to the right home — version-controlled rules (CLAUDE.md / CONTEXT.md), an ADR (a load-bearing decision), or agent memory (.claude/memory/, for taste/preferences/working-style). Use when the user corrects you, locks a decision, states a preference, or says "remember this" / "don't do that again" / "from now on". Also the write-back half of the learning loop the Stop hook surfaces.
---

# Remember — the learning loop's write-back

This is how the crew **grows**. Forward flow is you → agents → code. This skill is the
**back-flow**: a lesson learned in one session becomes a rule every future session reads
*for free*, with no token cost and no human re-explaining it.

The discipline is one rule above all: **propose, never silently auto-write.** A fact going
into a version-controlled file (`CLAUDE.md`, `CONTEXT.md`, an ADR) changes how every future
agent behaves — that is exactly the kind of edit a human must see and approve. You draft it,
you show it, you write it only on a yes.

---

## Phase 1 — Classify the fact (where does it belong?)

Every learnable moment is one of five kinds. The kind decides the home. **Get this right —
a preference written into `CLAUDE.md` as if it were a rule pollutes the rulebook; a real
architectural invariant left in ephemeral memory is lost on the next `/clear`.**

| Kind | Looks like | Home | Tracked in git? |
|---|---|---|---|
| **Rule / constraint** | "Never call the API client directly — always go through the gateway." | the relevant `CLAUDE.md` (root or module) | ✅ yes |
| **Orientation / fact** | "The billing tables live in `svc-ledger`, not `svc-orders`." | the relevant `CONTEXT.md` | ✅ yes |
| **Load-bearing decision** | "We chose Postgres LISTEN/NOTIFY over a broker because…" | a new ADR under the configured `adrDir` | ✅ yes |
| **Preference / taste / working-style** | "I like terse PR descriptions." / "Always show me the diff before committing." | `.claude/memory/<slug>.md` + a line in `.claude/memory/MEMORY.md` | ⚪ optional (see gitignore stance) |
| **Correction (one-off)** | "That import was wrong, it's `foo` not `bar`." | nowhere — it's already fixed; only persist if it reveals a *pattern* | — |

> **The test for "is this durable?"** Ask: *would a fresh agent, six sessions from now,
> behave better for knowing this?* If yes → persist it. If it's only true for this one task,
> it's not a memory — it's just this turn's context. Don't clutter the rulebook with it.

If a fact spans two homes (a decision that also implies a rule), record the decision in the
ADR and add the one-line *rule* to `CLAUDE.md` that points at it: `<rule> (see ADR-NNNN)`.

---

## Phase 2 — Draft, show, confirm

For the chosen home, draft the **exact** text you'd add and show it to the user before
writing. Keep it to the smallest durable statement — a rule is one or two sentences, not a
paragraph.

- **Rule / orientation** → show the exact lines you'd insert and *where* (which file, which
  section). On confirm, `Edit` them in. Match the surrounding format — these files have
  structure (tables, numbered invariants); don't append loose prose.
- **Decision** → draft the ADR from `templates/ADR.template.md`, fill Context / Decision /
  Options / Consequences from the conversation, propose the next ADR number (scan `adrDir`).
  On confirm, `Write` it and add the one-line rule to `CLAUDE.md` if one is implied.
- **Preference / working-style** → write the memory file directly (low-stakes, see format
  below) **but still say what you saved** in one line so it's never a silent edit.

Resolve `adrDir` / `CONTEXT.md` location from `.claude/skills-config.json` (`docs` block). If
the kit isn't installed yet, fall back to `docs/adr/` and root `CONTEXT.md`, and mention it.

---

## Phase 3 — Memory file format (for preference/taste/working-style)

Memory lives in `.claude/memory/`. Each fact is **one file, one fact**, with frontmatter so
the relevance of a recalled memory can be judged at a glance:

```markdown
---
name: <short-kebab-case-slug>
description: <one-line summary — used to decide relevance during recall>
metadata:
  type: user | feedback | project | reference
---

<the fact. For feedback/project, follow with **Why:** and **How to apply:** lines.
Link related memories with [[their-name]].>
```

Type meanings:
- **user** — who the user is (role, expertise, standing preferences).
- **feedback** — guidance on *how you should work* (a correction or a confirmed approach).
  Always include the **why** — a rule without its reason gets misapplied.
- **project** — ongoing work/goals/constraints not derivable from code or git. Convert
  relative dates to absolute ("next Friday" → the date).
- **reference** — pointers to external resources (URLs, dashboards, tickets).

After writing the file, add **one** pointer line to `.claude/memory/MEMORY.md` (the index a
session reads at start — via the `CLAUDE.md` "read the memory index" instruction):

```
- [Title](slug.md) — one-line hook
```

`MEMORY.md` holds *only* index lines — never memory content. Before saving, check for an
existing file that already covers it and **update that one** rather than duplicating. Delete
a memory that turns out to be wrong.

**Don't save what the repo already records** — code structure, a fix already in git, a CLAUDE.md
rule. If asked to "remember" one of those, ask what was *non-obvious* about it and save *that*.

---

## Phase 4 — Close the loop

After writing, state in one line what was persisted and where, e.g.
`Saved: rule "always go through the gateway" → svc-orders/CLAUDE.md §Architecture.`
That line is the receipt — it makes the back-flow visible instead of magic-and-silent.

---

## How this composes with the rest of the crew

- The **Stop hook** (`suggest-memory.sh`) watches sessions for learnable moments — a
  correction, a "from now on", a locked decision — and surfaces a nudge to run this skill.
  It never writes; it only *notices*. This skill is the write half.
- **Leads** that get corrected mid-slice should invoke this for anything durable, so the
  lesson outlives their context window (and survives `/context-handoff`).
- **`/install`** seeds an empty `.claude/memory/MEMORY.md` and the gitignore stance so this
  skill has a home from session one.
