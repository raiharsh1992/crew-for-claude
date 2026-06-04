---
name: bootstrap-skills
description: One-time-per-project bootstrap that configures the issue tracker (local files by default), the triage label vocabulary, and where domain docs live. Run once before using draft-prd, slice-issues, sort-issues, troubleshoot, test-first, deepen-architecture, or survey-code. Use when starting a new project or when a skill says "issue tracker / labels / docs location not configured".
---

# Setup Project Skills

This skill creates `.claude/skills-config.json` at the project root. Other skills read from it instead of asking you the same questions every time.

## Process

### 1. Detect what already exists

Check for:
- `.claude/skills-config.json` — already configured? Show it and ask if the user wants to update or start over.
- `CONTEXT.md` or `CONTEXT-MAP.md` at the project root — domain glossary; tells us if the project already has a shared language doc.
- `docs/adr/` — ADRs folder; tells us if the project records architecture decisions.
- A `.git` folder with a GitHub remote → GitHub is available as a tracker option.
- `.linear.app` or known Linear integrations → Linear may be available.
- Any `issues/` folder at the project root → local-files mode is already in use.

### 2. Ask the issue-tracker question

Ask the user: "Which issue tracker should the skills (draft-prd, slice-issues, sort-issues) use for this project?"

Options:
- **`local`** (default — recommended for solo and early-stage projects) — issues live as markdown files under `issues/` at the project root. No external dependency.
- **`github`** — issues go to the GitHub repo. Requires the `gh` CLI authenticated; the skill will check.
- **`linear`** — issues go to Linear. Requires the Linear MCP or API key; the skill will check.

If local: create `issues/` if missing, add a `issues/README.md` explaining the convention, ensure `issues/` is in `.gitignore` only if the user says these are working notes (default: keep them in git so the project history captures them).

### 3. Ask the label vocabulary

Default vocabulary (recommended — matches the triage skill out of the box):

```
Categories:  bug, enhancement
States:      needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix
```

Ask the user: "Use these defaults, or customize?"

If `local` tracker: labels become inline markdown front-matter on each issue file (`labels: [bug, needs-triage]`).
If `github`/`linear`: confirm the labels exist in the tracker; if not, create them on first use.

### 4. Ask the docs location

Where should new skill-generated docs live?
- ADRs → default `docs/adr/`
- Domain glossary → default `CONTEXT.md` at project root (or `docs/CONTEXT.md` if user prefers)
- PRDs → if tracker is `local`, default `issues/prds/`; otherwise issues hold them

### 5. Write the config

Create `.claude/skills-config.json`:

```json
{
  "issueTracker": {
    "type": "local|github|linear",
    "localPath": "issues/",
    "labels": {
      "categories": ["bug", "enhancement"],
      "states": ["needs-triage", "needs-info", "ready-for-agent", "ready-for-human", "wontfix"]
    }
  },
  "docs": {
    "context": "CONTEXT.md",
    "adrDir": "docs/adr/",
    "prdDir": "issues/prds/"
  }
}
```

### 6. Tell the user what other skills are now unlocked

Print: "Configured. The following skills will now work without re-asking these questions: `/draft-prd`, `/slice-issues`, `/sort-issues`, `/troubleshoot`, `/test-first`, `/deepen-architecture`, `/survey-code`."

## Notes

- This skill is idempotent — re-running it shows current config and lets the user update fields.
- The config file is intentionally per-project (lives in `.claude/`), not global, so different projects can have different trackers.
- If a skill is invoked before this one has been run, it should detect the missing config and prompt the user to run `/bootstrap-skills` first.
