---
name: api-contract-audit
description: Verify that API route implementations match their declared contracts (OpenAPI/tRPC/REST conventions) — check request validation, response shapes, error codes, and auth guards; use when auditing an API surface or before shipping route changes.
---

# api-contract-audit

Audit an API surface for contract drift: unguarded routes, unvalidated input,
leaky response shapes, swallowed errors, and (when a spec exists) divergence
between spec and implementation. Pure grep/file-pattern analysis — deterministic
for a given codebase state, no server needed.

Before starting, read the matching section of memory/MEMORY.md and grep memory/
for prior API-audit lessons on this project.

## Inputs (ask or infer)

- api root — directory containing route files (e.g. `src/app/api`)
- spec path (optional) — OpenAPI/tRPC spec; if absent, inspect routes directly
- auth guard pattern — regex for auth functions, default `getSession|getUser|verifyToken`
- validation pattern — regex for input-validation libraries, default `zod|yup|joi|valibot`

## Steps

Work files go under the scratchpad or `.qa/`; cite them as evidence paths.

1. Enumerate routes.
   ```bash
   find "$API_ROOT" -name "route.ts" -o -name "*.handler.ts" \
     -o -name "index.ts" | sort > .qa/routes.txt
   ```

2. Auth guard check.
   ```bash
   while IFS= read -r route; do
     has_auth=$(grep -cE "$AUTH_PATTERN" "$route" || echo 0)
     is_public=$(grep -cE "@public|// public|noAuth" "$route" || echo 0)
     [ "$has_auth" -eq 0 ] && [ "$is_public" -eq 0 ] && echo "NO_AUTH: $route"
   done < .qa/routes.txt > .qa/no_auth.txt
   ```

3. Input validation check.
   ```bash
   while IFS= read -r route; do
     has_validation=$(grep -cE "$VALIDATION_PATTERN" "$route" || echo 0)
     has_body_parse=$(grep -cE "req\.body|request\.json\(\)|await req\.json" "$route" || echo 0)
     [ "$has_body_parse" -gt 0 ] && [ "$has_validation" -eq 0 ] && echo "NO_VALIDATION: $route"
   done < .qa/routes.txt > .qa/no_validation.txt
   ```

4. Response shape check.
   ```bash
   # Routes that return raw DB rows without selecting/mapping fields
   grep -rn "select(\*)\|findMany()\|\.all()" "$API_ROOT" 2>/dev/null > .qa/raw_db.txt
   # Routes lacking explicit error responses
   grep -rn "catch" "$API_ROOT" | \
     grep -v "return.*status\|NextResponse\|Response" > .qa/swallowed_errors.txt
   ```

5. Spec drift (only if a spec path was provided). For each route in the spec,
   verify the corresponding file exists and the method is handled. For each
   route file, verify it appears in the spec.

6. Grade findings:
   - P0 (critical) — missing auth guard on a non-public route
   - P1 (major) — body-parsing route with no input validation
   - P2 (minor) — swallowed errors, raw DB rows returned, spec drift

## Output

Append one line per finding to BACKLOG.md:

```
- [ ] P0 | api | POST /api/monitors has no auth check; any unauthenticated caller can create monitors | ev:.qa/no_auth.txt | src:api-contract-audit
```

Include a short recommendation in the line when it fits, e.g.
"add `const session = await getSession(req); if (!session) return 401;` before handler logic".

Result summary in chat: routes scanned, counts per severity, and one line on
what was not covered. Zero P0s means the surface passes; any P0 means it fails
and the fix belongs at the top of the backlog. If the API uses a non-standard
framework these file patterns can't parse, say so and ask for a spec path
rather than reporting a clean pass. Fixing more than a couple of findings is
multi-unit work — route it via skill stage.

If the audit taught something non-obvious about this project's API layer
(unusual auth flow, framework quirk), record it via skill remember.

## Anti-patterns

- Do not flag routes annotated with `@public` or `// public` as missing auth.
- Do not assume GET routes need no auth; read-only data may still be tenant-scoped.
- Do not report spec drift if no spec path was provided; note the spec is absent instead.
- Do not conflate request logging middleware with input validation.
