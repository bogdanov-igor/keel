---
name: messaging-copy-audit
description: Cross-surface messaging consistency and legal-cleanliness audit — landing/features/compare/pricing/docs checked for claim drift, testimonial authenticity, and unsubstantiated statements.
---

# Messaging copy audit

Checks that user-facing copy tells one consistent, defensible story
across surfaces. Run it when marketing pages, pricing, or docs changed,
or before a launch. It follows the general `audit` skill's rules
(evidence per finding, WIP limit, honest coverage report); this file
adds the copy-specific procedure.

## Scope inputs

Settle these before scanning:

- Surfaces: at least two, each a label + glob, e.g. `landing:
  app/(marketing)/page.tsx`, `pricing: app/(marketing)/pricing/**/*.tsx`,
  `docs: docs/**/*.{md,mdx}`. One surface alone cannot drift.
- Brand voice reference (e.g. `docs/brand-voice.md`) — optional; if the
  file is absent, skip voice comparison silently, do not error.
- Known customers list — the set of names testimonials may legitimately
  cite. If testimonials exist but no such list was given, ask the owner
  once for it; no answer this session → park the audit in `PARKED.md`
  (authenticity is undecidable without it). Empty list → every
  testimonial is flagged `testimonial_unverified`.

Ground first: read the matching section of `memory/MEMORY.md` and grep
`memory/` for prior copy/claims lessons on this product.

## Procedure

1. Collect surfaces. Glob-match files per surface. Extract user-visible
   strings only: JSX text nodes, markdown paragraphs, alt-text, meta
   descriptions. Keep `{surface, file, line, text}` for each.
2. Build a claim registry from the extracted strings:
   - value propositions (benefit language)
   - quantitative claims (numbers + their context)
   - feature names (capitalized compound terms)
   - superlatives ("best", "only", "#1")
   - testimonials (quoted text + attribution)
   - competitor mentions
3. Cross-surface consistency check:
   - same feature under different names across surfaces → `naming_inconsistency`
   - quantitative claim differs between surfaces → `metric_contradiction`
   - value prop on landing absent from features/docs → `orphan_claim`
   - comparison-table claim not backed by docs → `unsubstantiated_comparison`
4. Legal-cleanliness check, per surface:
   - testimonials cross-referenced against known customers; unmatched or
     generic attribution → `testimonial_unverified` (P0 if clearly
     fabricated, e.g. initial-only surname with no matching customer)
   - quantitative claim without source/footnote → `claim_unsourced`
   - superlative without qualifier → `superlative_unqualified`
   - competitor claim without citation → `competitor_claim_unsourced`
   - comparison/pricing pages missing "results may vary" / "prices
     subject to change" → `disclaimer_missing`
5. Grade severity:
   - P0 — fabricated testimonial, false quantitative claim, trademark misuse
   - P1 — metric contradiction, unqualified superlative on landing
   - P2 — naming inconsistency, orphan claim, missing disclaimer
   - P3 — minor voice drift

## Output

Findings land as `BACKLOG.md` lines, one per finding:

```
- [ ] P1 | landing+pricing | metric_contradiction: landing "10× faster" vs pricing "5× speed improvement" — align to one defensible number with methodology footnote | ev:app/(marketing)/page.tsx:88 | src:messaging-copy-audit
- [ ] P0 | landing | testimonial_unverified: "Cut deploy time by 80%" — Alex K., NovaTech not in known customers | ev:app/(marketing)/page.tsx:142 | src:messaging-copy-audit
```

Each line names the check type, quotes the offending text, and carries
a `path:line` evidence pointer. Recommendation goes in the same line
when it fits ("align to one number", "verify or remove").

Close the run with an honest summary: surfaces and files scanned,
registry counts (value props / quantitative claims / testimonials),
finding totals per severity, and what the scope did not cover. Verdict:
pass = zero P0 and zero P1. Fixing copy across many surfaces is
multi-unit work — route it through skill `stage`. A non-obvious lesson
(e.g. a claim pattern this product keeps regressing on) → skill
`remember`.

## Anti-patterns

- Intentional tone differences between marketing and docs are not
  P0/P1 — P3 at most.
- Placeholder / lorem-ipsum text is not a finding.
- Never generate replacement testimonials — flag and recommend only.
- Do not infer competitor names from context; flag explicit mentions only.
