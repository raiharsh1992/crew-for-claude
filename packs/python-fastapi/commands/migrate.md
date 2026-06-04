# Database Migration

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The Alembic patterns below are this pack's
> default — keep what fits your project, drop what doesn't.

Create and apply database migrations: $ARGUMENTS

**IMPORTANT:** Migrations are ALWAYS MANUAL — review before applying. A migration is a
FULL-tier change (touches schema); update the service's CONTEXT.md in the same PR if
tables/columns change.

## Usage

- `/migrate create "Add users table"` — Create a new migration
- `/migrate up` — Apply all pending migrations
- `/migrate down` — Rollback last migration
- `/migrate status` — Show current migration status

## Commands

### Create
```bash
alembic revision --autogenerate -m "{message}"
```

### Apply
```bash
alembic upgrade head
```

### Rollback
```bash
alembic downgrade -1            # one step
alembic downgrade {revision}    # to a specific revision
# NOTE: `alembic downgrade base` may be blocked by a dangerous-command hook (irreversible).
```

### Status
```bash
alembic current
alembic history --indicate-current
alembic heads
```

## Migration Workflow

1. **Create / update the model** (`app/models/<name>.py`) with `tenant_id` + `deleted_at` on business tables.
2. **Export it** in `app/models/__init__.py`.
3. **Generate**: `alembic revision --autogenerate -m "Add <name> table"`.
4. **Review the generated file** (CRITICAL):
   - Correct table/column names + types
   - Indexes included (incl. `tenant_id`)
   - Foreign keys have proper `ondelete`
   - No destructive change unless intended
   - The first/baseline migration is NEVER edited/renamed; business schema starts after it
5. **Test**: `alembic upgrade head`, verify schema, `alembic downgrade -1`, re-apply.
6. **Update CONTEXT.md** in the same PR if the schema changed (binding freshness rule).

## Common Migration Patterns

### Add Column + Index
```python
def upgrade():
    op.add_column('items', sa.Column('email', sa.String(255), nullable=True))
    op.create_index('ix_items_email', 'items', ['email'])

def downgrade():
    op.drop_index('ix_items_email', 'items')
    op.drop_column('items', 'email')
```

### Make Column Non-Nullable (backfill first)
```python
def upgrade():
    op.execute("UPDATE items SET email = 'unknown@example.com' WHERE email IS NULL")
    op.alter_column('items', 'email', nullable=False)

def downgrade():
    op.alter_column('items', 'email', nullable=True)
```

### Create Table with tenant_id + soft-delete
```python
def upgrade():
    op.create_table(
        'items',
        sa.Column('id', sa.UUID(), primary_key=True),
        sa.Column('tenant_id', sa.UUID(), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index('ix_items_tenant_id', 'items', ['tenant_id'])

def downgrade():
    op.drop_index('ix_items_tenant_id', 'items')
    op.drop_table('items')
```

## Quality Verification Checklist

- [ ] **Model exported** in `app/models/__init__.py`
- [ ] **Table name** lowercase plural; **tenant_id** + index present (business tables)
- [ ] **Column types** match the model; **indexes** created/dropped symmetrically
- [ ] **Foreign keys** with correct `ondelete`
- [ ] **No data loss** — review any ALTER/DROP
- [ ] **Upgrade works** · **Downgrade works** · **App starts** · **Tests pass**
- [ ] **CONTEXT.md updated** if schema changed

## Troubleshooting

- **"Target database is not up to date"** → `alembic current` then `alembic upgrade head`
- **"Can't locate revision"** → `alembic history`; `alembic stamp {rev}` if needed
- **"Model changes not detected"** → ensure model imported in `__init__.py`; check `alembic/env.py`
- **"Multiple heads"** → `alembic heads` then `alembic merge heads -m "Merge migrations"`

## Safety Rules

1. **Never auto-migrate** — always review before applying
2. **Test rollback** before production
3. **No destructive change in production** without a planned data migration
4. **One logical schema change per migration**
