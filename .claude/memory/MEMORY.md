# Memory index

This file is the **index of agent memory** for this workspace — one line per memory, no
memory content here. It is the recall surface for the learning loop: a session reads these
one-liners, and pulls the full file only when a hook line looks relevant to the task at hand.

> **It is not auto-loaded by the harness.** The mechanism that brings it into context is an
> explicit instruction in the project `CLAUDE.md` ("at session start, read the memory index")
> — see `templates/CLAUDE.md.template`. Without that instruction the index is inert, so keep
> it in `CLAUDE.md` when you install the crew.

Memories are written by the **`/remember`** skill (the write half of the learning loop) and
suggested by the **`suggest-memory.sh`** Stop hook (the sensor half). See
[.claude/skills/remember/SKILL.md](../skills/remember/SKILL.md) for the format and routing.

## How to use this index

- **One line per memory:** `- [Title](slug.md) — one-line hook`. Nothing else.
- Keep the hooks specific enough that future-you can judge relevance at a glance.
- When a memory is deleted (it turned out wrong / stale), delete its line here too.
- Group under the headings below as the list grows; keep the most load-bearing at top.

> **Rotation discipline (so this index never bloats).** This file is loaded every session,
> so it must stay lean. Rules: keep **durable** entries (identity, binding rules, ideology,
> current project state); when a dated checkpoint line is **superseded**, replace it rather
> than stacking a new one beside it; if session-history lines ever accumulate, move the stale
> ones into a `MEMORY-ARCHIVE.md` and keep only the current resume-point here. The
> `guard-memory-size.sh` hook warns as the index nears ~24KB — treat that warning as the cue
> to rotate. Prefer **few durable files** over **many dated ones**.

## Sharing stance (what's committed vs local)

- **Committed** (`<slug>.md`): team-shareable facts — project conventions, decisions,
  domain orientation everyone on the repo should inherit. These travel with the repo.
- **Local-only** (`<slug>.local.md`): personal working-style and preferences that
  shouldn't bind teammates. These are gitignored (see root `.gitignore`).

---

<!-- Memories are added here by /remember and /install. Each entry is one line:
     - [Title](slug.md) — one-line hook describing when this memory is relevant. -->

*Empty for now — it fills as the crew learns. The first `/remember` writes here.*
