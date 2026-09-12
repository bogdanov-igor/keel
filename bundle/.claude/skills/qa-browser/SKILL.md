---
name: qa-browser
description: Browser verification pass for UI work — programmatic defect checks (invisible overlays, overflow, dead theme), real user flows, screenshot-vs-reference with differences listed. Run before declaring any UI change done; "looks fine" is not a result.
allowed-tools: Bash(node .claude/skills/qa-browser/sweep.mjs *)
---

# QA browser pass

Why this exists: this stack's history holds three "done, in prod"
declarations refuted by the owner's hands within minutes — a settings
editor broken behind green tsc/biome/e2e, an invisible overlay eating every
mobile click, a dark theme dead on static pages. Reading code and
glancing at one screenshot systematically miss these. This procedure
catches them.

Prereqs: the `playwright` npm package resolvable from the directory you
run the sweep in — `cd` into the app directory when `node_modules`
lives there (`node -e "require.resolve('playwright')"`; if absent:
`npm i -D playwright`), browsers installed once per machine
(`npx playwright install chromium` — the hook allows `install`).
App running via skill `safe-dev-server`. Write script output under
`.qa/` (gitignored by the installer), read back only the JSON summary.

## 1. Programmatic sweep — cheap and exact, always first

Three viewports (360×740, 768×1024, 1440×900), every page the change
touches plus its neighbors:

```sh
node .claude/skills/qa-browser/sweep.mjs <url> [more urls...] > .qa/sweep.json
```

Read the JSON, never the pages it loaded. Kinds it emits:
`page-overflow-x`, `element-overflow` (only overflow no ancestor
scrolls, one line per selector), `invisible-overlay-eats-clicks`,
`click-stolen`, `low-contrast`, and the diagnostics `hit-test` /
`redirected` / `http-error` / `load-error`.

`invisible-overlay-eats-clicks` is the exact historical mobile bug
(an `opacity:0` panel with `pointer-events:auto` stretched over the
FAB) — no screenshot can show it; this check can.

`click-stolen` is the same theft one control at a time: at the centre
of the visible part of a link/button/input, someone else receives the
click — an overlay over a single button, which no screenshot and no
size threshold can catch. Measured on eight public sites: after the
sweep learned to probe the first line box of a wrapped link, skip
screen-reader-only controls and clip a control to its visible part, it
reported nothing there; a real theft still trips it. Still a candidate,
confirmed by eye: a `<label>` covering its own input and a sticky
header over a link scrolled beneath it are legitimate and show up too.

`low-contrast` is text whose colour against the nearest opaque
ancestor background falls under 4.5:1 (3:1 for large text), twelve per
page, one per selector. A candidate, not a verdict: muted meta text is
a common real finding; a ratio near 1.0 usually means the true
background is a sibling layer (a video, a canvas, a gradient element)
the check cannot see. Text over an image is skipped.

`hit-test` entries are diagnostic context, not defects. `redirected` /
`http-error` / `load-error` mean the target page was never actually
checked — treat the page as unverified, not clean.

### No server available

When the circuit breaker refuses a server (host memory pressure), QA
still runs — do not raise its caps to get one. Playwright can serve
the build itself: `page.route('**/*', …)` intercepts every request,
maps the URL path onto a file in the built output directory (`dist/`,
`out/`, `build/`) and fulfils it from disk. No process, no port,
nothing to orphan, and every check in this skill works against it.

## 2. Flow pass — catches what no static check can

Click through each critical flow as a user: open → interact → assert
the visible result. A control that cannot be clicked, a swallowed
click, text unreadable at the viewport — each is a defect, not a
flake. Script the flows; on failure save screenshot + console output +
`elementFromPoint` at the click target.

## 3. Theme / visual-state pass

Applicability first: `colorScheme` emulation exercises
`prefers-color-scheme` theming. If the product themes via a toggle or
stored preference, drive that toggle in a flow instead — emulation
would report a false "theme dead".

Primary check is computed, immune to animations and timestamps — same
page in two contexts (`browser.newPage({ colorScheme: 'dark' })` vs
`'light'`):

```js
const probe = p => p.evaluate(() => {
  const cs = getComputedStyle(document.body);
  return cs.backgroundColor + '|' + cs.color;
});
```

Identical probe values across light/dark on a themed page mean the
theme never applied there (historical case: an env gate not baked into
force-static pages — 17 P1s exactly this way). Screenshots of both
states are evidence for the report; byte-comparison of screenshots is
only a coarse extra signal and needs animations quieted
(`page.emulateMedia({ reducedMotion: 'reduce' })`).

## 4. Screenshot vs reference — last, never alone

The reference is a file, not a memory of one:
`qa-baseline/<route>-<viewport>.png`, tracked in git — not under
`.qa/`, which the installer gitignores.

- Render the route in the same viewport, put it next to its baseline,
  and compare pixels. Write the differences as a list ("icon 3× too
  large", "price row wraps", "CTA below the fold"). Zoom into suspect
  regions (`clip:`) before judging detail.
- A text or CSS diff is not evidence. One reported "~5% off" on a pair
  whose structure differed outright.
- No baseline for this route × viewport → the first run creates one.
  That run is a baseline, not a check: it asserts nothing.
- A baseline changes only on a `verifier` pass or the owner's
  decision. Overwrite it quietly and the defect becomes canon.
- If the project synced its design system (`/design-sync`), the
  reference may come from there — skill `design-port`.

A full-page screenshot plus "looks correct" is an anti-result; element
crops alone have declared readiness falsely before.

## Output

Findings → `BACKLOG.md` as
`- [ ] P0..P3 | <surface> | <defect> | ev:<.qa/ path> | src:qa`.
Zero findings → state which checks ran on which pages and viewports,
so "clean" is a scoped claim, not a shrug.
