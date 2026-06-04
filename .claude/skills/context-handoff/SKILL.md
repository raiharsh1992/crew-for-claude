---
name: context-handoff
description: Compact a long-running agent's in-flight work into a structured handoff document so a fresh instance can resume without context degradation. Use when a long-running lead (dev-lead, design-lead, devops-lead, research-lead, security-lead, architect) hits a checkpoint trigger — natural breakpoint or hard fallback. The fresh instance then reads the handoff and continues.
---

# Agent Context Handoff

Long-running subagent work (large implementations, multi-stream research, deep audits) can exhaust the agent's context window. When that happens, reasoning quality degrades silently — earlier decisions get forgotten, work gets repeated, output goes incomplete.

This skill catches the problem **before** quality degrades by triggering a structured stop-and-checkpoint at safe boundaries.

## When this skill fires

You invoke this skill (or it auto-fires based on the triggers in [TRIGGERS.md](TRIGGERS.md)) when:

- **Heuristic trigger** (preferred — at a safe stopping point):
  - One acceptance criterion completed
  - About to start a sub-task >100 lines
  - 5+ file edits since last checkpoint
  - 10+ files read since last checkpoint
  - You catch yourself re-summarizing earlier work to remember it
  - About to delegate to junior-worker for the 3rd+ time

- **Hard fallback** (must fire NOW, even mid-stream):
  - 50+ total tool calls in the session
  - 30+ file edits in the session
  - 40+ conversation turns
  - You notice you're forgetting decisions you made earlier

If you're mid-function when the hard fallback hits: **finish the current statement only**, save the file, then handoff. Don't leave broken syntax.

Full trigger details: [TRIGGERS.md](TRIGGERS.md).

## Workflow

1. **Stop accepting new sub-tasks.** Finish the current safe boundary.
2. **Write the handoff file** to `.handoff/<your-agent-name>-<ISO-timestamp>.md` at the project root. Format spec: [FILE-FORMAT.md](FILE-FORMAT.md).
3. **Return to your caller** (lead-agent or user) with the exact structured message:

```
CHECKPOINT — context handoff

Handoff written to: .handoff/<agent>-<timestamp>.md

Reason: <heuristic trigger that fired | hard fallback condition that fired>

Progress: <one line — e.g. "3 of 5 acceptance criteria complete, schema migration verified">

To resume, invoke:
> Use the <agent-name> subagent to continue from .handoff/<agent>-<timestamp>.md

If this is the second consecutive handoff on this task, the scope is likely too large — recommend splitting into smaller deliverables before continuing.
```

4. **Do not start new work.** Your session ends here. A fresh instance picks up from your handoff file.

## When you are resuming (invoked with "Continue from .handoff/<file>")

See [RESUME.md](RESUME.md) for the full resume protocol. Quick version:

1. Read the handoff file first, before anything else
2. Verify the claimed "Done" state by spot-checking 1–2 files
3. Continue from the "Resume instructions" section
4. You may checkpoint again if you hit the triggers — same protocol, new file

## Chain detection

If you receive a handoff that itself continues a prior handoff (chain length ≥ 2), the task is too big for the current scoping. Don't continue — return to the caller with a proposed task split. See [RESUME.md](RESUME.md) §"Chained handoff detection".

## Which agents use this skill

- `dev-lead`, `design-lead`, `devops-lead`, `research-lead`, `security-lead`, `architect` — long-running leads, always wired
- `lead-agent` — handles handoff returns and re-dispatch decisions
- `critic`, `fixer`, `auditor`, `junior-worker`, `tester`, `pentester`, `media-lead` — bounded by design; should not hit context limits. If they do, the scoping of their task was wrong (escalate to the lead that spawned them).

## Setup per project

The `init-project.ps1` script creates `.handoff/README.md` automatically. If you're adopting v2.5 in an existing project that doesn't have it:

1. Create `.handoff/` at the project root
2. Add `.handoff/README.md` (copy from `templates/handoff-readme.md` or generate it)
3. Add to `.gitignore`:
   ```
   .handoff/*
   !.handoff/README.md
   ```

Handoff files are local working state, not codebase history.
