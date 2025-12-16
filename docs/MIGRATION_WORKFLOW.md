# Migration Workflow: Prisma + Supabase

This document explains the workflow for database schema changes using Prisma migrations with separate local and production databases.

## Quick Reference

| Environment | Database                       | Command                                       |
| ----------- | ------------------------------ | --------------------------------------------- |
| Local Dev   | Supabase CLI (localhost:54422) | `npx prisma migrate dev --name <description>` |
| Production  | Supabase Cloud                 | `npx prisma migrate deploy`                   |

---

## Local Development Setup

### Prerequisites

1. **Supabase CLI** (already configured in this project)
2. **Docker Desktop** (required for local Supabase)

### Start Local Supabase

```bash
cd /Users/evandeutsch/vibe-runner && npx supabase start
```

### Environment Files

- **`packages/db/.env`** - Local development (points to `localhost:54422`)
- **Production** - Set via Doppler or deployment environment

---

## Development Workflow

### 1. Start Local Supabase

```bash
npx supabase start
```

### 2. Make Schema Changes

Edit `packages/db/prisma/schema.prisma`:

```prisma
model NewTable {
  id        String   @id @default(uuid())
  name      String
  createdAt DateTime @default(now()) @map("created_at")

  @@map("new_table")
  @@schema("public")
}
```

### 3. Create and Apply Migration (Local)

```bash
cd packages/db
npx prisma migrate dev --name add_new_table
```

This:

- Creates a migration file in `prisma/migrations/`
- Applies it to your **local** database only
- Regenerates Prisma Client

### 4. Test Locally

```bash
npm run dev
```

### 5. Commit and Push

```bash
git add packages/db/prisma/migrations/ packages/db/prisma/schema.prisma
git commit -m "Add new_table to database"
git push
```

### 6. Deploy to Production

Apply migrations to production:

```bash
# Set production env vars (via Doppler or export)
npx prisma migrate deploy
```

---

## Customizing Migrations

For complex changes (data migrations, column renames):

```bash
# Create migration without applying
npx prisma migrate dev --name rename_column --create-only

# Edit the generated SQL in prisma/migrations/<timestamp>_rename_column/migration.sql

# Apply the edited migration
npx prisma migrate dev
```

---

## Environment Configuration

### Local Development

```env
DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:54422/postgres"
DIRECT_URL="postgresql://postgres:postgres@127.0.0.1:54422/postgres"
```

### Production (via Doppler/Vercel)

```env
DATABASE_URL="postgresql://...@pooler.supabase.com:6543/postgres?pgbouncer=true"
DIRECT_URL="postgresql://...@pooler.supabase.com:5432/postgres"
```

**Note:** `DATABASE_URL` uses the pooler (pgbouncer) for app connections. `DIRECT_URL` bypasses pooler for migrations.

---

## Handling Schema Drift

### Local Database Reset

```bash
# Reset local database (destroys local data only)
cd packages/db
npx prisma migrate reset
```

### Production Drift (rare)

If production drifted, baseline it:

```bash
# 1. Pull current schema
npx prisma db pull

# 2. Generate baseline migration
mkdir -p prisma/migrations/0_baseline
npx prisma migrate diff \
  --from-empty \
  --to-schema-datamodel prisma/schema.prisma \
  --script > prisma/migrations/0_baseline/migration.sql

# 3. Mark as already applied
npx prisma migrate resolve --applied 0_baseline
```

---

## Command Reference

| Command                            | Use Case                                 |
| ---------------------------------- | ---------------------------------------- |
| `npx supabase start`               | Start local Supabase stack               |
| `npx supabase stop`                | Stop local Supabase                      |
| `npx supabase status`              | Show local Supabase URLs and credentials |
| `prisma migrate dev --name X`      | Create + apply migration locally         |
| `prisma migrate dev --create-only` | Create migration without applying        |
| `prisma migrate deploy`            | Apply migrations (production only)       |
| `prisma migrate status`            | Check migration status                   |
| `prisma migrate reset`             | Reset local database                     |
| `prisma generate`                  | Regenerate Prisma Client                 |

---

## What NOT to Do

- **Never** run `prisma migrate dev` in production
- **Never** run `prisma migrate reset` in production
- **Never** edit migration files after they've been applied anywhere
- **Never** delete migration files that exist in production

---

## Supabase-Specific Features

Prisma handles schema changes. Use **Supabase SQL** only for:

- Row Level Security (RLS) policies
- SECURITY DEFINER functions
- Database triggers

---

## Complete Workflow Summary

```
LOCAL DEVELOPMENT
─────────────────
1. supabase start              (start local DB)
2. Edit prisma/schema.prisma
3. prisma migrate dev --name X (create + apply locally)
4. npm run dev                 (test locally)
5. git commit + push
        │
        ▼
PRODUCTION
──────────
1. Merge PR / push to main
2. prisma migrate deploy       (applies pending migrations)
3. Deploy app
```
