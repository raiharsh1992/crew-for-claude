# Create New Model

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The patterns below (tenant_id, soft-delete,
> SQLAlchemy 2.0) are illustrative conventions, not platform law — keep what fits your
> project, drop what doesn't.

Create a new SQLAlchemy model with the given name: $ARGUMENTS

## Instructions

1. Create `app/models/{name}.py` inheriting from `BaseModel`:
   - `BaseModel` provides the UUID primary key + `created_at`/`updated_at` timestamps
   - Use SQLAlchemy 2.0 `Mapped[...]` type hints + `mapped_column(...)`
   - Add `tenant_id` (UUID) on every BUSINESS table — tenant isolation is row-level
   - Add `deleted_at: Mapped[datetime | None]` for soft delete on business data
   - Add appropriate indexes and constraints; Google-style docstring

2. Export the model in `app/models/__init__.py`

3. Generate Alembic migration (MANUAL — never auto-apply):
   ```bash
   alembic revision --autogenerate -m "Add {name} table"
   ```

4. Review the migration file before applying, then:
   ```bash
   alembic upgrade head
   ```

## Template Structure

```python
from datetime import datetime
from uuid import UUID as PyUUID

from sqlalchemy import DateTime, Index, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import BaseModel


class {Name}(BaseModel):
    """{Name} database model.

    Attributes:
        tenant_id: Owning tenant (row-level isolation).
        name: Display name of the {name}.
        deleted_at: Soft-delete marker; None means active.
    """

    __tablename__ = "{names}"

    tenant_id: Mapped[PyUUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        Index("ix_{names}_tenant_id", "tenant_id"),
        Index("ix_{names}_name", "name"),
    )

    def __repr__(self) -> str:
        """Return string representation of {Name}."""
        return f"<{Name}(id={self.id}, name={self.name})>"
```

## Common Column Types

```python
from decimal import Decimal

from sqlalchemy import Boolean, ForeignKey, Integer, Numeric, Text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID

name: Mapped[str] = mapped_column(String(255), nullable=False)
description: Mapped[str | None] = mapped_column(Text, nullable=True)
amount: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)   # money: Numeric, never float
is_active: Mapped[bool] = mapped_column(Boolean, default=True)
metadata_: Mapped[dict] = mapped_column(JSONB, default=dict)
tags: Mapped[list] = mapped_column(ARRAY(String), default=list)
parent_id: Mapped[PyUUID] = mapped_column(
    UUID(as_uuid=True), ForeignKey("parents.id", ondelete="CASCADE"), nullable=False
)
```

## Quality Verification Checklist

### Model Compliance
- [ ] **Inherits BaseModel** (UUID PK + timestamps)
- [ ] **Mapped Type Hints** on all columns
- [ ] **tenant_id present** on business tables (+ indexed)
- [ ] **deleted_at present** for soft delete on business data
- [ ] **Table Name** lowercase plural
- [ ] **Google Docstring** with Attributes
- [ ] **Indexes** on frequently queried columns (incl. tenant_id)
- [ ] **Money columns** use `Numeric`, never float

### Code Quality
- [ ] **Imports at top** · **No print** · **Type hints** · **`__repr__` defined**

### Migration
- [ ] **Export Added** in `app/models/__init__.py`
- [ ] **Migration Created** (`alembic revision --autogenerate`)
- [ ] **Migration Reviewed** manually before applying
- [ ] **Upgrade + Downgrade tested** on dev DB

## Post-Creation Steps

```bash
black app/models/{name}.py && isort app/models/{name}.py
flake8 app/models/{name}.py && mypy app/
alembic revision --autogenerate -m "Add {name} table"
# review alembic/versions/*, then:
alembic upgrade head
```

## Export Model

```python
# app/models/__init__.py
from app.models.{name} import {Name}

__all__ = [
    # ... existing ...
    "{Name}",
]
```
