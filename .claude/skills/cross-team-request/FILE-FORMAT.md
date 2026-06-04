# Cross-Team Request File Format

## Naming convention

Requirement sheets follow a deterministic naming pattern to support automatic indexing and deduplication:

```
REQ-<YYYY-MM-DD>-<slug>.md
```

Where:
- `YYYY-MM-DD` is the date the requirement was raised (in absolute, ISO 8601 format).
- `<slug>` is a short, kebab-case identifier derived from the requirement's title. Keep it brief (2–4 words maximum).

### Examples

- `REQ-2026-06-04-database-migration.md` — requirement raised on 2026-06-04 for a database migration.
- `REQ-2026-05-20-oauth-provider-setup.md` — requirement for OAuth provider setup, raised 2026-05-20.

## Folder discipline

All requirement sheets live in a single, configured directory (resolved from skills-config.json key `crossTeamRequestDir`, default value `plan/cross-team/`).

The directory structure is flat:

```
plan/
└── cross-team/
    ├── README.md                             (index, created on first use)
    ├── REQ-2026-06-04-database-migration.md
    ├── REQ-2026-05-20-oauth-provider-setup.md
    └── REQ-2026-03-15-infra-monitoring.md
```

## README.md index (created on first use)

The `README.md` in the cross-team directory serves as an index of all active and resolved requirements. Maintain one line per requirement in this format:

```markdown
- [REQ-2026-06-04-database-migration](REQ-2026-06-04-database-migration.md) — Infrastructure Team — Database schema migration for v2.0
- [REQ-2026-05-20-oauth-provider-setup](REQ-2026-05-20-oauth-provider-setup.md) — Security Team — OAuth provider integration
```

Columns: requirement link, target team, one-line summary.

Update the index each time a new requirement is filed. Archive closed requirements (mark `DONE` in the sheet itself, but keep it in the index so the folder remains a complete record).

## GitHub issue naming and linking

Each requirement sheet gets a paired GitHub issue on the configured repository (resolved from skills-config.json `issueTracker.repo`).

The issue title uses the pattern:

```
[REQ-<YYYY-MM-DD>-<slug>] <Title>
```

This creates a 1:1 link: the sheet path, the issue title, and the requirement ID are mutually greppable.

**Example:**
- Sheet: `plan/cross-team/REQ-2026-06-04-database-migration.md`
- Issue: `[REQ-2026-06-04-database-migration] Database migration for v2.0`

The issue body includes:
- A brief summary of the ask (1–2 sentences).
- Acceptance criteria (copy from the sheet).
- A link to the full sheet on the default branch: `[Full requirement](../../plan/cross-team/REQ-2026-06-04-database-migration.md)`.

Labels applied to the issue:
- `type:cross-team-request` (universal marker).
- A team label (e.g., `team:backend`, `team:devops`) — resolved from skills-config.json key `crossTeamLabels`.
- Relevant `category:*` and `service:*` labels.
- A priority signal (e.g., `priority:p0`, `priority:p1`).

## Freshness and lifecycle

- **OPEN**: The requirement has been filed and is awaiting action by the target team.
- **IN PROGRESS**: The target team is actively working on the requirement.
- **DONE**: The requirement is satisfied; the requesting team has confirmed acceptance criteria pass.

When a requirement is satisfied:
1. Update the sheet's `Status` field to `DONE`.
2. Close the GitHub issue (optional to also add a comment confirming which acceptance criteria were met).
3. Leave the sheet in the folder (it's a historical record).

Never delete a closed requirement sheet — the folder is a versioned audit trail.

## Configuration

The cross-team-request skill resolves all repository, directory, and team identity from skills-config.json:

```json
{
  "issueTracker": {
    "repo": "user/repo-name"
  },
  "crossTeamRequestDir": "plan/cross-team/",
  "crossTeamLabels": [
    "team:backend",
    "team:devops",
    "team:frontend"
  ]
}
```

Keys:
- `issueTracker.repo` — GitHub repository for filing issues (e.g., `org/your-repo`).
- `crossTeamRequestDir` — directory path where REQ sheets live (default: `plan/cross-team/`).
- `crossTeamLabels` — array of team labels to create/apply (default examples: `["team:backend", "team:devops", "team:frontend"]`; add more as needed for your project).

Update these values in your skills-config.json to match your repository's conventions.
