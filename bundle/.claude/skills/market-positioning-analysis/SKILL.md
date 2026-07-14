---
name: market-positioning-analysis
description: Build a structured positioning map — ICP fit scores, differentiation matrix, and gap analysis grounded in sourced competitor data — when deciding where a product should compete or which segment to target.
---

# market-positioning-analysis

Builds a positioning map for a product: ICP segments with fit scores, a
differentiation matrix against named competitors, and a gap analysis.
Analysis only — turning the map into action recommendations is separate work.

## Inputs

- Product name and one-line value prop.
- Competitor data: per competitor — tagline, pricing, ICP, top features, moat
  claims, each with a source URL (output of a competitor-analysis pass or
  equivalent research).
- Seed ICP segments (at least one).
- Optional: current tagline/positioning; max segments to score (default 5).

Competitor data empty or unsourced → stop and ask for it first; guessed
competitor features poison every downstream score.

## Steps

1. Ground in prior knowledge. Read the matching section of memory/MEMORY.md
   and grep memory/ for the product name plus "positioning", "ICP",
   "differentiation". Earlier segment or moat conclusions constrain this run;
   contradict them only with fresh evidence.

2. ICP segmentation. From competitor customer pages and the seed list
   (WebSearch `"<competitor> customers"`, G2/Capterra snippets), identify up
   to the max number of distinct segments. For each record:
   - size tier: S / M / L
   - switching cost: low / med / high
   - best-served-by: which competitor currently owns the segment
   - our fit score 0–1 and a one-line gap summary

3. Differentiation matrix. For each feature that matters to a segment, score
   our product and every competitor `strong | partial | absent`. Derive:
   - moats — capabilities we cover that no competitor does; mark `confirmed`
     only when backed by a source URL, otherwise `suspected`
   - feature gaps — where at least one competitor is strong and we are absent

4. Positioning gap analysis. Classify each segment:
   - underserved — no competitor scores strong on more than 50% of the
     features that segment needs
   - over-contested — 3 or more competitors score strong; avoid unless a
     confirmed moat applies
   - natural fit — strongest overlap between our features and segment needs
   Give each gap a severity (high/med/low) and an opportunity score 0–1.

5. Write the map. The full analysis — segments table, matrix, moats, gaps,
   source URLs — goes into the stage report when this runs inside skill
   stage; for a standalone pass, one markdown file whose path serves as the
   evidence link below.

6. File findings. Each actionable gap or positioning contradiction becomes a
   BACKLOG.md line, severity high → P1, med → P2, low → P3 (reserve P0 for
   "current positioning claims a capability the product lacks"):
   `- [ ] P1 | positioning | 3PL operators underserved, opportunity 0.85 | ev:stages/012-positioning/report.md | src:market-positioning-analysis`

7. Remember. A confirmed moat, a disproven segment hypothesis, or a market
   shift is worth a note via skill remember; routine scores are not.

## Quality bar

The map is usable when it has at least 2 scored ICP segments, at least 3
feature rows in the matrix, and at least 1 identified gap. Below that — or if
web search returns no usable data for more than half the competitors — report
what blocked the analysis instead of padding the map with guesses.

## Worked example (shape of the output)

| Segment | Size | Switching | Best served by | Fit | Gap |
|---|---|---|---|---|---|
| D2C brands $1–10M ARR | L | med | ShipStation | 0.7 | missing returns automation |

| Feature | Ours | AfterShip | Shippo |
|---|---|---|---|
| Carrier rate optimization | strong | partial | strong |

Moat: real-time cost anomaly detection (confirmed). Gap: 3PL operators —
underserved, severity high, opportunity 0.85.

## Anti-patterns

- Producing action recommendations — this skill maps the terrain; choosing
  the route is a separate decision.
- Inventing competitor features without a source URL.
- Conflating adjacent-market tools with direct competitors.
- Skipping the memory grounding step — re-deriving segments from scratch each
  run silently discards earlier conclusions.
