---
name: pricing-packaging-audit
description: Reconcile every price, limit, and tier mention in code, copy, and config against the PLANS source-of-truth; use when pricing or plan limits may have drifted across surfaces.
---

# pricing-packaging-audit

Pure grep + regex reconciliation — no guessing, no strategy opinions. Every
finding must cite a file:line and the source-of-truth value it contradicts.

## Inputs

- Repo root.
- Path to the PLANS source-of-truth (e.g. `src/config/plans.ts` or `PLANS.md`).
  If the owner did not name one, look for an obvious single plan-definition
  file; if none exists or several candidates conflict, stop and ask the owner
  one targeted question — do not infer the SoT from marketing copy.
- Scan dirs (default `src app docs public emails`) and extensions
  (default `ts tsx js jsx md mdx json yaml yml html`).

## Steps

1. **Parse the SoT** into a canonical map:
   `{ plan_name → { price_monthly, price_annual, limits: {}, features: [] } }`.
   Ambiguous or duplicate entries that cannot be auto-resolved → stop and ask
   the owner instead of picking one.

2. **Extract price mentions.**
   ```bash
   rg -n --no-heading -e '\$\d+' -e 'price.*[:=]\s*\d+' -e 'per.?month' -e '/mo\b' \
     --type-add 'scan:*.{ts,tsx,js,jsx,md,mdx,json,yaml,yml,html}' -t scan \
     src/ app/ docs/ public/ emails/ 2>/dev/null || true
   ```

3. **Extract tier/limit mentions.**
   ```bash
   rg -n --no-heading -i \
     -e '(free|starter|pro|business|enterprise|hobby|team)' \
     -e 'max_\w+\s*[:=]\s*\d+' -e 'limit.*[:=]\s*\d+' -e 'quota.*[:=]\s*\d+' \
     --type-add 'scan:*.{ts,tsx,js,jsx,md,mdx,json,yaml,yml,html}' -t scan \
     src/ app/ docs/ public/ emails/ 2>/dev/null || true
   ```

4. **Cluster occurrences.** Group by `(file, inferred tier)`. Normalize dollar
   amounts to monthly integers. Deduplicate identical lines within a file.
   Skip commented-out code.

5. **Diff each cluster against the SoT:**
   - Price differs from SoT → contradiction, **P0**.
   - Limit differs from SoT → contradiction, **P0**.
   - Plan name used in code/copy but absent from SoT → unknown plan, **P1**.
   - SoT plan never referenced anywhere → missing reference, **P3** (note, not a defect).

6. **Willingness-to-pay inversion check.** Flag as **P1** when:
   - Free-tier limits in code exceed Starter/paid limits in the SoT, or
   - a paid price in marketing copy is lower than the Free-equivalent in
     billing config.

## Output

Append one line per finding to `BACKLOG.md`:

```
- [ ] P0 | pricing | starter shows $19, SoT says $29 | ev:app/(marketing)/pricing/page.tsx:47 | src:pricing-packaging-audit
- [ ] P0 | pricing | free tier lists 5 monitors, SoT says 2 | ev:app/(marketing)/pricing/page.tsx:63 | src:pricing-packaging-audit
- [ ] P1 | pricing | WTP inversion: free quota exceeds starter quota | ev:src/config/plans.ts:12 | src:pricing-packaging-audit
```

Then report to the owner: SoT path, plans found in SoT, total mentions
scanned, contradiction count by severity, and any plans with no references.
State explicitly what was not scanned (dirs or extensions outside the scan
set). Clean pass = zero contradictions and zero WTP inversions.

If the drift is systemic (many surfaces, or fixing it means restructuring
plan config), open the fix as a stage via skill stage rather than patching
inline. If the audit teaches something non-obvious about where pricing hides
in this codebase, record it via skill remember.

## Anti-patterns

- Do not infer the SoT from marketing copy — only trust the explicitly
  identified plans file.
- Do not flag commented-out code as a contradiction.
- Do not normalize annual pricing by 12 and then flag rounding differences
  under $0.50 as P0.
- Do not suggest pricing strategy changes — report drift only; strategy is
  the owner's decision.
