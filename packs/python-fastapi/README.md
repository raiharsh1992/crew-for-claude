# python-fastapi pack

> **EXAMPLE python / FastAPI stack pack.** This is the one fully-fleshed pack and
> doubles as the reference for authoring others (see [`../PACK-SPEC.md`](../PACK-SPEC.md)).
> The verify commands and command set here assume a Python service with a `.venv`
> at the repo root, `flake8` + `mypy` for lint, and `pytest` + coverage for test.
> **Adapt the toolchain to your project** — none of these tools is mandated by the
> crew; swap `flake8`→`ruff`, `pytest`→`unittest`, etc. in
> `pack.json.verifyDefaults` (and then in your `skills-config.json`).
>
> **The venv hook is the one rule that is NOT just an example.** Every project that
> activates this pack adopts the rule that *all* Python runs inside the project's
> `.venv` (details below). You may rename the venv dir (`VENV_DIR`), but the
> always-in-venv guarantee is part of what adopting the Python pack means.

## What this pack contributes when activated

- **Verify defaults** for the `python` language — merged into
  `.claude/skills-config.json` at `verify.defaults.python`.
- **Slash commands** (in `commands/`, declared in `pack.json`): `new-model`,
  `new-router`, `new-event`, `new-sqs-handler`, `lint`, `run-tests`, `audit`,
  `migrate`. Each carries an "EXAMPLE — python/FastAPI stack pack command" banner;
  they keep stack-specific patterns (tenant_id, HMAC, soft-delete, outbox) as
  sanctioned pack examples. The stack-agnostic `verify-service` command is **core**
  (`.claude/commands/`), not a pack command — it resolves its toolchain from the
  `skills-config.json` verify map rather than hardcoding one.
- **Two hooks** — `hooks/enforce-venv.sh` (the project venv rule, see "The venv
  rule" below) and `hooks/block-destructive-migrations.sh` (blocks
  `alembic downgrade base` / relative rollbacks — Python-stack-specific DB
  destruction that is intentionally kept out of the language-neutral core git
  guard). On activation the installer copies each into `.claude/hooks/` and adds a
  `Bash` matcher entry in `settings.json`.

## Activation

`/install` activates this pack automatically when it detects a Python marker
(`pyproject.toml` / `setup.cfg` / `requirements.txt`), or you can opt in by
setting `packs.python-fastapi: true` in `.claude/skills-config.json`. See
[`../PACK-SPEC.md`](../PACK-SPEC.md) "How activation uses a pack."

## The venv rule (`hooks/enforce-venv.sh`)

**The project is tied to one virtualenv and every Python command runs inside it —
period.** This is a crew rule, not a style preference, and `enforce-venv.sh` makes
it machine-enforced. It is **pack-scoped, not core** (it only matters where there's
Python), so it ships here and is wired into `.claude/settings.json` on activation.

It blocks two things:

1. **Wrong-path venvs.** A venv may only be created at `.venv` at the repo root.
   `python -m venv myenv`, `virtualenv env`, `uv venv foo` → blocked. The CI-equivalence
   throwaway `verify_venv*` (which you should gitignore) is the one exemption.
2. **System-interpreter Python.** A Python package/run command (`pip`, `python`,
   `pytest`, `mypy`, `flake8`, `black`, `isort`, `bandit`, `ruff`, `coverage`,
   `uvicorn`, `gunicorn`, `alembic`, `django-admin`) that is **not bound to the
   venv** → blocked, because it would hit the system interpreter.

A command counts as venv-bound (and is allowed) if it activates first
(`source .venv/bin/activate && …`, Windows `\.venv\Scripts\activate`), calls the
tool by venv path (`.venv/bin/pytest`), or uses a venv-aware runner (`uv run`,
`poetry run`, `pdm run`, `hatch run`, `pipenv run`, `tox`). The detection keys off
**command position** (start of line or after `&& || ; | ( &`), so a tool name that
appears merely as an argument (`grep -r pytest .`, `echo "install python"`) does
not trip it.

**Tunables** (optional, via a sourced `hook-globs.env`): `VENV_DIR` (default
`.venv`), `VENV_SCRATCH` (default `verify_venv`).

Like the core hooks it is **fail-safe**: it over-blocks on an unparseable event,
never fails open. Exit 2 = block, exit 0 = allow.
