# Handbook Project Instructions

## ARCHITECTURAL CHANGE - September 29, 2025 ⚠️

**CRITICAL**: The Prisma schema has been moved from `handbook/prisma/` to top-level `/prisma/`

**Reason**:
- Shared database architecture across entire monorepo (dashboard, handbook, rent calculator)
- Eliminates technical debt of having shared schema buried in one subproject
- Clarifies that database is a monorepo-wide resource

**Impact on Handbook**:
- Prisma schema now at `../prisma/schema.prisma` (relative to handbook/)
- Database migrations run from monorepo root: `npx prisma migrate deploy`
- Prisma client generation: `npx prisma generate` (from root)

**References that may need updating**:
- package.json scripts that reference `./prisma`
- Any imports that reference local prisma directory
- Development and build scripts

**Shared Tables**:
- `Tenant` - Roommate/resident information
- `RentLedger` - Historical rent payments
- `RentConfig` - Rent calculation configuration
- `CoOwnedItem` - Shared household items

This change maintains the handbook's functionality while properly organizing the shared database schema at the monorepo level.