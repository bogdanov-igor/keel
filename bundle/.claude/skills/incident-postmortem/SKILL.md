---
name: incident-postmortem
description: Produce a blameless postmortem from an incident timeline — root cause, contributing factors, graded action items into BACKLOG.md, and a lesson recorded for future prevention.
---

# Incident postmortem

Run after an incident is resolved, or as the closing step of a hotfix.
Blameless: the document explains why the system allowed the failure,
never who caused it. An incident writeup is big work — handle it via
skill `stage`; the postmortem is the stage's `report.md`.

## Inputs

Collect before writing; ask once for anything missing:

- Incident metadata: title, severity (P0-P3), started_at, resolved_at,
  affected services, measurable user impact.
- Timeline: at least 3 timestamped events covering detection, response,
  and resolution. Fewer than 3 means the picture is incomplete —
  gather more before synthesizing a root cause.
- Optional, pre-filled by the responder: contributing factors and
  mitigations taken. Augment them, don't overwrite.

If the root cause cannot be established from the timeline alone
(needs logs or traces not at hand), stop and request them once; a
postmortem with a guessed root cause is worse than a delayed one.

## Procedure

1. Sanity-check: started_at precedes resolved_at; compute MTTR in
   minutes and state it in the summary.
2. Classify severity impact:
   - P0 — total outage or data-loss risk.
   - P1 — major feature degraded, >10% of users affected.
   - P2 — partial degradation, workaround available.
   - P3 — minor issue, <1% of users, cosmetic.
3. Synthesize three distinct things from timeline + factors:
   - Trigger — the proximate cause: what changed or failed.
   - Root cause — the systemic condition that let the trigger cause
     impact.
   - Detection gap — why alerting or detection was late, if it was.
4. Generate action items. Each carries a type
   (`prevent | detect | respond | recover`), an owner role (never a
   person's name), a due horizon (`sprint | month | quarter`), and a
   priority P0-P3. Minimum one prevent and one detect item.
5. Write the postmortem with sections in order: Summary · Timeline ·
   Root Cause · Contributing Factors · Impact · Action Items ·
   Lessons Learned.
6. Land every action item in `BACKLOG.md`:
   `- [ ] P1 | <service> | <type>: <one line>, due <horizon>, owner <role> | ev:stages/NNN-slug/report.md | src:incident-postmortem`
7. Record the lesson via skill `remember` — one note named
   `incident-<YYYY-MM>-<service>` capturing root cause and fix, so the
   next session checks for the trap instead of rediscovering it.

## Worked example

P1, MTTR 136 min. Trigger: deploy restarted the DB. Root cause:
connection pool exhausted afterwards — no reconnect retry configured.

```text
- [ ] P1 | api | prevent: pool health check in deploy gate, due sprint, owner platform | ev:stages/012-db-pool/report.md | src:incident-postmortem
- [ ] P1 | api | detect: alert on pool_wait_ms > 200ms, due sprint, owner on-call | ev:stages/012-db-pool/report.md | src:incident-postmortem
- [ ] P2 | api | recover: manual pool-drain runbook, due month, owner platform | ev:stages/012-db-pool/report.md | src:incident-postmortem
```

Lesson recorded: `incident-2024-01-api`.

## Done when

Root cause identified and distinct from the trigger; at least one
prevent and one detect item in `BACKLOG.md`; postmortem written under
`stages/`; lesson recorded.

## Anti-patterns

- Naming individuals in blame context — use roles ("on-call
  engineer", "deployer").
- Action items without an owner role and due horizon — unassigned
  items are never done.
- Conflating trigger with root cause — trigger is what broke; root
  cause is why it could break.
- Skipping the detect item — a postmortem that only prevents the last
  failure misses the next one.
