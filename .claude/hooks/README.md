# Hooks

Two families of hooks live here. The **safety backstop** — two `PreToolUse` hooks
(`block-dangerous-git.sh`, `block-secrets-in-writes.sh`) — fires regardless of your
permission posture and fails **safe**: if it can't parse the event it over-blocks rather
than letting something through. The **three-loop sensors** — `SessionStart` + `Stop` hooks
(`onboard.sh`, `check-freshness.sh`, `suggest-memory.sh`) — are advisory: they surface
one-line nudges, never block, and fail **silent** (a missed nudge over a spurious one). See
the table below and [docs/adr/0002](../../docs/adr/0002-the-three-loops-auto-growing-workspace.md).

| Hook | Matcher | Role |
|---|---|---|
| `block-dangerous-git.sh` | `Bash` | Blocks irreversible git/fs/DB ops + secrets in commands; warns on parallel-session collision. |
| `block-secrets-in-writes.sh` | `Write\|Edit\|MultiEdit\|NotebookEdit` | Blocks a real secret written into a tracked source/config file. |
| `secret-patterns.sh` | *(sourced, not matched)* | Single source of truth for credential shapes — sourced by BOTH hooks above. |
| `suggest-memory.sh` | `Stop` | The **learning-loop sensor** (Loop 2): notices a durable lesson in the turn (a correction, a "from now on", a locked decision, a preference) and nudges toward `/remember`. Never writes, never blocks — advisory only. |
| `onboard.sh` | `SessionStart` | The **onboarding-loop sensor** (Loop 1): on a fresh/un-installed repo, detects folder shape (empty / single / multi-repo) and surfaces the right "install → alive" offer (`/orient`, `/install --dry-run`). Goes silent once installed + `CONTEXT.md` authored. |
| `check-freshness.sh` | `SessionStart` | The **freshness-loop sensor** (Loop 3): on an installed+oriented repo, nudges toward `drift-audit` when `CONTEXT.md` looks stale vs the code (cheap git-commit-count heuristic, `STALE_THRESHOLD`-tunable). |
| `check-commit-msg.sh` | `commit-msg` (git hook) | The **commit-message naming guard**: rejects a commit whose message names a model vendor/tier (Anthropic / Sonnet / Haiku / Opus / "Claude Code"). Default OFF when `attributionTrailer` is empty in `skills-config.json`. Configure the trailer to enable. Documentation may name models; commit messages may not. |
| `block-lead-agent-spawn.sh` | `Task` | **Agent lane discipline**: blocks spawning the orchestrator (`lead-agent`) as a sub-agent — it self-blocks on nested Task/Bash and wastes tokens. Orchestration is done by the main session; only domain leads/workers are spawnable. Fail-safe (over-allows a Task it can't parse, never wedges). |
| `block-cd-escape.sh` | `Bash` | **Stay-in-project**: blocks a `cd`/`pushd` whose target leaves the project root — you may cd into CHILDREN, never a parent / `cd /` / `cd ~` / an absolute path outside. Stops a session editing the wrong repo or another vertical's space. Opt-in `CD_ALLOWED_ROOTS` for sibling repos; fail-safe (allows if unparseable). |
| `guard-memory-size.sh` | `Write\|Edit\|MultiEdit` | **Memory-size compaction guard**: keeps each `.claude/memory/*.md` under ~24KB. Over the ceiling it blocks the write and instructs the agent to compress/consolidate older records (or split a topic out) THEN re-write — "make room, then continue," not a hard stop. Warns near the limit. Tunable via `MEMORY_MAX_BYTES`/`MEMORY_WARN_BYTES`. |

> **The three-loop sensor family** (see [docs/adr/0002](../../docs/adr/0002-the-three-loops-auto-growing-workspace.md)):
> these three hooks are *sensors* — they cheaply NOTICE a moment (a learnable lesson, a
> fresh repo, a stale doc) and SURFACE a one-line nudge to the matching *actuator* skill
> (`/remember`, `/orient`, `drift-audit`). None of them write or block; every write stays in
> a skill the user can see and approve. This sensor/actuator split is what makes the kit
> auto-grow without ever editing a tracked file behind the user's back.

> **The commit-message naming guard** (`check-commit-msg.sh`) is a native git `commit-msg`
> hook, not a Claude Code tool hook. Because `.git/hooks/` is not version-controlled, the
> guard *script* lives here (tracked, shareable) and a one-line shim in `.git/hooks/commit-msg`
> calls it. Install the shim with:
> ```bash
> printf '#!/bin/bash\nexec "$(git rev-parse --show-toplevel)/.claude/hooks/check-commit-msg.sh" "$1"\n' > .git/hooks/commit-msg
> chmod +x .git/hooks/commit-msg
> ```
> `/install` wires this automatically.

Additional hooks are **not** core — they ship with the `python-fastapi` pack
(`packs/python-fastapi/hooks/`) and are wired in only when that pack is activated,
because they only matter where there is Python:
- `enforce-venv.sh` — the crew's Python venv rule: **one `.venv` at the repo root,
  and every Python command runs inside it** (bare system-interpreter
  `pip`/`python`/`pytest`/… are blocked).
- `block-destructive-migrations.sh` — blocks irreversible `alembic downgrade base`
  / relative rollbacks (the Python-stack DB destruction kept out of the
  language-neutral core git guard).

See the pack README for the full allow/block contract of both.

## The secret-scan single-source design (why `secret-patterns.sh` exists)

Earlier, `block-dangerous-git.sh` carried its credential-shape list **inline**.
When the file-write surface (`block-secrets-in-writes.sh`) was added, that left
two copies of the pattern list that could silently drift — a secret shape added
to one surface but not the other is a hole that only shows up after a leak.

The fix: **extract the patterns + allowlist + scan function into one sourced
file** (`secret-patterns.sh`) and `source` it from BOTH hooks. There is now ONE
pattern list. The two surfaces (Bash commands, file writes) can never disagree
on what counts as a secret — the zero-drift guarantee is structural, not a
matter of remembering to update both.

`secret-patterns.sh` has no shebang and no top-level `exit` — it is meant to be
sourced, never executed directly. It defines:
- `SECRET_PATTERNS` — high-confidence credential shapes (case-sensitive).
- `TEST_SECRET_ALLOWLIST` — pipe-separated test-only values that must NOT trip
  the scan. Add your project's CI/fixture values here.
- `SECRET_BLOCK_MSG` — the shared block message both hooks emit.
- `scan_for_secrets <text>` — returns 0 (+ matched pattern on stdout) if a
  secret shape is present, 1 if clean.

## `block-dangerous-git.sh` (Bash)

The hard backstop behind whatever permission posture you run.

### What it blocks
- **Force-push to the protected branch** (set `PROTECTED_BRANCH` at the top —
  defaults to `main`; change to `master` if that's yours)
- **Working-tree destruction:** `git reset --hard`, `git clean -f`,
  `git checkout/restore .`, `git branch -D`
- **Filesystem destruction:** any recursive-force `rm -rf`
- **Irreversible DB ops in an execution context:** `DROP`/`TRUNCATE TABLE` via
  `psql`/`mysql`/`-c`/`.sql`, `dropdb` (stack-agnostic DB tooling only —
  framework-specific destructive migrations like `alembic downgrade base` are
  enforced by the relevant language pack, not core)
- **Real secrets** in a command (via the shared `scan_for_secrets`)

### What it warns on (does NOT block)
- **Parallel-session collision:** a HEAD-moving git op (`checkout -b`, `switch
  -c`, `branch -f/-M`, `commit --amend`, `rebase`, `reset`, `cherry-pick`)
  running WHILE the working tree shows submodule churn the acting session may
  not have created. That combination is the fingerprint of a second session
  live in the same tree, tangling history. The hook warns at the decision moment
  (exit 0, stderr surfaces as agent context) so you can confirm no other session
  is active before moving HEAD. A dirty tree is often legitimately your own
  work, so this is a warning, never a block.

### What it allows
Normal feature-branch flow — `git push`, commit, branch, force-push to your own
feature branch, `alembic upgrade`, tests, queries. SQL destruction only trips on
an actual run, not on prose (a commit message or issue body mentioning "DROP
TABLE" is fine).

## `block-secrets-in-writes.sh` (Write/Edit/MultiEdit/NotebookEdit)

Closes the gap the Bash hook can't reach: a secret written into a `.py` / `.yaml`
/ Dockerfile / CI workflow via a file-write tool, never touching a shell command.

- **Sanctioned-file exemption:** writes into a gitignored secret-bearing file
  (`.env`, `.env.*`, `*.pem`, `*.key`, `credentials.json`, `*.secret`) are
  allowed — that is the one sanctioned path for a real local secret, and
  `.gitignore` already keeps it out of git.
- **`*.example` is NOT exempt** — it's tracked, so `.env.example` is scanned at
  full strength (a placeholder passes; a real secret correctly trips).
- The exemption fails **closed** toward scanning: a path it can't extract is
  treated as "not exempt" and scanned. It also always scans the raw event as a
  union, so a non-string payload can't smuggle a secret through another field.

## Wiring it

All the hooks are referenced from `.claude/settings.json` (see the sample in this
repo and the steps in [../../docs/INSTALL.md](../../docs/INSTALL.md) / the `/install`
skill). On Windows, run them via Git Bash or WSL — they're bash scripts. There are two
families: the **safety backstop** (`PreToolUse`, blocks irreversible/leaky ops) and the
**three-loop sensors** (`SessionStart` + `Stop`, advisory nudges that never block).

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": ".claude/hooks/block-dangerous-git.sh" }] },
      { "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [{ "type": "command", "command": ".claude/hooks/block-secrets-in-writes.sh" }] }
    ],
    "SessionStart": [
      { "hooks": [
          { "type": "command", "command": ".claude/hooks/onboard.sh" },
          { "type": "command", "command": ".claude/hooks/check-freshness.sh" }
      ] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": ".claude/hooks/suggest-memory.sh" }] }
    ]
  }
}
```

When the `python-fastapi` pack is activated, the installer copies
`enforce-venv.sh` into this folder and adds a `Bash` matcher entry for it.

### Customizing
- **`PROTECTED_BRANCH`** — set to your main branch name (top of
  `block-dangerous-git.sh`).
- **`TEST_SECRET_ALLOWLIST`** — edit in `secret-patterns.sh` (one place, both
  surfaces) to allow your test-only fixture values.
- **Known wrinkle:** because the Bash hook scans command *text*, a `gh issue
  create` / `git commit` whose *body* contains a literal trigger string (`rm
  -rf`, a force-push-to-main phrase) can be over-blocked. Workaround: put long
  bodies in a file and pass `--body-file` / commit via a file so the trigger
  text isn't on the command line.
