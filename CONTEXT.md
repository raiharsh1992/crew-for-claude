# Crew for Claude — Orientation

This is the **orientation** half of the context contract for the `crew-for-claude` framework
repo itself. The **rules** half is `CLAUDE.md`. Anyone (human or agent) picking up work here
reads: `CLAUDE.md` → this file → design docs → code.

> **Freshness is mandatory.** Any change that alters the framework's capability structure,
> directory layout, hook wiring, or public contracts updates this file in the *same* change.

---

## What this repo owns

This repo IS the framework — `crew-for-claude`. It contains the portable Claude Code
operating-model that any project can install: agents, skills, commands, workflows, hooks,
language packs, and the documentation spec. It does NOT own any consuming project's code,
config, or issue tracker — those live in per-project config the consumer generates with
`/install`.

---

## The one file to read first

`docs/AGENT-WORKFLOW.md` — the binding workflow spec every agent reads per session. If you
read one file before touching this repo, read that one.

---

## Five capability layers (the core model)

| Layer | What it is | Lives in |
|---|---|---|
| **command** | Prompt template (`.md`), `$ARGUMENTS` substituted — no agents, no logic | `.claude/commands/` |
| **skill** | Conditional knowledge + bundled resources, loaded on demand | `.claude/skills/<name>/` |
| **workflow** | Deterministic multi-agent JS script (`parallel`/`pipeline`/loops) | `.claude/workflows/` |
| **lead** | Spawnable domain agent owning a slice + its quality pipeline | `.claude/agents/` |
| **orchestrator** | Main session acting as `lead-agent` (role, not a spawn target) | `.claude/agents/lead-agent.md` |

---

## Directory map

```
.claude/
  agents/         The 15-agent roster (leads, quality pipeline, workers)
  skills/         The 17 skills (orient, remember, install, create-workflow, …)
  commands/       5 core commands (status, verify-service, new-slice-branch, file-bug, bump-pointer)
  workflows/      5 named workflows + RESOLVER.md + repos.config.example.js
  hooks/          Safety backstop + three-loop sensors + naming guard
  memory/         MEMORY.md — the learning-loop index (seeded empty by /install)
  skills-config.json         Per-project config (consumer fills this in)
  skills-config.example.json Shape reference
  skills-config.schema.json  JSON Schema
  settings.json              Sample hook wiring
packs/
  python-fastapi/ Real pack (commands, hooks, verify defaults)
  java/ node/ go/ Spec-only stubs
  PACK-SPEC.md    Authoring contract for new packs
docs/
  guide/          Complete technical guide (getting-started, core-concepts, three-loops,
                  working-with-the-crew, reference)
  THE-METHOD.md   Philosophy — six habits + five-layer model + back-flow
  AGENT-WORKFLOW.md  Binding workflow spec (every agent reads per session)
  INSTALL.md      Installation walkthrough (Detect → Scope → Wire)
  adr/            Architecture decision records (0001, 0002)
templates/
  CLAUDE.md.template    Per-repo rules file template
  CONTEXT.md.template   Per-repo orientation file template
  ADR.template.md       ADR template
```

---

## The three loops (back-flow)

| Loop | Sensor hook | Actuator skill | What it closes |
|---|---|---|---|
| 1. Onboarding | `onboard.sh` (SessionStart) | `/orient` + `/install` | A fresh repo is opaque until someone manually runs `/orient` |
| 2. Learning | `suggest-memory.sh` (Stop) | `/remember` | A correction dies with the context window |
| 3. Freshness | `check-freshness.sh` (SessionStart) | `drift-audit` | `CONTEXT.md` drifts silently as code evolves |

Sensors: read-only, never block, fail silent. Actuators: propose every tracked edit before
writing. Trust invariant: "propose, never silently auto-write."

---

## Consumer installation contract

A consumer installs by:
1. Copying `.claude/`, `packs/`, `docs/` into their project root.
2. Running `/install` (Detect → Scope → Wire) to generate per-project config.
3. Filling in `CLAUDE.md` and `CONTEXT.md` from `templates/`.

The framework ships **zero project-specific facts**. Verify commands, repo universe, issue
tracker, and language pack all live in per-project config the consumer owns. See
`docs/adr/0001-projects-self-configure-via-install-resolver-packs.md`.

---

## Attribution hook

The `check-commit-msg.sh` and `block-claude-attribution.sh` hooks enforce an optional
attribution trailer on the git surface. **Default OFF** — they are no-ops when
`attributionTrailer` in `skills-config.json` is empty. A consumer who wants attribution
enforcement sets that field to their trailer string.

---

## Domain glossary

| Term | Means |
|---|---|
| **context contract** | The two-file pair (`CLAUDE.md` rules + `CONTEXT.md` orientation) every repo carries, kept current with the code |
| **slice** | One bounded unit of feature work owned end-to-end by a domain lead |
| **quality pipeline** | The critic → fixer → auditor chain that every FULL-tier slice runs before merging |
| **gate tiering** | FULL (all gates) vs LEAN (auditor-only) — matched to blast radius, never lowering the bar |
| **back-flow** | The three loops that feed session learning back into the workspace (vs forward-flow = human-invoked skills) |
| **sensor** | A read-only hook that notices a moment and nudges (never writes, never blocks) |
| **actuator** | The skill the sensor nudges toward — it writes, with human approval |
| **resolver** | The precedence ladder (`args → repos.config → .gitmodules → auto-discovery`) that resolves the repo universe |
| **verify map** | The 2-D (`language × class`) config in `skills-config.json` that resolves verify/lint/test commands |
