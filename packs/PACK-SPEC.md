# Pack specification

A **pack** teaches the crew one language/stack: which file markers identify it,
which verify commands it runs, which commands (slash-command `.md` files) it adds
to `.claude/commands/`, and which hooks it wires in. Core stays language-agnostic;
all language-specific knowledge lives in packs.

This spec is the contract every pack obeys. It is **thorough enough to author a
new pack (e.g. java) without reading core internals** — if something here is
ambiguous, that is a spec bug, file it.

---

## What a pack is

A directory under `packs/<id>/` containing:

```
packs/<id>/
  pack.json          # REQUIRED — the manifest (schema below)
  README.md          # REQUIRED — one-paragraph "what this pack is", EXAMPLE banner
  hooks/             # OPTIONAL — pack-specific hook scripts (copied to .claude/hooks/ on activation)
  commands/          # OPTIONAL — slash-command .md files (copied to .claude/commands/ on activation)
  templates/         # OPTIONAL — pack-specific file templates (service skeleton, etc.)
```

The **one real pack** today is `python-fastapi`. `java`, `node`, `go` are
**spec-only placeholders**: a `pack.json` stub + a "FUTURE" note, no commands/hooks
yet. They exist so the structure is visible and so auto-discovery can report
"detected java, no pack" against a real id.

---

## `pack.json` schema

```jsonc
{
  "id": "python-fastapi",            // REQUIRED. Unique pack id. Matches the directory name.
  "displayName": "Python / FastAPI", // REQUIRED. Human label.
  "status": "active",                // REQUIRED. "active" | "spec-only".
  "language": "python",              // REQUIRED. The language this pack handles (java|node|python|go|...).
                                     //   Maps to verify.defaults[<language>] in skills-config.json.

  "markers": [                       // REQUIRED. File markers that identify this stack during
    "pyproject.toml",                //   auto-discovery. A directory containing ANY of these is a
    "setup.cfg",                     //   candidate repo for this pack. Order = priority (most
    "requirements.txt"               //   specific first). See RESOLVER.md marker table.
  ],

  "classHint": "SERVICE",            // OPTIONAL. Default class for repos this pack matches, when
                                     //   shape detection is ambiguous. One of SERVICE|LIBRARY|UI|INFRA.

  "verifyDefaults": {                // REQUIRED for an active pack. The command chain this pack
    "verify": "...",                 //   contributes to verify.defaults[<language>] in skills-config.
    "lint":   "...",                 //   The installer copies these into skills-config.json on
    "test":   "..."                  //   activation (unless the user already set them).
  },

  "commands": [                      // OPTIONAL. Slash commands this pack installs into
    {                                //   .claude/commands/. The .md files live in this pack's
      "name": "new-router",          //   commands/ dir. For a spec-only pack, declare the intended
      "file": "commands/new-router.md", //   commands here even before the .md files exist (they
      "summary": "Scaffold a new API router." //   arrive in a later slice).
    }
  ],

  "hooks": [                         // OPTIONAL. Pack-specific PreToolUse hooks. On activation the
    {                                //   installer copies each script to .claude/hooks/ and adds a
      "file": "hooks/enforce-venv.sh", //   settings.json matcher entry.
      "matcher": "Bash",             //   matcher = the Claude Code tool matcher for this hook.
      "summary": "Enforce the venv rule: one .venv at the repo root + every Python command runs inside it."
    }
  ],

  "templateRefs": [                  // OPTIONAL. Named templates this pack provides under templates/.
    { "name": "service-skeleton", "path": "templates/service/" }
  ]
}
```

### Field rules
- **`id`** must equal the directory name and be unique across `packs/`.
- **`status: "active"`** packs MUST provide `verifyDefaults`. `status:
  "spec-only"` packs MAY omit `verifyDefaults`, `commands`, `hooks` (they're
  placeholders) but MUST keep `id`, `displayName`, `language`, `markers`.
- **`markers`** must not collide ambiguously across active packs for the same
  language. Two packs claiming `pyproject.toml` is a conflict the installer
  reports.
- **`commands[].file` / `hooks[].file`** are paths relative to the pack dir.
  They may be declared before the file exists (spec-only / forward-declared), but
  activation of an **active** pack fails if a declared `active` command/hook file
  is missing.

---

## How activation uses a pack (installer contract)

When `/install` activates pack `<id>` (because a marker matched, or the user opted
in via `packs.<id>: true`):

1. **Verify defaults** — merge `pack.json.verifyDefaults` into
   `.claude/skills-config.json` at `verify.defaults[<language>]`, only for stages
   the user hasn't already set (never clobber a user value).
2. **Commands** — copy each `commands[].file` into `.claude/commands/<name>.md`
   (idempotent; skip if the target exists and differs from the pack copy — report,
   don't clobber a user-edited command).
3. **Hooks** — copy each `hooks[].file` into `.claude/hooks/` and add a matcher
   entry to `.claude/settings.json` for it (idempotent; skip if already wired).
4. **Templates** — leave in place; commands reference them by `templateRefs`.
5. Set `packs.<id>: true` in `skills-config.json`.

A **spec-only** pack contributes nothing to activation beyond being the named
target of an auto-discovery gap ("detected `<language>`, pack `<id>` is spec-only
— no verify commands installed").

---

## Authoring a new pack (worked outline — e.g. java)

1. `mkdir packs/java/` (already a stub here — flesh it out).
2. Write `pack.json`: `id: "java"`, `language: "java"`, `markers:
   ["pom.xml","build.gradle","build.gradle.kts"]`, `status: "active"`,
   `verifyDefaults` for mvn/gradle, declare any `commands` and `hooks`.
3. Add `commands/*.md` for the java scaffolding commands you want (mirror the
   python-fastapi command set in shape).
4. Add any `hooks/*.sh` (keep them fail-safe / never-fail-open / exit-0 on an
   unparseable event, matching the core hook conventions).
5. Add a `README.md` with an EXAMPLE-stack banner.
6. Flip the pack to `status: "active"` and set `packs.java: true` in your
   `skills-config.json`.

No core file needs editing — packs are additive by design.
