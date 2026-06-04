# Create New Router

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The patterns below (HMAC on writes, tenant_id
> filtering, soft-delete, audit-on-state-change) are illustrative conventions for a
> multi-tenant API — keep what fits your project, drop what doesn't.

Create a new FastAPI router with the given name: $ARGUMENTS

## Instructions

1. Create `app/api/routers/{name}.py` with:
   - Router with appropriate prefix and tags
   - CRUD endpoints following REST conventions
   - Proper type hints and Pydantic schemas
   - Database session as `db_session` (NEVER `session`)
   - HMAC protection on write operations (`dependencies=[Depends(require_hmac)]`)
   - `tenant_id` filtering on every business-table query (tenant isolation)
   - Audit log entry on every state-changing operation
   - Kwargs-style logging

2. Create corresponding Pydantic schemas in `app/schemas/{name}.py`

3. Register the router in `main.py` with prefix `/api/v1`

4. Update the API client collection with new endpoints

## Template Structure

```python
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.audit import AuditAction, audit_log
from app.core.auth import CurrentUser, get_current_user
from app.core.logging import get_logger
from app.core.security import require_hmac
from app.db.database import get_db_session
from app.models.{name} import {Name}
from app.schemas.{name} import {Name}Create, {Name}Response, {Name}Update

logger = get_logger(__name__)
router = APIRouter(prefix="/{names}", tags=["{Names}"])


@router.get("/{id}", response_model={Name}Response)
async def get_{name}(
    id: UUID,
    current_user: CurrentUser = Depends(get_current_user),
    db_session: AsyncSession = Depends(get_db_session),
) -> {Name}Response:
    """Retrieve {name} by ID (scoped to the caller's tenant).

    Args:
        id: UUID of the {name} to retrieve.
        current_user: Authenticated caller (injected).
        db_session: Database session (injected).

    Returns:
        {Name} data.

    Raises:
        HTTPException: 404 if {name} not found in this tenant.
    """
    result = await db_session.execute(
        select({Name}).where(
            {Name}.id == id,
            {Name}.tenant_id == current_user.tenant_id,  # tenant isolation
            {Name}.deleted_at.is_(None),                 # soft-delete aware
        )
    )
    {name} = result.scalar_one_or_none()
    if not {name}:
        raise HTTPException(
            status_code=404,
            detail={"error": "{name}_not_found", "message": "{Name} does not exist"},
        )
    logger.info("{Name} retrieved", {name}_id=str(id))
    return {name}


@router.post(
    "",
    response_model={Name}Response,
    status_code=201,
    dependencies=[Depends(require_hmac)],
)
async def create_{name}(
    data: {Name}Create,
    current_user: CurrentUser = Depends(get_current_user),
    db_session: AsyncSession = Depends(get_db_session),
) -> {Name}Response:
    """Create a new {name} in the caller's tenant.

    Args:
        data: {Name} creation data.
        current_user: Authenticated caller (injected).
        db_session: Database session (injected).

    Returns:
        Created {name} data.
    """
    {name} = {Name}(**data.model_dump(), tenant_id=current_user.tenant_id)
    db_session.add({name})
    await db_session.commit()
    await db_session.refresh({name})
    await audit_log(
        action=AuditAction.CREATE,
        resource_type="{name}",
        resource_id=str({name}.id),
        details={"name": getattr({name}, "name", None)},
    )
    logger.info("{Name} created", {name}_id=str({name}.id))
    return {name}


@router.put(
    "/{id}",
    response_model={Name}Response,
    dependencies=[Depends(require_hmac)],
)
async def update_{name}(
    id: UUID,
    data: {Name}Update,
    current_user: CurrentUser = Depends(get_current_user),
    db_session: AsyncSession = Depends(get_db_session),
) -> {Name}Response:
    """Update an existing {name} (tenant-scoped).

    Args:
        id: UUID of the {name} to update.
        data: {Name} update data.
        current_user: Authenticated caller (injected).
        db_session: Database session (injected).

    Returns:
        Updated {name} data.

    Raises:
        HTTPException: 404 if {name} not found in this tenant.
    """
    result = await db_session.execute(
        select({Name}).where(
            {Name}.id == id,
            {Name}.tenant_id == current_user.tenant_id,
            {Name}.deleted_at.is_(None),
        )
    )
    {name} = result.scalar_one_or_none()
    if not {name}:
        raise HTTPException(
            status_code=404,
            detail={"error": "{name}_not_found", "message": "{Name} does not exist"},
        )
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr({name}, field, value)
    await db_session.commit()
    await db_session.refresh({name})
    await audit_log(
        action=AuditAction.UPDATE,
        resource_type="{name}",
        resource_id=str(id),
        details={"fields_updated": list(data.model_dump(exclude_unset=True).keys())},
    )
    logger.info("{Name} updated", {name}_id=str(id))
    return {name}


@router.delete("/{id}", status_code=204, dependencies=[Depends(require_hmac)])
async def delete_{name}(
    id: UUID,
    current_user: CurrentUser = Depends(get_current_user),
    db_session: AsyncSession = Depends(get_db_session),
) -> None:
    """Soft-delete a {name} (tenant-scoped). NEVER hard-delete business data.

    Args:
        id: UUID of the {name} to delete.
        current_user: Authenticated caller (injected).
        db_session: Database session (injected).

    Raises:
        HTTPException: 404 if {name} not found in this tenant.
    """
    from app.core.utils.time import time_manager

    result = await db_session.execute(
        select({Name}).where(
            {Name}.id == id,
            {Name}.tenant_id == current_user.tenant_id,
            {Name}.deleted_at.is_(None),
        )
    )
    {name} = result.scalar_one_or_none()
    if not {name}:
        raise HTTPException(
            status_code=404,
            detail={"error": "{name}_not_found", "message": "{Name} does not exist"},
        )
    {name}.deleted_at = time_manager.utc_now()  # soft delete, not db_session.delete()
    await db_session.commit()
    await audit_log(
        action=AuditAction.DELETE,
        resource_type="{name}",
        resource_id=str(id),
        details={},
    )
    logger.info("{Name} soft-deleted", {name}_id=str(id))
```

