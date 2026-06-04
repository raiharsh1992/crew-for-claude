---
name: cross-team-request
description: Produce a structured cross-team requirement (a handoff packet) so one stream can hand well-specified work to another team and have it tracked to done. Writes a versioned requirement sheet to the configured cross-team directory and files a linked, assignable GitHub issue. Use when your team is blocked on or needs work from another team — e.g. frontend needs backend to provision an API, or a team needs a founder/external action. Triggers: "write a requirement sheet", "create a cross-team request", "hand this to team X", "raise a requirement for <team>".
---

# Cross-Team Request

Turn a need that another team must satisfy into a **handoff contract**: a version-controlled requirement sheet plus a trackable GitHub issue, so the work is unambiguous, assignable, and verifiable. This is the durable mechanism for cross-team execution — a team blocked on another team does NOT improvise into another lane; it raises a requirement and routes it.

## When to use

- Your team is **blocked** on work owned by another team (e.g. backend needs infrastructure provisioned before it can deploy).
- You **need a deliverable** from another team that isn't a bug (a new endpoint/contract, an infra resource, a seed-data change, a founder/external action, a security review).
- Any time the honest answer is *"this isn't my lane — team X has to do it"* and you want it tracked, not just mentioned.

## When NOT to use

- It's a **bug** (something built that's broken) → file a normal GitHub issue per the file-first rule (`gh issue create` with `severity:*` and `category:*` labels).
- It's **in your own lane** → just do it.
- It's a question/decision → ask directly, not via a requirement sheet.

## The handoff contract (what every requirement sheet MUST contain)

Use the bundled `TEMPLATE.md` as the structure. The full handoff contract has these sections — none optional (write "N/A" only if genuinely not applicable):

1. **Header** — REQ id, title, requesting team, **target team**, date (absolute), priority, status.
2. **Context / why** — what's happening, why this is needed now, what it unblocks. Link the upstream work (PRs, ADRs, design docs, other REQs).
3. **The ask** — the concrete, specific work the target team must do. Numbered, executable steps. Name exact repos, files, services, resources.
4. **Acceptance criteria** — how the **requesting** team will verify it's done (checkable conditions). These are the requester's definition of "I can now proceed."
5. **Affected repos / services** — every repo, service, resource, queue, env var touched.
6. **Dependencies & blockers** — what this depends on, what it blocks, and any required ordering.
7. **Approvals required** — anything needing explicit human sign-off before the target team acts.
8. **Definition of done** — one sentence both teams agree means "closed."

## Process

### 1. Gather context
Work from the conversation. Identify precisely: your team, the **target team**, the concrete need, and what it unblocks. If unclear which team owns it, resolve that first (don't guess).

### 2. Pick the REQ id
List the REQ files in the configured cross-team directory (default `plan/cross-team/`); the next id uses the pattern `REQ-<YYYY-MM-DD>-<slug>` where YYYY-MM-DD is today's date and slug is short-kebab-case of the title.

### 3. Write the requirement sheet
Copy `TEMPLATE.md` to the configured directory as `REQ-<YYYY-MM-DD>-<slug>.md` and fill **every** section per the handoff contract above. Be concrete: exact resource names, exact env var keys, exact verification commands. The target team should be able to execute with **zero** clarifying questions — that's the bar. Convert any relative dates to absolute.

### 4. Ensure the routing labels exist
The configured repository (via skills-config.json `issueTracker.repo`) needs:
- `type:cross-team-request` (one-time create if absent)
- Labels for each team (configured in skills-config.json `crossTeamLabels` array, default examples: `team:devops`, `team:backend`, `team:frontend`) — create if absent.

Create missing labels with `gh label create`. Also apply relevant existing `category:*` / `service:*` labels.

### 5. File the linked GitHub issue
`gh issue create --repo <configured-repo>` with:
- Title: `[REQ-<id>] <title>` (greppable, maps 1:1 to the sheet).
- Labels: `type:cross-team-request`, the applicable team label, plus relevant `category:*`/`service:*` and priority.
- Body: summary of the ask + acceptance criteria + link to the full sheet on the default branch. Use `--body-file` to avoid trigger-text issues.
- Capture the issue number; write it back into the sheet's header (`Tracking issue: #<n>`).

### 6. Commit the sheet
Branch off the default branch, add **only** the new sheet by explicit name (never `git add -A`), commit with a clear message, push, open a PR to the default branch. The PR makes the sheet reviewable; the issue makes the work assignable.

### 7. Report back
Give the user: the REQ id, the sheet path, the issue URL and number, the target team, and the one-line definition of done. State plainly what is now blocked-pending-this.

## Conventions this skill obeys

- **Files land in the configured cross-team directory** (resolved from skills-config.json key `crossTeamRequestDir`, default `plan/cross-team/`). Create it + a `README.md` index on first use.
- **File-first**: the sheet exists before the work is routed — same discipline as the bug file-first rule.
- **No improvising into another team's lane** — the whole point. Raise the requirement; let the owning team execute.
- **Freshness**: when a REQ is satisfied, mark the sheet's status as `DONE` (don't delete it — it's the record).
