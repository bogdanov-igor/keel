---
name: site-sweep
description: Full-site user-level audit — a Playwright crawler captures screenshots, geometry, and console/network evidence for every route × viewport × theme, then a multi-lens review grades each page launch-ready | needs-polish | pet-project; run before launch or after broad UI changes.
---

# Site sweep

Two layers, both required: (1) deterministic crawler evidence,
(2) a review whose per-page verdict is the gate — never a single
glance at one screenshot. Skill `qa-browser` verifies one change;
site-sweep grades the whole site the way a first-time visitor sees it.

## Setup

- Target: the production origin (`BASE_URL`, e.g. `https://<prod-origin>`).
  Prefer prod — that is what users actually get. If sweeping a local
  build, start it via skill `safe-dev-server` first; never launch a
  server ad hoc for a sweep.
- Matrix: every public route × 2 viewports (desktop 1440×900, mobile
  390×844) × 2 themes (light/dark). Expected page loads = routes × 4.
- Output: screenshots + `sweep.json` under `.qa/sweep/<yyyymmdd>/`;
  read back only the JSON summary, not the images (qa-browser
  convention). The crawler lives at `.qa/site-sweep.mjs` — same
  Playwright-through-Bash pattern as the qa-browser sweep script,
  extended with slices, geometry, and console/network capture.
- The crawl spawns many Chromium processes; run it through the
  safe-run launcher with a TTL so a hung browser tree gets reaped
  (Bash tool, `run_in_background: true`):

  ```sh
  SWEEP_OUT=.qa/sweep/<yyyymmdd> bash .claude/skills/safe-dev-server/safe-run.sh \
    --label sweep --ttl 25 -- node .qa/site-sweep.mjs
  ```

  On host memory pressure, adjust only the breaker's pressure
  threshold in `keel.json:circuit_breaker`, scoped to this run —
  do not raise the process or RSS caps for a heavy sweep.

## Steps

1. Route inventory first. Diff the app's current public routes
   (router/pages directory, sitemap) against the `ROUTES` list in the
   crawler; add anything shipped since the last sweep and confirm any
   middleware/proxy allowlist covers it. A new public route silently
   missing from the list = false-green sweep.
2. Crawl. Per route × viewport × theme, record into `sweep.json`:
   full-page screenshot, viewport-step slice screenshots, geometry
   (header/h1/main/footer rects, nav inner-left offset, horizontal
   overflow, vertical gaps > 160 px), every console error, every
   failed request — own and third-party.
3. Slice completeness. Per combination, expected slice files =
   ceil(pageHeight / step). A shortfall is a crawler defect, not a
   short page — Playwright `clip:` beyond the viewport is a silent
   no-op. Re-shoot missing slices by scrolling + viewport-sized
   shots, without clip.
4. Dark check by hash. Quiet animations first
   (`page.emulateMedia({ reducedMotion: 'reduce' })`), then hash
   light-vs-dark full screenshots per route × viewport: a
   byte-identical pair means dark mode never applied on that page —
   a defect regardless of how the code reads. qa-browser's computed
   body background/color probe is the cheap cross-check; if the
   product themes via a toggle rather than `prefers-color-scheme`,
   drive the toggle instead of emulating the color scheme.
5. Geometry as one cross-page table. Assemble all rects and offsets
   into a single table across pages; defects are the outliers between
   pages (frame drift, nav misalignment, stray gaps), not per-page
   absolutes.
6. Console + third-party section — always present in the result.
   Report every console error and failed request per load, including
   third-party 4xx/5xx. A fix claimed in a code comment but never
   observed on the live site counts as unverified.
7. Multi-lens review. Grade each page × viewport against a
   composition rubric (visual hierarchy, spacing rhythm, alignment,
   copy quality, above-the-fold pitch); with many pages, fan out
   `scout` agents one per page and merge. Then four cross-page
   lenses: hub/nav consistency, marketing frame (would a stranger
   understand the product?), dark theme, mobile. Adversarially
   re-check every P0–P2 candidate against its screenshot evidence
   before accepting it. Per-page verdict enum:
   `launch-ready | needs-polish | pet-project` — the verdict is the
   gate, not your overall impression.
8. Consolidate + record. Merge crawler and review findings, dedupe,
   and write each to `BACKLOG.md`:
   `- [ ] P0..P3 | <route> | <one line> | ev:.qa/sweep/<date>/... | src:site-sweep`.
   P0/P1 remediation spanning multiple surfaces → skill `stage`.
   A newly discovered trap → skill `remember`.

## Sweep result

The sweep itself passes only when all of these hold — otherwise it
failed, and the report says which one broke:

- every route × viewport × theme combination completed;
- slice counts reconcile, or shortfalls were re-shot;
- the dark hash check ran on every pair;
- the review produced a verdict for every page;
- the consolidated defect list and the console/third-party section exist.

Any `pet-project` verdict or any P0 → escalate: the sweep still
counts as run, but flag it to the owner and route remediation ahead
of other work.

## Gotchas

- "Screenshot files exist" is not coverage — swallowed clip errors
  leave silent gaps; always reconcile counts against expectations.
- Eyeballing dark mode misses it: identical bytes = broken, however
  plausible the page looks in one theme.
- Judging geometry page-by-page hides frame drift; only the
  cross-page table exposes it.
- Omitting third-party failures makes the site look healthier than
  users experience it.
- Your own impression never overrides the per-page verdict enum.
