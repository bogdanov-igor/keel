---
name: competitor-analysis
description: Fetch and structure profile data for a set of competitors — tagline, pricing, ICP, top features, moat claims — into an evidence-backed competitor registry; use when benchmarking a product against its market.
---

# Competitor analysis

Profiles competitors from their live public pages into a registry with
source URLs. This skill profiles, it does not advise — positioning
recommendations are separate work. Output varies with live page content.

## Inputs

- Product being benchmarked.
- Seed competitors (at least one known name).
- Optional: category keywords (e.g. "shipping analytics", "uptime
  monitoring") to discover more, and a cap on total competitors
  (default 8).

## Procedure

1. Ground first: read the matching section of `memory/MEMORY.md` and
   grep `memory/` for prior notes on this market — don't re-profile
   what a recent registry already covers.
2. Discover. For each category keyword, WebSearch
   `"best <keyword> tools 2026"` and `"<product> alternatives"`;
   collect names until the cap is reached.
3. Profile each competitor:
   - WebFetch the homepage → tagline, primary value prop.
   - WebFetch `/pricing` → pricing model (flat / usage / seat / free-tier).
   - WebFetch `/customers` or `/about` → primary ICP claim.
   - Up to 5 top features from homepage/feature pages.
   - Moat claims (e.g. "largest network", "SOC2 Type II").
   - Record a source URL and fetch date for every data point.
4. Mark freshness. A page with no date indicator whose content looks
   more than 12 months old gets `freshness: unknown` on that entry.
5. Compile the registry. One entry per competitor; a competitor with
   fewer than 3 data points is listed as insufficient-data, not
   padded with guesses.

## Output

Write the registry as a markdown table — into the stage's `report.md`
when this runs inside a stage (multi-product or recurring benchmarks
are stage work), otherwise into a file agreed with the caller:

| name | tagline | pricing | primary ICP | top features | moat claims | freshness | sources |
|---|---|---|---|---|---|---|---|
| AfterShip | Post-purchase experience platform | usage-tiered | D2C e-commerce $5M+ ARR | tracking, returns, notifications | largest carrier network | current | aftership.com, aftership.com/pricing |

Follow-ups the registry surfaces (e.g. "competitor undercuts our entry
tier") go to `BACKLOG.md`:
`- [ ] P0..P3 | <surface> | <one line> | ev:<registry path> | src:competitor-analysis`

A non-obvious market lesson (a durable insight, not the data itself) →
skill `remember`.

## Done / not done

- Complete: at least 3 competitors fully profiled — tagline + pricing
  + ICP + 3 or more features, each with a source URL.
- Incomplete: fewer than 3 complete profiles; say so in the summary
  rather than diluting the completeness bar.
- Blocked: fetches fail for more than half the competitors → ask the
  owner once for alternative sources; no answer → `PARKED.md` with a
  one-line resume plan.

## Anti-patterns

- Inventing features not found on fetched pages — every feature claim
  needs a source URL.
- Conflating adjacent-market tools with direct competitors unless they
  have category-specific features.
- Omitting the fetch date — stale profiles mislead any later
  positioning work.
- Producing recommendations here; this skill profiles, not advises.
