---
name: seo-audit
description: Audit on-page SEO for all public-facing routes — metadata completeness, robots.txt, sitemap, Core Web Vitals readiness, heading hierarchy — findings ranked P0-P3 into BACKLOG.md.
---

# SEO audit

A scoped audit; the conventions of skill `audit` apply (WIP limit,
evidence per finding, honest coverage statement). Public-facing routes
only. Settle up front: repo root, framework (nextjs / remix / astro /
nuxt / sveltekit / generic — it determines where metadata is declared),
brand name if a title-suffix pattern should be validated, and the
sitemap path (default `public/sitemap.xml`).

Before starting, read the matching section of `memory/MEMORY.md` and
grep `memory/` for prior SEO traps on this project.

## Procedure

1. **Route discovery.** Next.js: enumerate `app/**/page.tsx` and
   `pages/**/*.tsx`, extract route paths. Other frameworks: parse the
   router config file.
   ```bash
   find "$root/app" -name "page.tsx" 2>/dev/null | \
     sed "s|$root/app||;s|/page.tsx||"
   ```

2. **Metadata completeness per route.** For each public route, grep its
   file for:
   - `title` / `<title>` — required.
   - `description` meta — required; flag if >160 or <50 chars.
   - `og:title`, `og:description`, `og:image` — required for social sharing.
   - `twitter:card`, `twitter:image` — recommended.
   - Canonical URL tag.
   ```bash
   grep -n 'title\|description\|og:\|twitter:\|canonical' "$route_file"
   ```

3. **robots.txt.**
   ```bash
   cat "$root/public/robots.txt" 2>/dev/null || echo "MISSING"
   grep -i 'Disallow: /' "$root/public/robots.txt" 2>/dev/null && echo "WARN: blocks all"
   ```
   Flag: missing file, blocks all crawlers, missing `Sitemap:` directive.

4. **Sitemap.**
   ```bash
   [ -f "$root/$sitemap_path" ] && \
     grep -c '<url>' "$root/$sitemap_path" || echo "MISSING"
   ```
   Flag: missing sitemap, URLs not matching discovered routes, absent `lastmod`.

5. **Core Web Vitals readiness.** Grep for:
   - Images without `width`/`height` attributes → CLS risk.
   - `next/image` or equivalent lazy-loading for large images.
   - Render-blocking scripts in `<head>` without `defer`/`async`.
   - Font preloading (`<link rel="preload">` for WOFF2).
   ```bash
   grep -rn '<img\b' --include="*.tsx" --include="*.html" \
     "$root/app" "$root/src" | grep -v 'width=\|height='
   ```

6. **Heading hierarchy.** Per route: exactly one `<h1>`; no `<h3>`
   before its `<h2>`.

Dynamic metadata (`getServerSideProps`, remix loaders, computed
`generateMetadata`) is not statically analyzable — either check the
rendered `<head>` in a browser pass (server via skill `safe-dev-server`,
inspection via skill `qa-browser`) or list those routes as not covered.

## Severity

- P0 — landing route missing title, description, or `og:image` (social
  shares render a blank card); robots.txt missing or blocking all crawlers.
- P1 — the same gaps on other public routes; sitemap missing; sitemap
  out of sync with real routes.
- P2 — description length out of the 50-160 band; missing canonical or
  twitter tags; CLS-risk images; render-blocking head scripts; heading
  hierarchy defects.
- P3 — missing font preload and similar polish.

## Findings

Each finding lands as a BACKLOG.md line with file evidence and a
concrete fix hint in the description when it fits:

```
- [ ] P0 | seo:/ | og:image missing — social shares render blank card | ev:app/(marketing)/page.tsx:5 | src:seo-audit
- [ ] P0 | seo:site | robots.txt missing — sitemap undiscoverable | ev:public/robots.txt | src:seo-audit
- [ ] P1 | seo:/pricing | description meta 210 chars — truncated in SERPs | ev:app/(marketing)/pricing/page.tsx:3 | src:seo-audit
```

Typical fixes worth suggesting inline: `export const metadata =
{ openGraph: { images: ['/og-default.png'] } }` for missing og:image;
a `User-agent: * / Allow: / / Sitemap: <url>` robots.txt for a missing
one; shortening a description to ≤160 chars.

Close the audit with honest totals — routes audited, findings per
severity, and which routes or checks were not covered. A lesson worth
keeping (framework-specific metadata quirk, recurring gap) → skill
`remember`.

## Gotchas

- Skip authenticated and admin routes — SEO applies to public surfaces only.
- Flag only structural and technical gaps; never recommend keyword
  stuffing or invisible text.
- A description of 155-165 chars is a warning, not a P0/P1.
- Report a missing sitemap as a gap; do not generate its content —
  sitemap generation belongs in build tooling.
