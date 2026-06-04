# Resume Protocol — When You Are the Fresh Instance

You were invoked with something like: "Continue from .handoff/<file>" or "Continue from .handoff/dev-lead-2026-05-25T14-30-00.md".

This is the protocol. Skipping steps causes drift, redoing of work, or silent contradictions with the prior instance's decisions.

## Step 1 — Read the handoff file first

Before reading anything else. Before exploring the codebase. Before responding to the caller.

Why first: the handoff tells you what's already been decided, what's done, what to do next. Loading other context before this risks priming you with stale info or duplicating exploration the prior instance already did.

## Step 2 — Verify the claimed "Done" state

The prior instance's narrative is not evidence. Trust nothing.

For each item in "Done (verified)":
- Spot-check 1–2 files mentioned to confirm the change is actually present
- If a verification command was provided, run it — confirm the claimed state matches reality
- If anything is missing or different from the claim, flag it and ask the caller before proceeding

This step catches: aborted edits the prior instance thought went through, files reverted by lint hooks, race conditions in the prior session.

## Step 3 — Re-read only what you need

The handoff lists "Files touched this session." You don't need to re-read all of them. Read what's relevant to:
- The "In progress (interrupted)" items
- The "Not started" items at the top of priority order

Skip files that were only read-only context for completed work.

## Step 4 — Continue from "Resume instructions"

That's your new task. Don't redesign; the prior instance + the user already shaped the approach. Your job is to execute the next step, not to second-guess.

If the resume instructions contradict what you'd naturally do, **flag it to the caller before deviating**. Maybe the prior instance saw something you don't, or maybe the resume instructions are wrong — either way, the caller decides.

## Step 5 — Inherit the pipeline status

The handoff's "Pipeline status" tells you where the quality pipeline is:
- **not yet run** — when work is complete enough, you'll invoke `critic`
- **critic done** — pass to `fixer` next
- **fixer done** — pass to `auditor` next
- **needs auditor** — invoke `auditor`

Don't re-run earlier pipeline stages.

## Step 6 — You may checkpoint again

If you hit the triggers from [TRIGGERS.md](TRIGGERS.md) yourself, follow the same protocol, write a new `.handoff/<agent>-<timestamp>.md`. But see chain detection below.

## Chained handoff detection

If you read a handoff and notice it itself references a prior handoff in its "Original task" or "Decisions made" — that means this is **handoff #2 (or higher) on the same task**.

That's a signal: **the scope is too big for the current sizing**.

Your first action in this case:

1. Read both handoffs (yours and the one it references)
2. Return to the caller with:

```
Chained handoff detected (this is handoff #N for task "<original task>").

The work is too large for the current scoping. Continuing will likely produce a 3rd handoff.

Suggested split:
- Scope A: <smaller deliverable>
- Scope B: <smaller deliverable>
- Scope C: <smaller deliverable>

I have not started the resume. Awaiting your call: continue anyway, or split.
```

3. **Do not start the resume work until the caller confirms.** They may say "continue anyway" (in which case you proceed), or "split it" (in which case they re-dispatch you with one of the smaller scopes).

## What if the handoff is incomplete or malformed?

If a section is missing or the format is broken:
- Try to infer what you can from what's there
- Return to the caller noting what's unclear: "The handoff is missing the 'Resume instructions' section. I can read what's done, but I don't know where to pick up. Can you confirm: <your guess>?"
- Do not proceed on assumption

## What if the verification step fails?

If the claimed "Done" state is wrong (e.g. the prior instance said file X has feature Y, but X doesn't):
- Don't redo the prior work blindly — there may be a reason it isn't there (revert, hook, lint failure)
- Return to the caller: "The handoff claims X.y is implemented, but I don't see it in the file. Possible reasons: <list>. How should I proceed?"
- Wait for direction

The cost of asking is low. The cost of redoing or silently contradicting prior work is high.
