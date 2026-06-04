# File a Bug (file-first rule)

File an issue on the project's tracker for a bug that will NOT be fixed in the current
loop: $ARGUMENTS

This enforces THE FILE-FIRST RULE (your project's CLAUDE.md, if adopted): the moment any
agent identifies a bug that escapes the current PR/quality-loop, the FIRST action is to
file an issue — BEFORE deferring it, routing it, noting it as a "known limitation", or
writing it into a report. We never want to miss a bug.

`$ARGUMENTS` = a short description of the bug (the rest is gathered below).

## When this applies

File an issue for: a pre-existing bug noticed while working · an out-of-scope discovery ·
any security finding · anything an agent decides to defer / call a "follow-up" / "known
limitation" · any `TODO`/`FIXME` describing a real defect.

Does NOT apply to: a critic finding the fixer resolves in the same PR, or the bug the
current PR is actively fixing (those stay in-loop, no issue needed).

## Where it goes (read the config)

The tracker is configured in `.claude/skills-config.json` under `issueTracker`:

- **`type: "github"`** → file with `gh issue create` on the configured repo (use
  `--repo <owner/repo>` if the config names a parent/central repo for cross-cutting bugs).
- **`type: "local"`** → create a Markdown file under the configured `localPath` (e.g.
  `issues/`), named with the next id + a slug.
- **`type: "none"`** → no tracker configured; surface the bug to the user directly and ask
  where to record it (do not silently drop it).

Apply the labels from `issueTracker.labels` (the config defines the valid `categories` and
`states` for this project). At minimum tag a category and, if your config defines them, a
severity and the affected component.

### GitHub example

```bash
# Put the body in a file so trigger-strings in prose don't trip a dangerous-command hook.
gh issue create --repo <owner/repo-from-config> \
  --title "<concise title>" \
  --body-file <path-to-body.md> \
  --label "<category-from-config>" \
  --label "<severity-or-state-from-config>"
```

### Local-file example

```
issues/<next-id>-<slug>.md   # front-matter: title, category, severity/state from the config vocab
```

## Body template (keep context complete)

```markdown
## Source
<file paths + line numbers>

## Detail
<what's wrong, precisely>

## Reproduction
<exact steps / command / input that triggers it>

## Impact
<what breaks; who is affected; severity rationale — data leak / data loss / money = highest>

## Recommendation
<the fix, or the direction>

## Owner / Routing
<which repo's dev-lead owns this>

## Fix gate
<when it must be fixed: pre-release / next-slice / backlog>
```

## After filing

- Quote the issue id wherever the bug is mentioned next (report, PR, code marker).
- Any in-code marker MUST carry the reference: `# TODO(#<id>): …` — never a bare
  `TODO`/`FIXME`/`<TBD>`.
- Apply the category (and severity/state, if your config defines them) labels.

## Do NOT

- Create the issue on a per-component repo for a cross-cutting bug — file on the central
  repo named in the config and tag the affected component instead.
- Leave an issue without at least a category label.
