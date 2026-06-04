# Security & Compliance Audit

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The checklist below encodes a multi-tenant API's
> conventions (tenant isolation, HMAC, soft-delete, audit-on-state-change) — keep what fits
> your project, drop what doesn't.

Perform a comprehensive security and code compliance audit of the codebase.

## Quick Scan Commands

```bash
# Security vulnerability scan
bandit -r app/ -ll

# Check for vulnerable dependencies
pip-audit

# Check for hardcoded secrets
git grep -n "password\|secret\|key\|token" -- "*.py" | grep -v "# " | grep -v "__" | grep -v "settings\."

# Check for print statements
grep -rn "print(" app/ --include="*.py"

# Check for os.getenv usage
grep -rn "os.getenv\|os.environ" app/ --include="*.py"

# Check for direct datetime usage (must use time_manager)
grep -rn "datetime.now()\|datetime.utcnow()" app/ --include="*.py"
```

## Compliance Checklist

### 1. Secrets Management (CRITICAL)
- [ ] **No hardcoded secrets** in any Python file
- [ ] **Secrets from environment variables** only — injected at runtime by the deployment platform's secret manager (Vault, K8s secrets, AWS Secrets Manager, GCP Secret Manager, Doppler, …). The app reads `os.environ` only; NO secret-manager SDK dependency.
- [ ] **All required secrets available** (e.g. DB_PASSWORD, JWT_SECRET, HMAC_SECRET, FIELD_ENCRYPTION_KEY — match your project's set)
- [ ] **repr=False** on sensitive fields in the Settings class
- [ ] **No secrets in logs** — check logging statements
- [ ] **No secrets in error responses** — check HTTPException details
- [ ] **No real secrets in `.env`** committed to the repo (only dev-only test values; `.env.example` carries placeholders)

### 2. Request Validation (CRITICAL)
- [ ] **X-Request-ID required** — Middleware validates presence
- [ ] **X-Device-ID required** — Middleware validates presence (except device endpoints)
- [ ] **HMAC validation** on all POST/PUT/PATCH/DELETE endpoints (`Depends(require_hmac)`)
- [ ] **Rate limiting enabled** — Per device_id limiting active
- [ ] **Input validation** — All inputs via Pydantic schemas

### 3. Tenant Isolation (CRITICAL — multi-tenant)
- [ ] **Every business-table query filters by `tenant_id`** from the JWT (`current_user.tenant_id`)
- [ ] **No cross-tenant leak** — no query returns rows from another tenant
- [ ] **Scope enforcement** — where relevant, scope claims from the JWT are enforced
- [ ] **No database RLS** — tenant isolation is app-layer enforced (this project's convention)

### 4. Code Quality Compliance
- [ ] **No print statements** — Zero `print()` in app/
- [ ] **No os.getenv()** — Use `settings.VARIABLE_NAME` only
- [ ] **All imports at top** — No inline imports
- [ ] **Correct import paths** — match your project's module layout
- [ ] **db_session naming** — Not `session` for database sessions
- [ ] **Kwargs logging** — `logger.info("msg", key=value)` style
- [ ] **time_manager usage** — No direct `datetime.now()` calls

### 5. Security Headers
- [ ] **X-Content-Type-Options: nosniff**
- [ ] **X-Frame-Options: DENY**
- [ ] **X-XSS-Protection: 1; mode=block**
- [ ] **Strict-Transport-Security** (when not DEBUG)
- [ ] **Content-Security-Policy**
- [ ] **Referrer-Policy**

### 6. Error Handling
- [ ] **Structured error format** — `{"error": "code", "message": "text"}`
- [ ] **No stack traces** in responses (check DEBUG=False behavior)
- [ ] **No internal details** in error messages
- [ ] **Proper status codes** — 4xx for client errors, 503 for infra only

### 7. Database Security
- [ ] **SQLAlchemy ORM only** — No raw SQL string interpolation
- [ ] **Soft delete only** — business data uses `deleted_at`, never hard `DELETE`
- [ ] **UUID primary keys** — all PKs are UUID v4
- [ ] **Secrets not in connection string** — password from env injection

### 8. Audit Trail (Postgres `audit` schema + stdout)
- [ ] **Audit module exists** — `app/core/audit.py` implemented (a DB-backed audit log)
- [ ] **State changes logged** — CREATE/UPDATE/DELETE operations call `audit_log(...)`
- [ ] **Security events logged** — HMAC failures, rate limit exceeded, unauthorized access
- [ ] **`audit.audit_event_log` table reachable** — verified at startup
- [ ] **Dual write** — PostgreSQL is the durable authoritative record; stdout JSON is forensic backup

### 9. Startup Health Checks
- [ ] **Database check** — Connection verified at startup
- [ ] **Redis check** — Ping verified at startup (REQUIRED, no graceful degradation)
- [ ] **Secrets check** — All required secrets loaded from env
- [ ] **Audit table check** — `audit.audit_event_log` is reachable
- [ ] **Fail fast** — App won't start if any check fails

### 10. Debug Mode Security
- [ ] **/docs, /openapi.json, /redoc, root** all return 404 when DEBUG=False
- [ ] **Detailed errors disabled** when DEBUG=False

### 11. Dependencies
- [ ] **No known vulnerabilities** — pip-audit passes
- [ ] **Dependencies pinned** — Versions in requirements.txt / pyproject

## Severity Levels

### CRITICAL (Fix Immediately)
- Hardcoded/committed secrets · Missing HMAC on a write · Missing `tenant_id` filter · Hard delete on business data · State change without audit · Secrets in logs/responses

### HIGH (Fix Before Merge)
- Missing request validation · Print statements · `os.getenv()` usage · Inline imports · Wrong import paths

### MEDIUM (Fix Soon)
- Missing docstrings · Inconsistent error formats · Missing indexes

### LOW (Technical Debt)
- Code style issues · Minor refactoring

## Audit Report Template

```markdown
# Security Audit Report
Date: YYYY-MM-DD
Auditor: Claude

## Summary
- Critical: X · High: X · Medium: X · Low: X

## Critical Issues
1. [CRITICAL] Description
   - File: path/to/file.py:line
   - Impact: What could happen
   - Fix: How to resolve

## High / Medium / Low Issues
...

## Recommendations
...

## Files Reviewed
...
```

## Automated Checks (run before every PR)

```bash
bandit -r app/ -ll && \
pip-audit && \
black --check app/ tests/ && \
isort --check-only app/ tests/ && \
flake8 app/ tests/ && \
mypy app/ && \
pytest --cov=app --cov-report=term-missing
```

> Coverage floor is single-sourced in `pyproject.toml` `[tool.coverage.report]`
> (`fail_under` + `precision = 2`) — do NOT add a competing `--cov-fail-under` flag to the
> CI test line (the round-up hole). See `docs/AGENT-WORKFLOW.md`.

## Common Violations to Check

### Hardcoded Secrets
```python
HMAC_SECRET = "my-secret-key"          # VIOLATION
hmac_secret = settings.HMAC_SECRET     # CORRECT
```

### Missing tenant filter
```python
select(Item).where(Item.id == id)                                  # VIOLATION (cross-tenant)
select(Item).where(Item.id == id, Item.tenant_id == tenant_id)     # CORRECT
```

### Hard delete
```python
await db_session.delete(item)                  # VIOLATION on business data
item.deleted_at = time_manager.utc_now()       # CORRECT (soft delete)
```

### Wrong import path
```python
from app.core.wrong.logging import get_logger   # VIOLATION (path does not exist)
from app.core.logging import get_logger          # CORRECT
```
