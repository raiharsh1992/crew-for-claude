# Python FastAPI Pack Hooks

This directory contains PreToolUse Bash hooks that enforce project conventions for Python projects. All hooks are installed as PreToolUse matchers on the Bash tool when the python-fastapi pack is activated.

## enforce-venv.sh

**Purpose**: Enforce the complete project venv rule — both STRUCTURE and ACTIVATION.

**What it does**:
- **STRUCTURE**: A virtualenv may only be created at the canonical path `.venv` at the repo root. Commands like `python -m venv <name>`, `virtualenv <name>`, and `uv venv <name>` are blocked if `<name>` is not `.venv` or a `verify_venv*` (CI throwaway) pattern.
- **ACTIVATION**: Every bare Python command (pip, python, pytest, mypy, etc.) must run inside the `.venv` venv. Commands are allowed only if they:
  - Are an activation: `source .venv/bin/activate` or `. .venv/bin/activate`
  - Call a venv tool by explicit path: `.venv/bin/<tool>` or `.venv\Scripts\<tool>`
  - Use a venv-aware runner: `uv run`, `poetry run`, `pdm run`, `hatch run`, `pipenv run`, or `tox`
  - Have a prior activation on the same command line (joins via `&&` or `;`)

**Fail-safe behavior**: If no JSON parser is available (jq/python/python3), the hook parses the raw command text and over-blocks rather than failing open.

## enforce-venv-structure.sh

**Purpose**: Enforce only the STRUCTURE part of the venv rule — where virtualenvs may be created.

**What it does**:
- Blocks virtualenv-creation commands (`python -m venv`, `virtualenv`, `uv venv`) unless the target is `.venv` at the repo root.
- Allows CI throwaway patterns matching `verify_venv*` (e.g., `verify_venv_test`).
- Does NOT check activation or bare Python-tool commands — use `enforce-venv.sh` for the full rule.

**Use case**: Lighter-weight structure enforcement when activation checking is handled separately or when you want to isolate the directory-path constraint.

**Fail-safe behavior**: Same jq → python → python3 → raw fallback as `enforce-venv.sh`; over-blocks on parse failure.

## block-destructive-migrations.sh

**Purpose**: Block irreversible database migrations in Python-stack projects using Alembic.

**What it does**:
- Blocks `alembic downgrade base` (resets to the schema root, destroys all migration state).
- Blocks relative downgrades: `alembic downgrade -` or `alembic downgrade -<n>`.
- Allows targeted downgrades to a specific revision: `alembic downgrade <revision>` (recoverable).
- Allows all upgrades: `alembic upgrade …`.

**Rationale**: Forward moves and targeted rollbacks to specific revisions are recoverable; rolling back to `base` or using relative moves can accidentally destroy schema state. This is a Python/SQLAlchemy-specific rule, so it lives in the pack rather than the language-neutral core git guard.

**Fail-safe behavior**: Parses the command via jq → python → python3 → raw fallback; over-blocks on parse failure to prevent dangerous operations.

---

## Configuration

All three hooks respect optional tunables via `.claude/hooks/hook-globs.env` (if sourced):
- `VENV_DIR` — canonical venv directory name (default: `.venv`)
- `VENV_SCRATCH` — glob prefix for sanctioned throwaway venvs (default: `verify_venv`)

## Exit Codes

- **Exit 0**: Command is allowed; no violation.
- **Exit 2**: Command is blocked; a violation is detected.

All hooks write block messages to stderr (fd 2) and exit 2 on failure.