## Schema Template

Create `app/schemas/{name}.py`:

```python
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class {Name}Create(BaseModel):
    """Schema for {name} creation request."""

    name: str


class {Name}Update(BaseModel):
    """Schema for {name} update request (all fields optional for partial update)."""

    name: str | None = None


class {Name}Response(BaseModel):
    """Schema for {name} response."""

    id: UUID
    name: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
```

## Quality Verification Checklist

### Security & Convention Compliance
- [ ] **HMAC Protection**: All POST/PUT/PATCH/DELETE have `dependencies=[Depends(require_hmac)]`
- [ ] **Tenant isolation**: every business-table query filters by `tenant_id` from `current_user`
- [ ] **Soft delete only**: DELETE sets `deleted_at`, never `db_session.delete()` on business data
- [ ] **Audit on state change**: CREATE/UPDATE/DELETE each call `audit_log(...)`
- [ ] **TimeManager**: no `datetime.now()`/`utcnow()` — use `time_manager`
- [ ] **No Hardcoded Secrets**: no credentials/keys/tokens in code
- [ ] **Input Validation**: all inputs via Pydantic schemas
- [ ] **SQL Injection Prevention**: SQLAlchemy ORM only (no raw SQL interpolation)
- [ ] **Error Response Safety**: structured `{"error","message"}`, no stack traces

### Code Quality Compliance
- [ ] **Imports at Top**: no inline imports (the one `time_manager` import inside delete may be hoisted)
- [ ] **Correct import paths**: `app.core.logging`, `app.core.audit`, `app.core.security`
- [ ] **db_session Naming**: database session parameter named `db_session` (not `session`)
- [ ] **Kwargs Logging**: `logger.info("message", key=value)` — no f-strings, no `extra={}`
- [ ] **No Print Statements**: zero `print()` calls
- [ ] **Google-Style Docstrings**: Args/Returns/Raises
- [ ] **Type Hints**: all params and returns typed
- [ ] **Status Codes**: 201 for create, 204 for delete; default 200 otherwise

### Documentation & Testing
- [ ] **Router Registered**: added to main.py with `/api/v1` prefix
- [ ] **Schema/Model Exported**: in `app/schemas/__init__.py` / `app/models/__init__.py`
- [ ] **API client collection Updated**: endpoints + HMAC pre-request scripts
- [ ] **Tests**: `tests/test_api/test_{name}.py` — happy path + 4xx + HMAC + tenant-isolation, ≥90% coverage

## Post-Creation Verification

```bash
black app/api/routers/{name}.py app/schemas/{name}.py
isort app/api/routers/{name}.py app/schemas/{name}.py
flake8 app/api/routers/{name}.py app/schemas/{name}.py
mypy app/
pytest tests/test_api/test_{name}.py -v --cov=app
bandit app/api/routers/{name}.py
```
