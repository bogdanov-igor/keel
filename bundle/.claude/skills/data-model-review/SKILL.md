---
name: data-model-review
description: Review database schema (migrations or ORM schema) for missing foreign keys, index gaps, constraint holes, and multi-tenant isolation; graded findings with additive migration hints land in BACKLOG.md.
---

# Data model review

Static review of schema files — grep/text analysis only, deterministic
for a given schema state. Postgres is the default dialect; RLS checks
apply to Postgres only (sqlite/mysql skip step 6).

## Before starting

- Establish scope: schema locations (typical: `supabase/migrations/`,
  `prisma/schema.prisma`, `db/schema.sql`), the tenant-scoping column
  (default `project_id`), and the dialect.
- Read the matching section of `memory/MEMORY.md` and grep `memory/`
  for prior schema lessons on this project.
- If no schema files exist at any expected path, stop and ask the owner
  for the correct location instead of guessing.

## Procedure

Keep intermediates in a scratch dir (`S=$(mktemp -d)`); evidence cited
in findings is the real migration file `path:line`, not scratch files.

1. Collect schema files.
   ```bash
   find . -path "*/migrations/*.sql" -o -name "schema.prisma" \
     -o -name "schema.sql" | sort > "$S/files.txt"
   ```
2. Table inventory.
   ```bash
   xargs grep -hEo 'CREATE TABLE (IF NOT EXISTS )?"?\w+"?' < "$S/files.txt" |
     awk '{print $NF}' | tr -d '"' | sort -u > "$S/tables.txt"
   ```
3. Foreign keys. Flag `*_id` columns of type uuid/integer/bigint that
   have no `REFERENCES` inline and no matching `FOREIGN KEY` constraint
   anywhere in the migration history — later `ALTER TABLE` migrations
   often add the constraint, so confirm absence before flagging.
4. Index coverage. Every FK / `*_id` column and hot filter column should
   appear in some `CREATE [UNIQUE] INDEX`. Unindexed FK columns are the
   classic source of slow joins and slow cascade deletes.
5. Tenant column. Each business table carries the tenant column, NOT
   NULL, and indexed — usually as the leading column of a composite
   index.
6. RLS (Postgres). Diff the table inventory against tables with
   `ENABLE ROW LEVEL SECURITY`; a tenant-scoped table without RLS is a
   finding. Prefer `FORCE ROW LEVEL SECURITY` as well, so the table
   owner is not exempt.
7. NOT NULL gaps. Columns that semantically require a value — FK
   columns, the tenant column, `created_at` / `updated_at` — lacking
   NOT NULL (and a default for the timestamps).
8. Normalization smells. Repeated column groups (`phone1`, `phone2`),
   JSON blobs that get filtered or joined on, duplicated denormalized
   values with no stated reason.

## Grading

- P0 — tenant table without RLS, or tenant column missing/nullable:
  cross-tenant data exposure risk.
- P1 — missing FK constraint on a relationship column; unindexed
  tenant column.
- P2 — unindexed FK column; NOT NULL gaps on required columns.
- P3 — normalization smells, naming inconsistencies.

## Output

One `BACKLOG.md` line per finding, migration hint inline:

```
- [ ] P0 | db-schema | monitors: tenant col project_id but no RLS — fix: ALTER TABLE monitors ENABLE ROW LEVEL SECURITY; ALTER TABLE monitors FORCE ROW LEVEL SECURITY; | ev:supabase/migrations/0007_monitors.sql:12 | src:data-model-review
```

Report totals honestly: N tables reviewed, counts per grade, and what
the scope did not cover. Fixes spanning several tables or needing a
data backfill are big work — skill `stage`. A recurring schema trap
worth keeping goes to memory via skill `remember`.

## Anti-patterns

- No destructive hints: migration hints are additive SQL only — never
  DROP TABLE / DROP COLUMN.
- Don't flag system tables (`pg_catalog`, `information_schema`) or
  migration-tracking tables.
- Don't infer a missing FK from a column name alone; confirm no
  constraint exists anywhere in the schema first.
- Don't accept application-level tenant filtering as a substitute for
  RLS — both are needed.
