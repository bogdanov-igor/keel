---
name: customer-reply-draft
description: Draft a factual, on-brand reply to a customer question or complaint, grounded in product docs and support playbook — cites sources, never invents capabilities.
---

# customer-reply-draft

Turn a customer message into a reply where every factual claim traces to a doc
passage. Inputs: the verbatim customer message, plus (when available) the repo's
docs (`docs/**/*.md`), a support playbook, a brand-voice doc, and the customer
tier (free / starter / pro / enterprise — affects tone and escalation threshold).

Before starting, read the matching section of memory/MEMORY.md and grep memory/
for prior lessons on this product's support topics (e.g. recurring complaint
themes, phrasing that landed badly).

## Steps

1. **Classify the message.**
   - Type: billing question, feature how-to, bug report, complaint, feature
     request, or compliment.
   - Urgency: urgent (data loss, outage, billing error) vs. normal.

2. **Retrieve grounding passages.** Search docs/playbook for content matching
   the message topic:
   ```bash
   grep -rni "$(echo "$customer_message" | tr ' ' '\n' | sort -u | head -5 | tr '\n' '\|')" \
     docs/ 2>/dev/null | head -20
   ```
   Collect up to 5 relevant passages with file + line citations.

3. **Check the playbook for a matching macro.** If a support playbook exists,
   grep it for a macro matching the message type. If found, use it as the base
   template and personalize.

4. **Draft the reply.**
   - Open with empathy (1 sentence max).
   - Answer the question directly using only grounding passages — no invented
     features.
   - Cite each factual claim with `[source: docs/path.md#heading]`.
   - If the answer is unknown, acknowledge that and escalate per playbook.
   - Close with a next step or offer — one concrete action, not an open-ended
     "let me know if you need anything".
   - Match the brand-voice doc if one exists.
   - Default to 1 draft; produce a second variant only when asked.

5. **Score confidence** (0.0–1.0):
   - 1.0 — every claim grounded in a retrieved doc passage.
   - 0.7–0.9 — partially grounded, minor inference.
   - < 0.7 — significant gaps; flag for human review before sending.

6. **Escalation check.** If the message type is billing error, data loss, or a
   legal/privacy request, mark the draft as escalated and include the
   escalation route from the playbook.

## Output

Present the draft(s) inline with: message type, urgency, confidence score, and
the citation list. Save the draft under `stages/<current-stage>/` if working
inside a stage, otherwise wherever the caller asked.

When the result needs follow-up (escalation, human review, or a docs gap that
blocked grounding), add a line to BACKLOG.md:

```
- [ ] P1 | support | escalate: billing error from enterprise customer, draft held | ev:stages/012-support/reply-draft.md | src:customer-reply-draft
```

Severity guide: P0 legal/data-loss/outage; P1 billing errors and escalations;
P2 confidence < 0.7 needing human review; P3 docs gap discovered while grounding.

## Result classes

- **passed** — at least 1 draft produced, confidence ≥ 0.7, no invented
  capabilities.
- **failed** — no grounding passages found and the message requires a factual
  answer (not just empathy). Report the docs gap rather than guessing.
- **escalated** — billing error, data loss, legal request, or confidence < 0.5.

## Anti-patterns

- Inventing product features or capabilities not found in docs.
- Including pricing numbers — link to the pricing page instead.
- Multi-paragraph replies to simple how-to questions — brevity is brand.
- Replying to legal/privacy requests without the escalation flag.
- Suppressing the human-review note when confidence < 0.7 — it always ships
  with the draft.

If a reply teaches something reusable (a recurring complaint theme, a macro
worth adding to the playbook), record it via skill remember.
