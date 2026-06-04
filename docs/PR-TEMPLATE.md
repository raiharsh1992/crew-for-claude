# PR description template

Copy this into every PR to the main branch. It makes the quality pipeline auditable and
gives the human merger everything they need to decide in one screen.

```markdown
## Slice
Implements `BRIEF-<slice>.md` / `DESIGN-<slice>.md`.

## Scope
- <bullet> what's in
- <bullet> what's NOT in (deferred to follow-up slice)

## Commits (chronological)
- `<sha>` — <commit subject>
- `<sha>` — <commit subject>

## Quality pipeline
- Tier: FULL | LEAN — <one-line reason; if LEAN, confirm it touches none of the FULL triggers>
- [ ] critic: <verdict + finding count>     (FULL only)
- [ ] fixer: <fixes applied>                (FULL only)
- [ ] auditor: APPROVED / CONDITIONAL — <conditions>   (both tiers)
- [ ] verify (local CI mirror): GREEN

## CI gates
- [ ] tests (coverage ≥ <floor>): <result>
- [ ] lint
- [ ] type-check
- [ ] build (if applicable)

## External review
- [ ] Reviewed the latest commit (not just PR opened)
- Each comment resolved WITH PROOF:
  - `<comment>` → **fixed in `<sha>`** | **rejected: <cited rule/decision>** | **deferred: #<issue>**

## Cross-module impact
- <events emitted/consumed, API paths, shared schema changes other modules must align on>

## Breaking changes
- <list, or "None">

## Open items deferred to follow-up
- <numbered list with explicit follow-up slice naming + filed issue numbers>
```
