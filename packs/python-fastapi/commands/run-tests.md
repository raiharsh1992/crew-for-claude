# Run Tests

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The pytest + coverage chain below is this pack's
> default — swap for your test runner if your project differs.

Run the test suite with coverage reporting.

## Commands to Execute

```bash
# Full test suite with coverage (floor enforced by pyproject.toml)
pytest --cov=app --cov-report=term-missing -v
```

## Coverage Requirement

**Minimum coverage: 90%** for new services (pre-existing services ratchet to their real
floor, rounded DOWN to the nearest 5). The floor is single-sourced in `pyproject.toml`
`[tool.coverage.report]` (`fail_under` + **`precision = 2`**).

> Do NOT pass `--cov-fail-under` on the pytest line — it competes with the config and masks
> the exit code (the round-up hole). Keep the threshold in pyproject only.

## What to Check

1. **All tests pass** — zero failures
2. **Coverage ≥ floor** — enforced by the pyproject config
3. **No warnings** — address deprecations
4. **Report failures** with the error message + stack trace

## Test Categories

```bash
pytest tests/test_unit/ -v          # unit
pytest tests/test_api/ -v           # integration
pytest tests/test_api/test_items.py -v   # one module
pytest -s -v                        # show logs/prints
```

## Quality Verification Checklist

### Coverage
- [ ] **Overall ≥ floor** · **New code covered** · **Branch coverage** on conditionals
- [ ] **Only `__init__.py` excluded**

### Test Quality
- [ ] **Happy path** (200/201/204)
- [ ] **Error cases** (400/401/403/404/409/422/429)
- [ ] **HMAC tests** — protected endpoints verify HMAC is required
- [ ] **Tenant isolation** — a caller cannot read/write another tenant's rows
- [ ] **Edge cases** — boundary conditions

### Standards
- [ ] **`@pytest.mark.asyncio`** on async tests
- [ ] **Fixtures** in conftest.py · **Descriptive names** · **Isolated** (no inter-test state)

## CI-equivalence note

`pytest` here is the inner loop. Before opening a PR, prove the FULL CI gate with the
`/verify-service <repo>` command — it resolves this repo's CI-equivalence verify chain from
`.claude/skills-config.json` (lint + type-check + migrations + `pytest --cov`). See
`docs/AGENT-WORKFLOW.md`. Don't run the same suite a fourth time by hand; pre-commit +
verify-service + CI cover it.

## Coverage Report Interpretation

```
Name                          Stmts   Miss  Cover   Missing
-----------------------------------------------------------
app/api/routers/items.py         50      2    96%   45-46
app/services/item_service.py     40      5    88%   22-26
-----------------------------------------------------------
TOTAL                           120      7    94%
```

`Miss`/`Missing` show the exact uncovered lines — write tests for those.

## Pre-Commit Integration

```bash
pre-commit install
pre-commit run --all-files
```
