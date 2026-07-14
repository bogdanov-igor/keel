---
name: qa-browser
description: Browser verification pass for UI work — programmatic defect checks (invisible overlays, overflow, dead theme), real user flows, screenshot-vs-reference with differences listed. Run before declaring any UI change done; "looks fine" is not a result.
---

# QA browser pass

Why this exists: this stack's history holds three "done, in prod"
declarations refuted by the owner's hands within minutes — customizer
broken behind green tsc/biome/e2e, an invisible overlay eating every
mobile click, a dark theme dead on static pages. Reading code and
glancing at one screenshot systematically miss these. This procedure
catches them.

Prereqs: the `playwright` npm package resolvable from the project
(`node -e "require.resolve('playwright')"`; if absent:
`npm i -D playwright`), browsers installed once per machine
(`npx playwright install chromium` — the hook allows `install`).
App running via skill `safe-dev-server`. Write script output under
`.qa/` (gitignored by the installer), read back only the JSON summary.

## 1. Programmatic sweep — cheap and exact, always first

One script, three viewports (360×740, 768×1024, 1440×900), every page
the change touches plus its neighbors:

```js
// .qa/sweep.mjs — run: node .qa/sweep.mjs <url> [more urls...]
import { chromium } from 'playwright';
const browser = await chromium.launch();
const out = [];
for (const url of process.argv.slice(2)) {
  for (const vp of [{width:360,height:740},{width:768,height:1024},{width:1440,height:900}]) {
    const page = await browser.newPage({ viewport: vp });
    let resp = null;
    try {
      resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
      // settle without dying on long-polling/SSE pages
      await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    } catch (e) {
      out.push({ url, viewport: vp.width, findings: [{ kind: 'load-error', error: String(e).slice(0, 200) }] });
      await page.close();
      continue;
    }
    const findings = await page.evaluate(() => {
      const sel = el => el.tagName.toLowerCase() +
        ((el.getAttribute('class') || '').trim() ? '.' + el.getAttribute('class').trim().split(/\s+/)[0] : '');
      const bad = [];
      const de = document.documentElement;
      if (de.scrollWidth > de.clientWidth + 1)
        bad.push({ kind: 'page-overflow-x', scrollWidth: de.scrollWidth, clientWidth: de.clientWidth });
      for (const el of document.querySelectorAll('*')) {
        const cs = getComputedStyle(el), r = el.getBoundingClientRect();
        if (el.scrollWidth > el.clientWidth + 8 && cs.overflowX === 'visible' && r.width > 0)
          bad.push({ kind: 'element-overflow', sel: sel(el) });
        // invisible click-eater: covers most of the viewport, cannot be
        // seen, still receives pointer events. visibility:hidden elements
        // are NOT hit-test targets, so only near-zero opacity qualifies.
        if ((cs.position === 'fixed' || cs.position === 'absolute')
            && r.width >= innerWidth * .9 && r.height >= innerHeight * .9
            && parseFloat(cs.opacity) < .05
            && cs.visibility !== 'hidden'
            && cs.pointerEvents !== 'none')
          bad.push({ kind: 'invisible-overlay-eats-clicks', sel: sel(el), zIndex: cs.zIndex });
      }
      // who actually receives a click at key points (diagnostic context)
      for (const [x, y] of [[innerWidth/2, innerHeight/2], [innerWidth-40, innerHeight-40]])
        bad.push({ kind: 'hit-test', at: [x|0, y|0], receiver: sel(document.elementFromPoint(x, y) || de) });
      return bad;
    });
    // never sweep an error page or a login redirect in the target's name
    const status = resp ? resp.status() : 0;
    if (status >= 400) findings.unshift({ kind: 'http-error', status });
    if (new URL(page.url()).pathname !== new URL(url).pathname)
      findings.unshift({ kind: 'redirected', finalUrl: page.url() });
    out.push({ url, finalUrl: page.url(), status, viewport: vp.width, findings });
    await page.close();
  }
}
console.log(JSON.stringify(out, null, 1));
await browser.close();
```

`invisible-overlay-eats-clicks` is the exact historical mobile bug
(an `opacity:0` panel with `pointer-events:auto` stretched over the
FAB) — no screenshot can show it; this check can. `hit-test` entries
are diagnostic context, not defects. `redirected` / `http-error` /
`load-error` mean the target page was never actually checked — treat
the page as unverified, not clean.

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

Compare against the mock, baseline, or the neighboring page, and write
the differences as a list ("icon 3× too large", "price row wraps",
"CTA below the fold"). Zoom into suspect regions (`clip:`) before
judging detail. A full-page screenshot plus "looks correct" is an
anti-result; element crops alone have declared readiness falsely before.

## Output

Findings → `BACKLOG.md` as
`- [ ] P0..P3 | <surface> | <defect> | ev:<.qa/ path> | src:qa`.
Zero findings → state which checks ran on which pages and viewports,
so "clean" is a scoped claim, not a shrug.
