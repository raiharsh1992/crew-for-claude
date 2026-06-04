# Security & Compliance Audit

Perform a comprehensive security and code compliance audit of the codebase: $ARGUMENTS

**This is a core audit checklist suitable for any project.** Stack-specific scanning tools
(language/framework-particular linters, security analyzers) belong in packs — see the
examples below and adapt them for your toolchain.

## Quick Scan Commands (Python examples)

```bash
# Security vulnerability scan
bandit -r app/ -ll

# Check for vulnerable dependencies
pip-audit

# Check for hardcoded secrets
git grep -n "password\|secret\|key\|token" -- "*.py" | grep -v "# " | grep -v "__" | grep -v "settings\."

# Check for print statements
grep -rn "print(" app/ --include="*.py"

# Check for environment variable access
grep -rn "os.getenv\|os.environ" app/ --include="*.py"
```

**Note:** Replace with your language's tools (Node: `npm audit`, Go: `gosec`, Rust: `cargo audit`, etc.).

## Compliance Checklist

### 1. Secrets Management (CRITICAL)
- [ ] **No hardcoded secrets** in source code
- [ ] **Secrets from environment variables only** — injected at runtime by the deployment
  platform's secret manager (Vault, K8s secrets, AWS Secrets Manager, GCP Secret Manager,
  HashiCorp Consul, etc.). The app reads env vars only; NO secret-manager SDK dependency.
- [ ] **All required secrets available** — verify each is injected at runtime
- [ ] **repr=False on sensitive fields** (if applicable to language/framework)
- [ ] **No secrets in logs** — check logging statements
- [ ] **No secrets in error responses** — check exception details
- [ ] **No real secrets in version-controlled config** (only dev-only test placeholders;
  `.env.example` carries placeholders, never real values)

### 2. Request Validation (CRITICAL)
- [ ] **Required headers validated** — Middleware/interceptor enforces presence (e.g.,
  request ID, device ID)
- [ ] **Signature/HMAC validation** on state-changing operations (POST/PUT/PATCH/DELETE)
- [ ] **Rate limiting enabled** — Per client/user limiting active
- [ ] **Input validation** — All inputs validated against schema (Pydantic, Zod, struct tags, etc.)

### 3. Multi-Tenant Isolation (if applicable)
- [ ] **Every business-domain-table query filters by tenant/org/workspace** from the
  authenticated context
- [ ] **No cross-tenant data leak** — no query returns rows from another tenant
- [ ] **Scoping enforcement** — where applicable (e.g., centers, divisions), filter by the
  authenticated principal's scope
- [ ] **App-layer isolation, not database RLS** — tenant isolation is code-enforced

### 4. Code Quality Compliance
- [ ] **No debug prints** — Zero `print()`/`console.log()`/`fmt.Println()` in production code
- [ ] **No direct env access in code** — Use configuration/settings object only
- [ ] **All imports organized** — No inline imports
- [ ] **Correct module paths** — No typos or broken imports
- [ ] **Consistent session/connection naming** — Not reused generically
- [ ] **Structured logging** — Use named fields, not string concatenation
- [ ] **Time handling** — Use a centralized time manager, not `now()` inline

### 5. Security Headers (HTTP)
- [ ] **X-Content-Type-Options: nosniff**
- [ ] **X-Frame-Options: DENY**
- [ ] **X-XSS-Protection: 1; mode=block** (or CSP equivalent)
- [ ] **Strict-Transport-Security** (when not in dev/debug mode)
- [ ] **Content-Security-Policy**
- [ ] **Referrer-Policy**

### 6. Error Handling
- [ ] **Structured error format** — Consistent JSON/XML shape: `{"error": "code", "message": "text"}`
- [ ] **No stack traces** in user-facing responses (debug mode excluded)
- [ ] **No internal details** in error messages
- [ ] **Proper status codes** — 4xx for client errors, 5xx for server (not 200 with error body)

### 7. Database Security
- [ ] **Parameterized queries only** — No string interpolation in SQL
- [ ] **Soft delete pattern** — Business data uses a tombstone flag (e.g., `deleted_at`),
  never hard `DELETE`
