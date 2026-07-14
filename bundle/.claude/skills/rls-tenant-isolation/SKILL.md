---
name: rls-tenant-isolation
description: Migrate a Supabase request path from service-role admin client to row-scoped client with enforced RLS, and assert no anon USING(true) policies remain on touched tables.
---

# rls-tenant-isolation

Closes the most common multi-tenant hole in Supabase apps: a request handler
using the service-role (admin) client, which bypasses RLS entirely, or tables
carrying trivial `USING (true)` policies for `anon`.

## Before starting, pin down

- **request path** — the handler file (or glob) to migrate
- **tables** — every table that path touches
- **tenant column** — the scoping column (`project_id`, `org_id`, ...)
- **auth context** — SQL expression yielding the tenant id (`auth.uid()`,
  `request.jwt() ->> 'org_id'`, ...). In org-based tenancy `auth.uid()` is
  usually NOT the tenant column — take the expression literally, don't assume.
- **migration dir** — default `supabase/migrations`

Migrating several request paths or a whole schema is multi-unit work — run it
via skill stage. Read the matching section of memory/MEMORY.md and grep
memory/ for prior RLS/tenancy notes before touching policies.

## Steps

1. **Inventory admin-client usage.**
   ```bash
   grep -nE "createAdminClient|createServiceRoleClient|supabaseAdmin" <request_path>
   ```
   Zero matches → the path already uses a scoped client; done, note it and exit.

2. **Audit existing RLS per table.** For each table:
   ```bash
   grep -rE "CREATE POLICY.*ON\s+(public\.)?<table>" <migration_dir>/*.sql
   ```
   and within those matches look for the vulnerability marker:
   ```bash
   grep -E "USING\s*\(\s*true\s*\)"
   ```

3. **Generate migration SQL.** For each table missing tenant-scoped RLS:
   ```sql
   DROP POLICY IF EXISTS "<table>_anon_select" ON public.<table>;
   ALTER TABLE public.<table> ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.<table> FORCE ROW LEVEL SECURITY;
   CREATE POLICY "<table>_tenant_select" ON public.<table>
     FOR SELECT TO authenticated USING (<tenant_column> = (<auth_context>));
   CREATE POLICY "<table>_tenant_insert" ON public.<table>
     FOR INSERT TO authenticated WITH CHECK (<tenant_column> = (<auth_context>));
   CREATE POLICY "<table>_tenant_update" ON public.<table>
     FOR UPDATE TO authenticated
     USING (<tenant_column> = (<auth_context>))
     WITH CHECK (<tenant_column> = (<auth_context>));
   CREATE POLICY "<table>_tenant_delete" ON public.<table>
     FOR DELETE TO authenticated USING (<tenant_column> = (<auth_context>));
   CREATE POLICY "<table>_service_role_all" ON public.<table>
     FOR ALL TO service_role USING (true) WITH CHECK (true);
   ```
   Write to the next sequential migration file.

4. **Replace the admin client in the request path.** Swap `createAdminClient()`
   for `createClient()` and make sure the handler passes the user JWT. Leave
   webhook/cron admin-client calls in place with a `// JUSTIFIED:` comment —
   they have no user JWT and legitimately need service-role. Database
   credentials, if needed, come from `.secrets.env` via `{{secret:KEY}}`.

5. **Post-migration verification.**
   ```bash
   grep -rE "TO\s+(anon|public).*USING\s*\(\s*true\s*\)" <migration_dir>/*.sql | grep -i <table>
   grep -cE "createAdminClient|createServiceRoleClient" <request_path>
   ```
   Expect zero anon `USING (true)` hits per touched table and zero unjustified
   admin-client calls remaining.

## Outcome

- **Passed** — no unjustified admin-client calls, no anon `USING (true)` on
  touched tables, and FORCE RLS enabled on all of them. Summarize in one line
  (calls replaced, tables migrated, migration file path).
- **Failed / partial** — each remaining gap becomes a BACKLOG.md line:
  `- [ ] P0 | <table or handler> | <one line> | ev:<migration or handler path> | src:rls-tenant-isolation`
  (anon `USING (true)` and unjustified admin calls are P0 — they are live
  cross-tenant reads).
- **Needs design** — hierarchical tenancy or shared resources that a single
  column predicate can't express: stop, add a P1 BACKLOG.md line for manual
  RLS design instead of shipping a wrong policy.

If the migration taught something non-obvious (an odd auth context, a table
that resisted the standard predicate), record it via skill remember.
A natural follow-up is a data-model review of full schema RLS coverage.

## Anti-patterns

- Do not replace the admin client in webhook or cron handlers; those lack a
  user JWT and need service-role.
- Do not create `USING (true)` for the `anon` role — that is the exact
  vulnerability this skill fixes.
- Do not rely on application-level filtering as a substitute for RLS;
  database enforcement is the boundary.
- Do not use `FORCE ROW LEVEL SECURITY` without a `service_role` bypass
  policy — admin tooling will break.
- Do not assume `auth.uid()` equals the tenant column in org-based tenancy;
  use the stated auth context literally.
