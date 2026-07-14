---
name: conversion-cro-audit
description: CRO audit of landing, signup, and onboarding flows — finds conversion killers in performance, trust signals, form UX, and first-run experience; use before spending on traffic or after funnel-touching changes.
---

# conversion-cro-audit

Structural audit of the acquisition funnel. It reports what in the code and UX
suppresses conversion; it does not estimate rates without data.

## Inputs to establish first

- Repo root.
- Hot entry URLs to audit (default: `/` and `/signup`; add `/pricing` if present).
- First post-signup route (onboarding entry).
- DB schema path, if query analysis on hot pages is wanted.
- Baseline metrics, if any exist: landing→signup rate, signup→activation rate.
  Missing baselines still allow structural findings — see "When to stop and ask".

## Procedure

1. **Page inventory.** Enumerate routes in the landing → signup → onboarding
   funnel from the router config. Mark each `hot` (traffic-facing) or `internal`.
   Auth-gated pages you cannot reach: list explicitly as not audited, with reason.

2. **Performance scan.** Grep server components / API handlers for uncached
   aggregates on hot pages:

   ```bash
   grep -rn 'COUNT\|SUM\|AVG' --include="*.ts" --include="*.tsx" \
     app src 2>/dev/null | grep -v 'cache\|stale\|revalidate'
   ```

   Flag uncached aggregates and N+1 patterns; estimate payload-size impact.

3. **Trust-signal audit.** Locate trust / social-proof components. Check:
   - DB queries at render time vs build-time / ISR / cached.
   - CLS risk from async trust content (no reserved dimensions).
   - TTFB / LCP impact on the landing page.

4. **Form and signup friction.** Count required fields on each form. Flag:
   missing inline validation, no SSO/OAuth option, multi-step flow without a
   progress indicator, CAPTCHA on first touch, redirect chain longer than one
   hop from CTA to form.

5. **Onboarding first-run.** Trace the post-signup flow. Flag: empty states
   without guidance, feature walls before value delivery, mandatory steps that
   do not contribute to activation, missing skip/defer path, no drop-off tracking.

6. **Live verification (when the app can run).** Launch it via skill
   safe-dev-server and walk the funnel with skill qa-browser (Playwright CLI
   scripts, outputs under `.qa/`, read back only the JSON summaries) to confirm
   code-level findings show up as real friction.

## Scoring

Each finding gets:

- severity P0–P3 (P0 = measurably blocks or cripples a hot funnel page),
- category: perf | trust | form | onboarding | layout,
- effort: low | med | high,
- expected lift: high | med | low.

Order by severity, then effort — cheap high-severity fixes first.

## Output

One BACKLOG.md line per finding, with the scoped fix inside the one-liner:

```
- [ ] P0 | / | TrustStrip runs 4 uncached COUNT queries at render — replace with materialized stats row (ISR or cron) | ev:src/components/TrustStrip.tsx:14-28 | src:conversion-cro-audit
- [ ] P1 | /signup | 7 required fields, no SSO — cut to email+password, add Google/GitHub OAuth | ev:app/signup/page.tsx | src:conversion-cro-audit
```

Close with a short chat summary: pages audited, findings per severity, top
blocker, funnel map (step → page → blocking finding), and what was not covered.
If the findings imply multi-surface rework, open it via skill stage rather than
fixing inline. A recurring codebase-specific conversion killer is worth
recording via skill remember.

## When to stop and ask

- A funnel page is unreachable or the router unparseable — report that first;
  the audit is not trustworthy until it is fixed.
- No baseline metrics and no analytics source — deliver structural findings,
  but ask the owner to instrument before ranking fixes by expected lift.
- An active A/B test changes the flow — ask which variant to audit.

## Anti-patterns

- Guessing conversion rates without data — report structural findings and ask
  for measurement instead.
- "Rewrite the page" recommendations — fixes must be scoped, concrete, and
  independently shippable.
- Silently skipping auth-gated pages — list them as not audited, with reason.
- Mixing SEO issues into CRO findings — SEO belongs in a separate audit pass.