- [ ] **UUID primary keys** — All PKs are UUID v4 or equivalent
- [ ] **Secrets not in connection strings** — Password/credentials from env injection

### 8. Audit Trail
- [ ] **State changes logged** — CREATE/UPDATE/DELETE operations recorded (to database,
  stdout, or both)
- [ ] **Security events logged** — Authentication failures, authorization denials, validation
  failures
- [ ] **Audit records queryable** — At startup, verify access to audit logs
- [ ] **Tamper-resistant storage** — If using a database, append-only pattern; if stdout,
  forwarded to immutable log store

### 9. Startup Health Checks
- [ ] **Database connectivity** verified at startup
- [ ] **Required external dependencies** (cache, message queue) verified at startup
- [ ] **All required secrets loaded** from environment
- [ ] **Audit subsystem reachable** — verified at startup
- [ ] **Fail fast** — App won't start if any critical check fails

### 10. Debug Mode Security
- [ ] **Developer endpoints** (docs, OpenAPI, REPL, root) return 404 in production
  (DEBUG=False)
- [ ] **Detailed error responses disabled** in production

### 11. Dependencies
- [ ] **No known vulnerabilities** — Audit tool passes (pip-audit, npm audit, cargo audit, etc.)
- [ ] **Dependencies pinned** — Versions locked in `requirements.txt`, `package.json`, `Cargo.lock`, etc.

## Severity Levels

### CRITICAL (Fix Immediately)
- Hardcoded/committed secrets
- Missing signature/HMAC on state-changing operations
- Missing tenant/scope filter on business-data query
- Hard delete on business data
- State change without audit
- Secrets in logs or responses

### HIGH (Fix Before Merge)
- Missing request validation
- Debug prints in code
- Direct env access (not through config object)
- Inline imports
- Wrong module paths

### MEDIUM (Fix Soon)
- Missing docstrings
- Inconsistent error formats
- Missing database indexes

### LOW (Technical Debt)
- Code style issues
- Minor refactoring

## Audit Report Template

```markdown
# Security Audit Report
Date: YYYY-MM-DD
Auditor: <name or automated tool>

## Summary
- Critical: X · High: X · Medium: X · Low: X

## Critical Issues
1. [CRITICAL] Issue description
   - Location: file:line (or module path)
   - Impact: What could happen if not fixed
   - Fix: How to resolve

## High / Medium / Low Issues
...

## Recommendations
...

## Files Reviewed
- file1
- file2
...
```

## Automated Checks (stack-agnostic template)

Replace tool names with your stack's equivalents:
- **Secrets scanner:** `bandit` (Python), `npm-audit` (Node), `cargo audit` (Rust), etc.
- **Linter:** `black`, `pylint` (Python), `eslint` (Node), `rustfmt` (Rust), etc.
- **Type checker:** `mypy` (Python), `tsc` (TypeScript), `cargo check` (Rust), etc.
- **Test runner:** `pytest` (Python), `jest` (Node), `cargo test` (Rust), etc.

Example (Python):
```bash
bandit -r app/ -ll && \
pip-audit && \
black --check app/ tests/ && \
mypy app/ && \
pytest --cov=app --cov-report=term-missing
```

> Coverage floor is configured in your project settings (single source of truth). Do NOT
> add competing flags to CI.

## Common Violations to Check

### Hardcoded Secrets
```python
API_KEY = "sk-1234567890abcdef"   # VIOLATION
api_key = settings.API_KEY        # CORRECT
```

### Missing scope filter
```python
# VIOLATION: cross-tenant leak
select(Item).where(Item.id == id)

# CORRECT: tenant-scoped
select(Item).where(
    Item.id == id,
    Item.tenant_id == current_user.tenant_id
)
```

### Hard delete on business data
```python
# VIOLATION
delete(item)

# CORRECT (soft delete)
item.deleted_at = utc_now()
```

### Debug print in code
```python
# VIOLATION
print(f"Processing {item_id}")  

# CORRECT
logger.info("Processing", item_id=item_id)
```
