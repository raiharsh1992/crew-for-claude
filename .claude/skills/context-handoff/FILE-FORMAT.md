# Handoff File Format

Every handoff is one markdown file at `.handoff/<agent-name>-<ISO-timestamp>.md` at the project root.

The format below is mandatory — the fresh instance reads each section and acts on it. Skipping sections breaks the resume protocol.

## Template

```markdown
# Handoff — <agent-name> — <ISO timestamp>

## Original task
<quote the task you were given, verbatim if short, summarized if long>

## Caller
<lead-agent / user / specify>

## Status
<one line: "checkpoint at natural breakpoint" | "hard fallback triggered" | "task complete, no resume needed">

## Done (verified)
- <thing completed, with file paths and line numbers where applicable>
- <...>

## In progress (interrupted)
- <thing partially done — what's the state, where to pick up>
- <if mid-function: name the function, the file, the line, and what was about to happen>

## Not started
- <remaining work items from the original task, in priority order>

## Decisions made (so the next instance doesn't relitigate them)
- <decision>: <reasoning>
- <e.g. "Chose Drizzle over Prisma — matches existing state-manager-service stack">

## Open questions / blockers
- <thing the next instance needs to decide or escalate>

## Files touched this session
- <path>: <created | modified | read-only>
- <...>

## Resume instructions
The next <agent-name> instance should:
1. Read this handoff file first
2. Read these files for context: <list — only the ones still relevant, not everything I read>
3. Continue with: <specific next action>
4. Pipeline status: <not yet run | critic done | fixer done | needs auditor>

## Verification command (if any)
<exact command(s) the next instance can run to confirm current state is what I claim>
```

## Why each section exists

| Section | Purpose | What goes wrong without it |
|---|---|---|
| Original task | Anchor; prevents drift | Next instance solves a slightly different problem |
| Caller | Routing context | Next instance reports back to the wrong place |
| Status | Quick triage | Caller can't tell if scope is sized right |
| Done (verified) | Trust signal | Next instance redoes completed work |
| In progress (interrupted) | The most important section | Next instance has no idea where to pick up |
| Not started | Remaining scope | Next instance forgets the original task's full ask |
| Decisions made | Prevents relitigation | Next instance grills out same decisions, wastes time |
| Open questions | Surfaces blockers | Blockers get re-hit and re-escalated |
| Files touched | Context surface for next instance | Next instance re-reads everything |
| Resume instructions | The hand-off to next-you | Next instance has to figure out resume on its own |
| Verification command | Confirm current state | Next instance trusts handoff narrative, gets surprised |

## Quality bar

- Every "Done (verified)" item points to specific files/line ranges, not vague descriptions
- "In progress" specifies the file AND the line AND what was about to happen
- "Decisions made" includes the reasoning, not just the choice — so next instance can judge edge cases
- "Resume instructions" lists the SUBSET of files relevant to resume, not everything you read

## What NOT to include

- A full diff of changes (large, redundant — git already has it)
- A copy of files you edited (next instance can read them)
- Your reasoning narrative for every decision (boring; just the decisions + brief why)
- Speculation about "what the user might want" (leave that to the next instance + the caller)

A good handoff is 100–300 lines. If you're at 500+, you're including too much narrative.
