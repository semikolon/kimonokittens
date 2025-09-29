# PostgreSQL Generated Columns in Prisma

## ⚠️ Critical Issue: Prisma Introspection Bug

**Problem**: Prisma's `db pull` command incorrectly introspects PostgreSQL `GENERATED ALWAYS AS` columns as `@default(dbgenerated(...))`, which creates invalid migration SQL that fails to deploy.

**GitHub Issue**: https://github.com/prisma/prisma/issues/23308 (Open since Feb 2024)

## Example: RentConfig.period_month

### Actual Database Schema (Correct):
```sql
"period_month" DATE GENERATED ALWAYS AS ((date_trunc('month'::text, period))::date) STORED
```

### Prisma Introspection Result (Incorrect):
```prisma
period_month DateTime? @default(dbgenerated("(date_trunc('month'::text, period))::date")) @db.Date
```

### Migration SQL Generated (Broken):
```sql
"period_month" DATE DEFAULT (date_trunc('month'::text, period))::date
-- ERROR: cannot use column reference in DEFAULT expression
```

## Solution

### 1. Schema Definition
In `prisma/schema.prisma`, define generated columns as simple nullable fields:

```prisma
model RentConfig {
  // ... other fields
  period       DateTime  @default(now())
  period_month DateTime? @db.Date  // No @default() annotation!

  @@unique([key, period_month])
}
```

### 2. Manual Migration Editing
After running `npx prisma migrate diff` or `migrate dev --create-only`, manually edit the migration SQL to add `GENERATED ALWAYS AS`:

```sql
CREATE TABLE "RentConfig" (
    -- ... other columns
    "period" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "period_month" DATE GENERATED ALWAYS AS ((date_trunc('month'::text, period))::date) STORED,
    -- ... constraints
);
```

### 3. After Running `prisma db pull`
**NEVER trust the introspected result for generated columns!**

Check for any `@default(dbgenerated(...))` with column references and:
1. Remove the `@default(dbgenerated(...))` annotation
2. Keep only the `@db.Date` (or appropriate type)
3. Manually verify/edit the migration SQL

## Prevention Checklist

✅ **Before committing migrations:**
1. Check migration SQL for `DEFAULT` with column references
2. Replace with `GENERATED ALWAYS AS ... STORED`
3. Test migration on clean database
4. Verify generated column works as expected

✅ **After running `prisma db pull`:**
1. Search schema for `@default(dbgenerated(`
2. Inspect actual database column definition
3. If it's `GENERATED ALWAYS`, remove Prisma's incorrect annotation
4. Document in this file

## Why PostgreSQL Requires GENERATED ALWAYS

PostgreSQL doesn't allow column references in `DEFAULT` expressions because:
- DEFAULT is evaluated once at row insertion
- Column references would create circular dependencies
- GENERATED columns are computed automatically on every read/write

## Alternative Approaches

If you can't use manual SQL editing:

### Option A: Triggers (More Complex)
```sql
CREATE TRIGGER set_period_month
BEFORE INSERT OR UPDATE ON "RentConfig"
FOR EACH ROW
EXECUTE FUNCTION update_period_month();
```

### Option B: Application Logic (Less Efficient)
Handle `period_month` calculation in your application code before insert/update.

### Option C: Wait for Prisma Support
Track https://github.com/prisma/prisma/issues/6336 for native generated column support.

## Current Status

- **Prisma Version**: Check `package.json` for current version
- **PostgreSQL Version**: 16+ (supports GENERATED columns)
- **Workaround Status**: ✅ Working (manual migration editing)
- **Native Support**: ❌ Not available (as of 2024)

## Related Issues

- Prisma #23308: `prisma db pull` returns GENERATED ALWAYS AS as DEFAULT
- Prisma #6336: Generated columns feature request
- Prisma #18659: `@default(dbgenerated(...))` causes endless migration changes

---

**Last Updated**: 2025-09-30
**Tested With**: PostgreSQL 16, Prisma 6.x