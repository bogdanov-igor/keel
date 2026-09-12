// Programmatic defect sweep — the cheap, exact first pass of skill qa-browser.
//
//   node .claude/skills/qa-browser/sweep.mjs <url> [more urls...] > .qa/sweep.json
//
// Every url is loaded in three viewports; findings print as one JSON array.
// Needs the `playwright` package resolvable from the directory the sweep runs
// in (cd into the app directory when node_modules lives there) and chromium
// installed once per machine (`npx playwright install chromium`). A bare ESM
// import would resolve from this file's own location instead — the kernel dir,
// which never holds node_modules — so the package is required from cwd.
import { createRequire } from 'node:module';
const requireFromCwd = createRequire(process.cwd() + '/');
let chromium;
try { ({ chromium } = requireFromCwd('playwright')); }
catch { ({ chromium } = await import('playwright')); }

const VIEWPORTS = [{ width: 360, height: 740 }, { width: 768, height: 1024 }, { width: 1440, height: 900 }];
const browser = await chromium.launch();
const out = [];

for (const url of process.argv.slice(2)) {
  for (const vp of VIEWPORTS) {
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
      // id included: "div" as the thief of a click names nothing findable.
      const sel = el => el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
        ((el.getAttribute('class') || '').trim() ? '.' + el.getAttribute('class').trim().split(/\s+/)[0] : '');
      const bad = [];
      const de = document.documentElement;
      if (de.scrollWidth > de.clientWidth + 1)
        bad.push({ kind: 'page-overflow-x', scrollWidth: de.scrollWidth, clientWidth: de.clientWidth });
      // Overflow inside a scroller (carousel, code block, table wrapper) is by
      // design; only overflow that no ancestor scrolls is a candidate. One line
      // per selector, fifteen per page: a component repeated 60 times is one
      // defect, and the JSON is read by the model.
      const inScroller = el => { for (let p = el.parentElement; p; p = p.parentElement) { const o = getComputedStyle(p).overflowX; if (o === 'auto' || o === 'scroll') return true; } return false; };
      const overflowSeen = new Set();
      for (const el of document.querySelectorAll('*')) {
        const cs = getComputedStyle(el), r = el.getBoundingClientRect();
        if (el.scrollWidth > el.clientWidth + 8 && cs.overflowX === 'visible' && r.width > 0
            && overflowSeen.size < 15 && !overflowSeen.has(sel(el)) && !inScroller(el)) {
          overflowSeen.add(sel(el));
          bad.push({ kind: 'element-overflow', sel: sel(el) });
        }
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
      for (const [x, y] of [[innerWidth / 2, innerHeight / 2], [innerWidth - 40, innerHeight - 40]])
        bad.push({ kind: 'hit-test', at: [x | 0, y | 0], receiver: sel(document.elementFromPoint(x, y) || de) });
      // Per-control hit test: the same theft one button at a time. An overlay
      // covering ONE control never trips the full-viewport check above, and no
      // screenshot shows it. Capped — the point is the interactive surface,
      // not every node on a long page. Measured on eight public sites: the
      // false-positive classes were a link wrapped over two lines (the centre
      // of its bounding box falls between the lines), a screen-reader-only
      // skip link clipped to one pixel, and a link cut off by a cell with
      // overflow hidden — hence the first line box, the clip checks and the
      // visible-part clipping below.
      let probed = 0;
      for (const el of document.querySelectorAll('a, button, input, select, textarea, [role=button], [onclick]')) {
        if (probed >= 200) break;
        const cs = getComputedStyle(el), r = el.getBoundingClientRect();
        if (r.width < 1 || r.height < 1) continue;
        if (cs.visibility === 'hidden' || cs.display === 'none' || parseFloat(cs.opacity) < .05) continue;
        if (cs.clipPath !== 'none' || (cs.clip && cs.clip !== 'auto') || (r.width <= 1 && r.height <= 1)) continue;
        const rects = el.getClientRects(), b = rects.length ? rects[0] : r;
        // the visible part only: an ancestor with overflow hidden clips the
        // box, and the clipped part belongs to whatever is painted there
        const cb = { left: b.left, top: b.top, right: b.right, bottom: b.bottom };
        for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
          const ps = getComputedStyle(p);
          if (ps.overflowX === 'visible' && ps.overflowY === 'visible') continue;
          const pr = p.getBoundingClientRect();
          cb.left = Math.max(cb.left, pr.left); cb.top = Math.max(cb.top, pr.top);
          cb.right = Math.min(cb.right, pr.right); cb.bottom = Math.min(cb.bottom, pr.bottom);
        }
        if (cb.right - cb.left < 1 || cb.bottom - cb.top < 1) continue;
        const x = (cb.left + cb.right) / 2, y = (cb.top + cb.bottom) / 2;
        // off-viewport points are not hit-testable; elementFromPoint returns null
        if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) continue;
        probed++;
        const rec = document.elementFromPoint(x, y);
        if (!rec || rec === el || el.contains(rec) || rec.contains(el)) continue;
        bad.push({ kind: 'click-stolen', sel: sel(el), receiver: sel(rec) });
      }
      // Text contrast: WCAG ratio of the text colour over the nearest opaque
      // ancestor background. A theme that "applied" can still be unreadable,
      // and a screenshot is judged by the same eye that missed it. Text over
      // an image or a gradient cannot be judged this way and is skipped;
      // twelve per page, one per selector — candidates to confirm, not verdicts.
      try {
        const lum = c => {
          const m = (c || '').match(/[\d.]+/g); if (!m) return null;
          const [r, g, b] = m.map(Number), a = m.length > 3 ? Number(m[3]) : 1;
          if (a === 0) return undefined; if (a < 1) return null;
          const f = v => { v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; };
          return .2126 * f(r) + .7152 * f(g) + .0722 * f(b);
        };
        const bgLum = el => {
          for (let p = el; p; p = p.parentElement) {
            const s = getComputedStyle(p);
            if (s.backgroundImage !== 'none') return null;
            const l = lum(s.backgroundColor);
            if (l === null) return null; if (l !== undefined) return l;
          }
          return 1; // no background anywhere: the canvas is white
        };
        const seen = new Set();
        for (const el of document.querySelectorAll('body *')) {
          if (seen.size >= 12) break;
          if (![...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) continue;
          const cs = getComputedStyle(el), r = el.getBoundingClientRect();
          if (r.width < 1 || r.height < 1 || cs.visibility === 'hidden' || parseFloat(cs.opacity) < .1) continue;
          if (el.closest('[aria-hidden="true"], [disabled], :disabled')) continue;
          const fg = lum(cs.color), bg = bgLum(el);
          if (fg === null || fg === undefined || bg === null) continue;
          const ratio = (Math.max(fg, bg) + .05) / (Math.min(fg, bg) + .05);
          const px = parseFloat(cs.fontSize), bold = parseInt(cs.fontWeight, 10) >= 700;
          const need = (px >= 24 || (px >= 18.66 && bold)) ? 3 : 4.5;
          const key = sel(el);
          if (ratio < need && !seen.has(key)) {
            seen.add(key);
            bad.push({ kind: 'low-contrast', sel: key, ratio: Math.round(ratio * 10) / 10, fontSize: px, color: cs.color });
          }
        }
      } catch (e) { bad.push({ kind: 'sweep-error', check: 'low-contrast', error: String(e).slice(0, 120) }); }
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
