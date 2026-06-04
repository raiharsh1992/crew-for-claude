# Lint and Format Code

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The tools below (black/isort/flake8/mypy/bandit)
> are this pack's default chain — swap for ruff/etc. if your project differs.

Run all code quality tools on the codebase.

## Commands to Execute

Run these in sequence:

```bash
# Format code (line length: 100)
black app/ tests/

# Sort imports (profile: black)
isort app/ tests/

# Check for style issues (app/ AND tests/ — hygiene baseline)
flake8 app/ tests/

# Type checking (BLOCKING per hygiene baseline)
mypy app/

# Security scan
bandit -r app/ -ll
```

## Configuration

### Line Length
- **100 characters** — Configured in pyproject.toml for all tools

### Tool Configuration (pyproject.toml)
```toml
[tool.black]
line-length = 100

[tool.isort]
profile = "black"
line_length = 100

[tool.flake8]
max-line-length = 100
exclude = [".venv", "__pycache__", "alembic"]

[tool.mypy]
python_version = "3.11"
strict = true
```

## What to Fix

### Black / isort (Auto-fix)
- Formatting + import ordering fixed automatically (isort uses the black profile)

### flake8 (Manual Fix Required)
Common issues: `E501` line too long · `F401` unused import · `F841` unused variable ·
`E711` compare to None (use `is None`) · `E712` compare to True/False (use `if x:`)

### mypy (Manual Fix Required) — BLOCKING
Missing type hints · incompatible return types · missing Optional for nullable params.

> mypy is a BLOCKING CI gate per the hygiene baseline — never `continue-on-error`. Treat
> local mypy output as the gate, not advisory.

### bandit (Security)
HIGH = fix immediately · MEDIUM = fix before merge · LOW = review.

## Quality Verification Checklist

- [ ] **Black Passed**: zero formatting changes needed
- [ ] **isort Passed**: imports correctly ordered
- [ ] **flake8 Clean** on `app/` AND `tests/`: zero violations
- [ ] **mypy Clean** on `app/`: zero type errors (strict)
- [ ] **bandit Clean**: no HIGH/MEDIUM issues

## Import Order (isort / black profile)

```python
# 1. Standard library
import os
from datetime import datetime
from uuid import UUID

# 2. Third-party
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

# 3. Local application
from app.core.config import settings
from app.core.logging import get_logger
from app.db.database import get_db_session
```

## Fixing Common Issues

```bash
# Auto-fix
black app/ tests/ && isort app/ tests/

# Check without fixing
black --check app/ tests/ && isort --check-only app/ tests/
```

## Pre-Commit Integration

```bash
pre-commit install
pre-commit run --all-files
```

> Never use `git commit --no-verify` to skip hooks.
