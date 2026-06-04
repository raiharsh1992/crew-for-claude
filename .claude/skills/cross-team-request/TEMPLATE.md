<!--
  CROSS-TEAM REQUIREMENT SHEET — TEMPLATE
  Copy this file to the configured cross-team directory as REQ-<YYYY-MM-DD>-<slug>.md and fill EVERY section.
  Delete these HTML comments. Write "N/A" only where a section is genuinely not applicable.
  The bar: the target team can execute with ZERO clarifying questions.
-->

# REQ-<YYYY-MM-DD>-<slug>

| | |
|---|---|
| **Requesting team** | <e.g. Your Team Name> |
| **Target team** | <e.g. Infrastructure Team> |
| **Date raised** | <YYYY-MM-DD (absolute)> |
| **Priority** | <P0 blocker / P1 / P2> |
| **Status** | OPEN <!-- OPEN → IN PROGRESS → DONE; flip to DONE when acceptance criteria pass --> |
| **Tracking issue** | #<n> <!-- filled after the GitHub issue is created --> |

---

## 1. Context / why

<What's happening, why this is needed NOW, what it unblocks. Link the upstream work that created this need: PRs, ADRs, design docs, prior REQs. Be specific — the target team should understand the situation without reading the whole conversation.>

## 2. The ask

<The concrete work the target team must do. Numbered, executable steps. Name exact repos, files, services, ports, resources, env-var keys. Do NOT hand-wave ("set up the queue") — say exactly which queue, which config file, which .env var.>

1. …
2. …

## 3. Acceptance criteria (how the requester verifies "done")

<The checkable conditions the REQUESTING team will use to confirm it's done — the requester's definition of "I can now proceed." Each must be objectively verifiable (a command + expected output, an endpoint returning 200, a resource appearing in a list).>

- [ ] …
- [ ] …

## 4. Affected repos / services

<Every repo, service, resource, queue, env var, or config touched. A table is fine.>

| Repo / service | Resource | What changes |
|---|---|---|
| … | … | … |

## 5. Dependencies & blockers

- **This depends on:** <upstream things that must be true first — or "nothing">
- **This blocks:** <the gated downstream work — name it, e.g. "the Phase-2 rollout">
- **Ordering:** <any required sequence among the ask's steps, or "none">

## 6. Approvals required

<Anything needing explicit human sign-off before the target team acts. Infrastructure changes, credential rotation, production deploys, or external actions that need owner approval. State who must approve what. "None" if purely internal and local.>

## 7. Definition of done

> <One sentence both teams agree means "closed.">

**Closed by:** <who flips status to DONE and closes the issue — usually the requesting team after acceptance criteria pass, or the target team with requester confirmation.>
