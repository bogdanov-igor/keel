---
name: support-playbook
description: Generate a structured support playbook from product docs and known issues — issue categories, a triage decision tree, escalation paths, and macro templates.
---

# support-playbook

Builds a `playbook.md` for a product's support workflow, grounded in what the
docs and known issues actually say. Use when a project needs canned support
structure: triage, escalation, reply macros.

## Establish inputs first

- Repo root and docs location (default glob: `docs/**/*.{md,mdx}`).
- Product name (used in macro templates).
- Support tiers offered (default: email, chat).
- Escalation contacts as role descriptions (eng on-call, finance, legal), not personal names.
- Known open issues: read the matching section of memory/MEMORY.md and grep
  memory/ by topic; also scan BACKLOG.md for open user-facing P0/P1 items.

## Procedure

1. Extract issue categories from docs. Identify FAQ patterns, error messages,
   and troubleshooting sections:
   ```bash
   grep -rn '##\s*\(Troubleshoot\|Error\|FAQ\|Common\|Issue\|Problem\)' \
     docs/ 2>/dev/null | head -40
   ```
   Build a list of `{ category, doc file, heading }`.

2. Fold in known issues, each with status `open | mitigated | resolved`.
   Treat an issue as resolved only when the source explicitly says so.

3. Build a triage decision tree — three levels, four at most:
   - L1: billing/account issue vs technical issue.
   - L2 (technical): login/auth vs feature bug vs performance vs data.
   - L3: resolvable with a docs link | needs a workaround | requires escalation.

4. Write 5 macro templates covering the highest-frequency categories:
   - Account/billing inquiry.
   - Feature not working (with workaround).
   - Feature not working (escalation needed).
   - Data/privacy request.
   - Positive feedback / feature-request acknowledgment.
   Each macro: subject line + body with `{{CUSTOMER_NAME}}` and
   `{{PRODUCT_NAME}}` placeholders.

5. Escalation paths: for each support tier, define escalation criteria, the
   role contact, and an SLA target.

6. Compile `playbook.md` with sections: Overview → Issue Categories → Triage
   Tree → Macros → Escalation Paths → Known Open Issues. Default location
   `docs/support/playbook.md` unless the owner names another; when this runs
   inside a stage, link the path from the stage report.

## Quality bar

- A useful playbook has ≥3 issue categories, a triage tree, ≥3 macros, and
  defined escalation paths.
- Fewer than 3 categories found → docs are too sparse; stop and say so rather
  than padding, and add:
  `- [ ] P2 | docs | support docs too sparse for a playbook (<3 issue categories) | ev:docs/ | src:support-playbook`
  to BACKLOG.md.
- No docs and no known issues at all → nothing to ground on; ask the owner for
  source material instead of inventing content.

## Follow-ups

- Suggested next steps (review macro tone against brand voice, load macros
  into the support tool as canned responses) go to BACKLOG.md in the same
  line format.
- If building the playbook revealed something non-obvious about the product's
  failure modes, record via skill remember.

## Anti-patterns

- Personal names in escalation contacts — role descriptions only.
- Macros that promise capabilities not verifiable from the docs.
- Triage trees deeper than 4 levels — complexity defeats usability.
- Marking a known open issue resolved without an explicit source saying so.
