# OPS — standing duties

Ownership made routable: recurring duties with cadence, each mapped to
a skill. A duty whose cadence has elapsed since its `last:` stamp is
overdue. Stamp `last:` when a duty completes.

## Mode

`mode: build`

Two modes: `build` while the product is being made, `live` once it is
in front of users. Flipped to `live` only by the owner's explicit
go-live call; flipping back is also the owner's call.

- **build** — no scheduled token burns. Duties run when a session is
  already open and idle (no P0/P1, nothing claimed), or when the owner
  asks. The session-start sweep notes overdue duties but queues at
  most one.
- **live** — full cadence. On the flip, set up the schedule as a stage
  so daily/weekly duties fire without an open session; from then on
  overdue duties become `BACKLOG.md` items automatically. Five ways
  to run a duty without asking, reaching different things: `/loop`
  inside an open session (repeats a prompt on an interval, dies with
  the session); system cron running
  `claude -p` on the owner's box (everything: local files,
  `.secrets.env`, MCP — but `-p` starts in manual permission mode, so
  pass `--permission-mode` and allow rules or the run silently denies);
  Claude Desktop scheduled tasks (local files and MCP, only while the
  app is open); cloud routines (a fresh clone of the repository, no
  local files, no local MCP, one-hour minimum); GitHub Actions (a fresh
  clone, no daily cap). The kernel schedules nothing by itself.

Format: `- [cadence] duty | skill(s) | last:YYYY-MM-DD`

## Daily

- [daily] Triage user feedback, comments, support inbox — every report is a defect or a feature signal until proven otherwise | support-playbook, customer-reply-draft | last:never
- [daily] Error and load review: logs, uptime, resource pressure | observability-setup | last:never
- [daily] Burn down BACKLOG P0/P1 | — | last:never

## Weekly

- [weekly] Whole-site health sweep, all public pages, 3 viewports | site-sweep, qa-browser | last:never
- [weekly] Security: dependency CVEs, exposed surfaces, server hardening | dependency-vuln-audit, security-audit | last:never
- [weekly] Funnel: signup → activation → retention drop-offs vs analytics | growth-funnel-audit | last:never
- [weekly] Performance: hot paths, slow queries, N+1 | performance-profiling | last:never

## Monthly

- [monthly] SEO + Core Web Vitals on public routes | seo-audit | last:never
- [monthly] Pricing/packaging consistency across code, copy, config | pricing-packaging-audit | last:never
- [monthly] Competitor moves and positioning drift | competitor-analysis, market-positioning-analysis | last:never
- [monthly] Messaging claim drift across surfaces | messaging-copy-audit | last:never
- [monthly] Module adoption / PMF classification | product-pmf-eval | last:never
- [monthly] Tech-debt paydown list refresh | tech-debt-audit | last:never
- [monthly] Memory garden: dedup, promote, prune the index | memory-consolidation | last:never
- [monthly] Sweep Claude Code's own auto memory for corrections that belong to the project or the kernel | adopt-feedback | last:never
- [monthly] Resource and spend review: server, SaaS subscriptions, API costs — against what the product actually uses | — | last:never
- [monthly] Kernel cost: `/skill-doctor` (or `/doctor`) — which skills were never invoked and what the listing costs; read the report only, decline its offers to edit `.claude/` here (kernel changes go through the keel repo); hide unused skills with `skillOverrides` in this project's settings | — | last:never
- [monthly] Claude Code changelog: new hook events, front-matter fields, settings — what the kernel could replace with a mechanism or delete; file the answer as `src:kernel` | — | last:never
- [quarterly] Kernel assumptions review: for each hook, rule and skill — which inability of the model does it compensate, and is that still true; what is stale is proposed for removal | — | last:never

## Access registry

Names only — values live in `.secrets.env`. The owner grants access;
what exists is recorded here so every session knows its reach:

- server / deploy: (fill in: host alias, method)
- analytics: (fill in: project, dashboard)
- publishing: (fill in: blog, social, launch platforms)
- billing dashboard: (fill in)
- error tracking / logs: (fill in)
