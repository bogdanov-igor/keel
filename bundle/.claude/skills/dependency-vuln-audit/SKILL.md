---
name: dependency-vuln-audit
description: Scan project dependencies for known CVEs and outdated packages using npm audit / pnpm audit / pip-audit / govulncheck, and land a prioritized remediation list in BACKLOG.md.
---

# Dependency vulnerability audit

Defaults: severity threshold `moderate` (ignore findings below it unless
asked), devDependencies excluded. Network access is needed for the CVE
database lookup; the scan itself is deterministic for a given lockfile.

## Procedure

1. Ground: read the matching section of `memory/MEMORY.md` and grep
   `memory/` for the affected packages — known-accepted risks and past
   upgrade traps should not be re-discovered.

2. Detect the package manager from the lockfile:

   ```bash
   [ -f package-lock.json ] && PM=npm
   [ -f yarn.lock ] && PM=yarn
   [ -f pnpm-lock.yaml ] && PM=pnpm
   { [ -f requirements.txt ] || [ -f pyproject.toml ]; } && PM=pip
   [ -f go.sum ] && PM=go
   ```

3. Run the scan, evidence to `.qa/deps/` (read back only the summary):

   ```bash
   mkdir -p .qa/deps
   # npm / yarn
   npm audit --json --audit-level=moderate --omit=dev > .qa/deps/audit.json 2>/dev/null
   # pnpm — use pnpm's own auditor (npm audit cannot read a pnpm lockfile)
   pnpm audit --json > .qa/deps/audit.json 2>/dev/null
   # Python — prefer `uv audit` (fast OSV/CVE), fall back to pip-audit
   uv audit --format json > .qa/deps/audit.json 2>/dev/null \
     || pip-audit --format json -o .qa/deps/audit.json 2>/dev/null
   # Go
   govulncheck -json ./... > .qa/deps/audit.json 2>/dev/null
   ```

   Tool not installed or lockfile missing → do not fake a clean result;
   record one BACKLOG.md line saying the scan could not run and stop.

4. Parse each finding: vuln id (CVE/GHSA), package, installed vs patched
   version, severity, fix available, dependency chain. For a flagged
   transitive dep, trace why it is present — `pnpm why <pkg>` or
   `npm ls <pkg>` — and report the shortest path to a direct dependency
   so the owner knows which top-level package to bump.

5. Outdated check alongside the CVE scan:

   ```bash
   npm outdated --json > .qa/deps/outdated.json 2>/dev/null
   ```

   Flag packages with major-version lag (current vs latest); they
   accumulate CVE debt silently even when today's scan is clean.

6. Prioritize by (1) severity, (2) direct before transitive, (3) fix
   available. Assign each finding one action:
   - `upgrade` — patched version exists; give the exact command
     (e.g. `npm install lodash@4.17.21`).
   - `patch` — covered by a plain `npm audit fix` (never `--force`).
   - `replace` — no fix published; swap the package.
   - `accept` — low severity, no fix, vulnerable code path unreachable;
     document the reasoning via skill `remember`.

7. Write findings into `BACKLOG.md`, severity mapped to priority
   (critical→P0, high→P1, moderate→P2, low→P3):

   ```text
   - [ ] P0 | deps | CVE-2024-12345 lodash 4.17.20→4.17.21, direct, upgrade | ev:.qa/deps/audit.json | src:dependency-vuln-audit
   - [ ] P2 | deps | react major lag 17→19, no open CVE | ev:.qa/deps/outdated.json | src:dependency-vuln-audit
   ```

   Remediation that spans many packages or involves breaking major
   upgrades is big work — run it via skill `stage`, not inline.

8. After applying fixes, rerun the scan to confirm clean before closing
   the checkboxes.

## Report

Totals honestly: N vulnerabilities (critical/high/moderate/low counts),
M packages with major-version lag, and what was not scanned (e.g. dev
deps excluded, a second lockfile in a workspace).

## Anti-patterns

- Auto-applying `npm audit fix --force` — breaking changes in major
  upgrades need manual review.
- Marking a transitive vulnerability `accept` without checking whether
  the vulnerable code path is reachable.
- Skipping outdated major-version packages because the CVE scan is clean.
- Conflating devDependency CVEs with prod CVEs when dev deps are
  excluded; note them separately if they surface.
