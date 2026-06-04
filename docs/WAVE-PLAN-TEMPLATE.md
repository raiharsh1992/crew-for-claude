# Wave plan template

How to turn "build this product" into a sequence the crew can actually execute. A
**wave** is a set of slices that can ship together; a **slice** is one dev-lead's
end-to-end unit of work (one feature branch → one PR → one merge).

The model is **tracer-bullet vertical slices**: each slice cuts through every layer it
needs (data → logic → API → UI) and ships something demonstrable, rather than building
all of one layer before any of the next. Thin and working beats thick and half-wired.

---

## The shape of a plan

```
Release v1
├── Wave 0 — Backbone (must land before anything depends on it)
│     └── Slice: <the thing everything else needs>
├── Wave 1 — <capability>      (slices here can run in parallel)
│     ├── Slice A  ──┐
│     └── Slice B  ──┘  independent → parallel dev-leads
├── Wave 2 — <capability>      (depends on Wave 1)
│     └── Slice C
└── Wave 3 — <capability>
      └── Slice D
```

Rules of thumb:
- **Order waves by dependency, not by priority.** A high-priority slice that depends on
  an unbuilt backbone still waits.
- **Within a wave, maximize parallelism.** Two slices with no shared files = two
  concurrent dev-leads under the `lead-agent`.
- **End each wave with a verification pass** (a test-lead, or a real end-to-end run)
  before opening the next. Unverified parallelism is where time leaks (habit #3).

---

## Per-slice spec

For each slice, write this down *before* dispatching a dev-lead. Ten minutes here saves
hours of wrong-direction build (habit #1).

```markdown
### Slice: <name>

**Goal (one sentence):** <what exists after this slice that didn't before>

**Wave / order:** <wave number; what it depends on; what depends on it>

**Layers touched:** data │ logic │ API │ UI │ infra   (cross out what doesn't apply)

**Gate tier:** FULL | LEAN — <reason; default FULL, any doubt = FULL>

**Acceptance criteria:**
- [ ] <demonstrable outcome 1>
- [ ] <demonstrable outcome 2>

**Cross-module contracts:** <events/APIs/schema this slice produces or consumes>

**Out of scope (explicit):** <what this slice deliberately does NOT do — deferred to ___>

**Estimated commits:** <rough count — drives solo-vs-delegate decisions>
```

---

## Dispatching a wave

1. The `lead-agent` reads the wave's slice specs.
2. For each **independent** slice, dispatch a `dev-lead` (or `design-lead`/`devops-lead`)
   with the slice spec as the brief. Run them in parallel.
3. For **dependent** slices, dispatch in order — the downstream lead consumes the
   upstream's merged contract.
4. Each lead runs its own quality pipeline and stops at the human-merge gate.
5. **You merge**, in dependency order.
6. After the wave merges, run the verification pass.
7. Update `CONTEXT.md` for anything whose contracts changed (freshness rule).
8. Open the next wave.

---

## A worked micro-example

```
Release: "user can book an appointment"

Wave 0 — Backbone
  └── Slice: appointment data model + state machine        (FULL — new schema + state)

Wave 1 — Booking
  ├── Slice: create-appointment endpoint                   (FULL — new write endpoint)
  └── Slice: availability calendar (read-only)             (LEAN — GET, existing patterns)
                                                            ↑ these two run in parallel

Wave 2 — Confirmation
  └── Slice: booking-confirmed notification + UI banner    (FULL — cross-module event)
```

Wave 0 must land first (everything reads its schema). Within Wave 1 the two slices share
no files, so two dev-leads run concurrently. Wave 2's notification consumes Wave 1's
"appointment created" event, so it waits.

---

## When to re-plan

- A slice's auditor keeps rejecting → the slice is too big. Split it.
- A dev-lead hits a second context handoff on one slice → too big. Split it.
- Two "independent" slices keep colliding on the same file → they're actually one slice,
  or there's a missing backbone slice underneath both. Extract it into an earlier wave.

Re-planning between waves is cheap. Re-planning mid-slice is expensive. Front-load it.
