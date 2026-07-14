---
name: ci-pipeline-setup
description: Scaffold or audit a CI pipeline (GitHub Actions / GitLab CI / Bitbucket / CircleCI) — lint, test, build, security scan, deploy stages with caching and branch rules; use when adding CI to a repo or checking an existing pipeline for gaps.
---

# ci-pipeline-setup

Two modes: **scaffold** (no CI yet — write it) and **audit** (CI exists —
validate it, file gaps). Establish up front: repo root, CI provider
(github-actions | gitlab-ci | bitbucket | circleci), primary runtime
(node | bun | python | go | rust | java), and deploy target
(vercel | fly | railway | k8s | docker | none). With no deploy target,
the pipeline stops at build. Workflow dir defaults to `.github/workflows`
for GitHub. Before starting, read the matching section of memory/MEMORY.md
and grep memory/ for prior CI lessons on this repo.

## Steps

1. **Inventory existing CI.** Grep the workflow dir for YAML files:
   ```bash
   find "$PROJECT/.github/workflows" -name "*.yml" -o -name "*.yaml" 2>/dev/null
   ```
   Parse which stages are present. None found → scaffold from scratch.

2. **Detect package manager and test command.** Do not assume npm:
   ```bash
   [ -f bun.lockb ] && PM=bun || { [ -f pnpm-lock.yaml ] && PM=pnpm || PM=npm; }
   grep -m1 '"test"' package.json 2>/dev/null | awk -F'"' '{print $4}'
   ```
   For other runtimes, look for the idiomatic runner (pytest, go test,
   cargo test, mvn/gradle test).

3. **Validate required stages.** For each existing workflow, confirm:
   - lint or typecheck job — grep `tsc --noEmit|eslint|biome`
   - test job — grep `vitest|jest|pytest|go test`
   - build job
   - security scan — grep `trivy|snyk|grype|audit`
   - branch rules — `on: push: branches` or `pull_request` triggers

4. **Validate caching.** Grep for `actions/cache` or a `cache:` key. Flag
   a missing cache for `node_modules`, build artifacts, or the runtime's
   cache dir (pip, go build, cargo registry, gradle).

5. **Write or patch the workflow.** For each missing stage, append a
   minimal correct job block. Deploy job by target:
   - vercel → `vercel deploy --prebuilt` with `VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}`
   - fly → `flyctl deploy` with `FLY_API_TOKEN`
   - docker → `docker buildx build --push`
   Secrets stay references only — CI-native `${{ secrets.KEY }}` in the
   workflow, `{{secret:KEY}}` elsewhere; values live in `.secrets.env`.

6. **Record the outcome.** Files written go in your reply with paths.
   Audit gaps you did not fix land as BACKLOG.md lines:
   ```
   - [ ] P0..P3 | ci | <one line> | ev:.github/workflows/ci.yml | src:ci-pipeline-setup
   ```
   Severity: P0 plaintext secret in a workflow; P1 missing test stage or
   tests skipped on main; P2 missing security scan or caching; P3 style.
   A non-obvious repo-specific gotcha → record via skill remember.

## Done when

- lint + test + build stages present, caching configured, no plaintext
  secret values anywhere in workflow files.
- Not done if any required stage is absent or a secret value is embedded —
  fix it or file the BACKLOG line.
- Monorepo with multiple runtimes needing a custom matrix is multi-unit
  work — route it through skill stage instead of improvising one workflow.

## Anti-patterns

- Embedding secret values — use `${{ secrets.KEY }}` / `{{secret:KEY}}`
  references only.
- A workflow that skips tests on push to main ("too slow" is not a reason).
- Deploy steps on PRs — deploy only on merge to the protected branch.
- Assuming npm when `bun.lockb` or `pnpm-lock.yaml` is present.
