---
name: growth-funnel-audit
description: AARRR funnel audit — trace onboarding/activation/retention paths in code and analytics events; flag broken flows, missing instrumentation, and drop-off gaps.
---

# growth-funnel-audit

Audit the product's AARRR funnel (acquisition, activation, retention, revenue,
referral) by reading code and analytics instrumentation. Default stage set:
`signup → onboarding_complete → first_value_action → day7_return →
paid_conversion` — adjust to the product's real funnel, and each stage should
map to at least one analytics event.

Before starting, read the matching section of memory/MEMORY.md and grep
memory/ for funnel, onboarding, or analytics notes — prior findings and known
broken flows live there and in BACKLOG.md; deduplicate against them.

Default evidence source is code grep. Only query an analytics provider's API
if credentials are provided — reference them as `{{secret:KEY}}` with values
in `.secrets.env`.

## Steps

1. **Event inventory.** Grep the repo for analytics capture calls:
   ```bash
   grep -rn 'posthog\.capture\|usePostHog\|\$pageview\|analytics\.track' \
     --include="*.ts" --include="*.tsx" src app 2>/dev/null
   ```
   Adapt the pattern to the provider in use. Build a catalog:
   `{ event_name, file, line }`.

2. **Route inventory.** Extract user-facing routes. Flag onboarding routes
   lacking an auth gate or exposing resource IDs without an access check.

3. **Map events to AARRR stages.** For each funnel stage, match events from
   step 1 and classify:
   - `covered` — at least one event on the happy path.
   - `gap` — no matching event (stage invisible to analytics).
   - `orphan` — event exists but maps to no stage.

4. **Trace the onboarding happy path.** Walk the code from signup entry
   through each onboarding step. For each step record: route, auth-guarded
   (y/n), event fired (or missing), error boundary (y/n). Flag private URL
   sharing, 404 on empty state, missing error boundaries.

5. **Activation check.** Identify the first-value action. Verify an event
   fires on completion, time-to-activate is measurable, and the abandonment
   path is distinguishable in events.

6. **Retention signal check.** Grep for day-N return or session-start events
   carrying a user_id. Flag if none exist (retention unmeasurable) or if no
   cohort property is attached.

7. **Severity classification.**
   - P0 — broken flow or data leak.
   - P1 — invisible stage (funnel gap in analytics).
   - P2 — missing property on an otherwise-present event.
   - P3 — orphan or noise event.

## Output

Write each finding as one BACKLOG.md line:

```
- [ ] P0..P3 | <surface> | <one line> | ev:<path> | src:growth-funnel-audit
```

Examples:

```
- [ ] P0 | onboarding | step 2 shares private project URL without auth gate | ev:app/onboarding/step2/page.tsx:31 | src:growth-funnel-audit
- [ ] P1 | retention | no day-N return event — retention unmeasurable | ev:grep posthog.capture, zero session_start/day_* matches | src:growth-funnel-audit
```

Close with a short summary in chat: total events found, stage coverage map
(stage → covered/gap/orphan events), finding counts by severity, and what was
not covered. A healthy funnel means all stages covered, zero P0 findings, and
no broken onboarding steps; any P0 or two-plus gap stages means the funnel
needs work before growth experiments make sense.

If a third-party OAuth redirect blocks static tracing, or the analytics
provider is unfamiliar, say so explicitly rather than guessing. Fixing the
findings is separate work: small fixes go through BACKLOG.md; multi-surface
instrumentation work goes via skill stage. If the audit taught something
non-obvious about the product's funnel, record it via skill remember.

## Anti-patterns

- Do not call an analytics API without explicit credentials — default is
  code-grep only.
- Do not invent funnel stages the product doesn't have.
- Do not mark a stage covered if its event only exists in dead code.
- Do not conflate marketing pageviews with meaningful funnel events.
