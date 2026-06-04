# Checkpoint Triggers — Full Reference

Two layers, by design: heuristic (catches the problem early at safe boundaries) and hard fallback (catches it late even mid-stream).

## Layer 0 — Context budget (the primary signal when you can see it)

If your harness surfaces your context-window usage (a percentage, a token count, or a "context low" warning), treat it as the **leading** checkpoint signal — it's a truer measure of degradation risk than the tool-call/edit proxies below.

- **At ≥55% context used:** arm the checkpoint. Do NOT hand off yet. Finish the **current slice / sub-task** to a safe boundary — last related edit done, file saved/parses, in-flight command completed, any uncommitted work either committed or explicitly noted in the handoff. THEN write the handoff and hand off.
- **At ≥70% context used:** treat as a hard fallback (see Layer 2) — stop at the next safe statement boundary and checkpoint even if the sub-task isn't fully done. Past this point, degradation risk outweighs the cost of an early handoff.

The rule is **budget + safe boundary**, never an unconditional flush at an arbitrary %. Handing off mid-edit (uncommitted changes, half-verified work) hands the next instance a landmine — the whole point of the handoff is that the *next* agent starts clean. A handoff at 60% on a clean boundary beats a handoff at 40% mid-slice every time.

If your harness does NOT surface context usage, fall back to the proxy counts in Layers 1–2 — they exist precisely for that case.

## Layer 1 — Heuristic triggers (preferred)

Fire when **any one** of these is true AND you're at a safe stopping point (not mid-function, not between two related file edits):

### Per-domain natural breakpoints

**For dev-lead**:
- One acceptance criterion from the original task is completed
- About to start a sub-task estimated at >100 lines of new code/output
- 5+ file edits since the last checkpoint
- 10+ files read since the last checkpoint
- About to delegate to `junior-worker` for the 3rd+ time in this session

**For design-lead**:
- One major artifact done (one ADR, one full API contract, one schema package)
- About to start a new artifact >100 lines
- 5+ file edits since last checkpoint

**For devops-lead**:
- One pipeline/module/manifest complete and dry-run/planned
- About to start a new resource group >100 lines
- 5+ file edits since last checkpoint
- **Special**: NEVER checkpoint mid-`apply`/`deploy`. Wait until the operation completes (success or rollback) before writing the handoff. Half-applied infra is worse than no infra.

**For research-lead**:
- One alternative fully evaluated
- One major subtopic fully sourced and synthesized
- ~half the stated fetch budget spent and partial findings worth preserving

**For security-lead**:
- One vulnerability class fully assessed and findings written
- One target/scope segment complete
- Half the engagement window spent with partial findings to preserve
- **Special**: never leave a finding half-documented; partial security reports are dangerous

**For architect**:
- One major decision area done (e.g. modules decided, moving to interfaces)
- Never checkpoint mid-grilling-session — finish the current question chain first

### Universal heuristic signals

Regardless of agent type:
- You catch yourself re-summarizing earlier work to remember it (context getting crowded)
- You notice you're losing track of which files you've touched
- The conversation has many turns and you've started repeating yourself

## Layer 2 — Hard fallback (must fire NOW)

Fire immediately when **any one** is true, regardless of where you are:

- **≥70% context used** (if your harness surfaces it — see Layer 0)
- **≥50 total tool calls** in this session
- **≥30 file edits** in this session
- **≥40 conversation turns** (rough proxy: ≥40 assistant messages)
- **You notice you're forgetting things you decided earlier** — can't recall a variable name you defined, you're re-reading a file you already read

If mid-function when the hard fallback triggers:
1. Finish the current statement only
2. Save the file (so it parses)
3. Then checkpoint

## What is NOT a trigger

- Effort. Hard work alone isn't a reason to handoff. Work until you hit a real trigger.
- Single big file. One 500-line file edit doesn't trigger by itself — it's one edit. Watch the cumulative count.
- User asking a question. Pause to answer, then continue — that's not a context issue.
- Pipeline running (critic→fixer→auditor). The pipeline runs in its own context; doesn't count toward yours.

## Why these layers

**Context budget (Layer 0)** is the truest signal when available — it measures the actual thing we care about (how full the window is), not a proxy. **Heuristic (Layer 1)** catches degradation at clean boundaries when you can't see the budget. **Hard fallback (Layer 2)** catches pathological cases (one huge file read that bloats context in a single call) even mid-stream.

Together: when the harness shows context usage, Layer 0 leads — arm at 55%, finish the slice, hand off; force at 70%. When it doesn't, most checkpoints happen heuristically at clean breakpoints, with the proxy hard-fallback as the safety net.

## Tuning

If you find handoffs are firing too aggressively (e.g. on small tasks), the trigger numbers are too low — raise them in the agent's prompt.

If handoffs are firing too late (work degraded before the checkpoint), the trigger numbers are too high — lower them.

These numbers (5, 10, 30, 40, 50) are starting points based on observed Claude Code behavior. Tune per your usage.
