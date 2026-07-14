---
name: e2e-playwright-cli
description: Run scripted, repeatable browser checks through the Playwright CLI via Bash — results land on disk under .qa/ and only the needed bytes are read back; the token-cheap path for non-interactive verification.
---

# e2e-playwright-cli

Scripted browser checks (page loads, selector visible, screenshot
saved) do not need an interactive browser tool that streams every
result into context. The CLI writes results to disk and the agent reads
only the bytes each check needs — roughly 4x fewer tokens on typical
browser tasks, per community benchmarks. That results-to-disk
discipline is the whole point of this skill.

Scope: non-interactive, repeatable checks against known URLs with a
known list of assertions. Programmatic defect sweeps, user flows, and
theme checks belong to skill `qa-browser` (Playwright library scripts);
both share the `.qa/` output convention.

## Inputs

- URL(s) to drive.
- The observable checks to run ("title contains X", "selector #foo
  visible", "screenshot saved").
- Output dir: `.qa/` (gitignored by the installer) — the same home as
  qa-browser's artifacts.

## Procedure

1. **Read the help before running anything.** `@playwright/cli` is
   early (0.1.x) and its flags change between releases — run
   `npx -y @playwright/cli@latest --help` (and `<subcommand> --help`)
   and use only the surface it actually exposes. Do not assume command
   names or flags from memory.
2. **Run through Bash, results to disk.** Drive the page with
   `npx -y @playwright/cli@latest <args>` and direct every output —
   screenshots, JSON, traces — into `.qa/`. One-shot invocations that
   exit on their own run as plain Bash calls. Anything that keeps a
   browser alive across calls (session/server mode, a reused browser
   for a batch of checks) launches via skill `safe-dev-server` with a
   TTL, so the Chromium child stays under the circuit breaker instead
   of running unbounded.
3. **Read selectively.** Open only the result file each check needs —
   grep the saved HTML/JSON, view one screenshot. Never cat a whole
   trace or HTML dump into context; that throws away the entire token
   saving.
4. **Give every check a verdict.** Each requested check maps to
   PASS/FAIL backed by an on-disk evidence path. A check that could
   not be evaluated (CLI not resolvable, page unreachable) is a
   failure to report, not a silent skip.

## Output

- Failures land in `BACKLOG.md`:
  `- [ ] P0..P3 | <surface> | <failed check, one line> | ev:<.qa/ path> | src:e2e-playwright-cli`
- Clean result: state which checks ran against which URLs, so "clean"
  is a scoped claim, not a shrug.
- A task that needs interactive stepping or live inspection to
  diagnose is outside this skill — script the flow with the Playwright
  library per skill `qa-browser` instead.

## Gotchas

- No global install: always `npx -y @playwright/cli@latest`, so any
  checkout runs it the same way.
- Runs are deterministic for static pages; assertion phrasing is
  model-interpreted — write checks as observable facts ("selector X
  visible"), not impressions ("page looks right").
- Do not invent CLI flags — 0.1.x moves fast; read `--help` first,
  every time.
