# Database Migration

Create and apply database migrations: $ARGUMENTS

**IMPORTANT:** Migrations are ALWAYS MANUAL — review the generated migration before
applying. A migration is a FULL-tier change (touches schema); update the project's
CONTEXT.md in the same PR if tables/columns change.

## Usage

- `/migrate create "<message>"` — Create a new migration
- `/migrate up` — Apply all pending migrations
- `/migrate down` — Rollback last migration
- `/migrate status` — Show current migration status

**Tool-specific syntax** (e.g., `alembic`, `flyway`, `liquibase`) belongs in your
stack's language pack. This document covers the generic workflow and safety rules.

## Generic Migration Workflow

1. **Create or update the model** with the new field, table, or constraint.
2. **Export it** in your project's models module.
3. **Generate the migration** using your tool's autogenerate feature.
4. **Review the generated migration file** (CRITICAL):
   - Correct table/column names and types
   - Indexes included (especially on scoping fields like `tenant_id`)
   - Foreign keys have proper cascading behavior (`ondelete` rules)
   - No destructive change unless intentional
   - First migration (the bootstrap) is NEVER edited; new changes start in a separate
     migration
5. **Test the migration locally:**
   - Apply: `$MIGRATION_TOOL upgrade head`
   - Verify schema changed correctly
   - Rollback: `$MIGRATION_TOOL downgrade -1`
   - Re-apply and verify: `$MIGRATION_TOOL upgrade head`
6. **Update CONTEXT.md** in the same PR if the schema changed (binding freshness rule).

**Replace `$MIGRATION_TOOL` with your tool** (e.g., `alembic`, `flyway`, `liquibase`,
`db-migrate`, etc.). The commands vary; your language pack provides tool-specific syntax.

## Common Migration Patterns

### Add Column + Index
```
upgrade:
  - add column "email" (VARCHAR/STRING)
  - create index on (email)

downgrade:
  - drop index
  - drop column
```

### Make Column Non-Nullable (backfill first)
```
upgrade:
  - set all NULL values to a safe default
  - alter column to NOT NULL

downgrade:
  - alter column back to NULLABLE
```

### Create Table with Scoping + Soft Delete
```
Table "items":
  - id (UUID, primary key)
  - tenant_id (UUID, NOT NULL, indexed) — for multi-tenant scoping
  - name (VARCHAR/STRING, NOT NULL)
  - deleted_at (TIMESTAMP, nullable) — for soft delete pattern
  - created_at (TIMESTAMP, default=now())
  - updated_at (TIMESTAMP, default=now())
```

## Quality Verification Checklist

- [ ] **Model exported** in the project's models module
- [ ] **Table/column names** correct; **scoping fields** (tenant_id, org_id) + indexes present
- [ ] **Column types** match the model; **indexes** created/dropped symmetrically
- [ ] **Foreign keys** with correct cascading behavior
- [ ] **No data loss** — review any ALTER/DROP
- [ ] **Upgrade works** · **Downgrade works** · **App starts** · **Tests pass**
- [ ] **CONTEXT.md updated** if schema changed

## Troubleshooting

- **"Database is behind"** → Run status to see current, then apply pending
- **"Can't find migration"** → List migration history; stamp if needed
- **"Model changes not detected"** → Ensure model is exported; check migration tool config
- **"Multiple migration heads"** → Merge conflicts in migrations; resolve and consolidate

## Safety Rules (generic, not tool-specific)

These apply regardless of migration tool:

1. **Never auto-apply migrations** — always review the generated SQL/DDL before applying
2. **Test rollback** in a development environment before production
3. **No destructive change in production** without a planned data migration / backfill
4. **One logical schema change per migration** — keep migrations focused

### Examples

**BAD (one migration doing too much):**
```
Create users table + create roles table + add email column to existing table + rename column
```

**GOOD (one migration per logical change):**
```
Migration 1: Create users table
Migration 2: Create roles table
Migration 3: Add email column
Migration 4: Rename column
```

This lets you roll back individual changes if needed and keeps the revision history clear.
