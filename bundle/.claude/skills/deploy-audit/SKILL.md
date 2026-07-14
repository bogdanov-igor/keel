---
name: deploy-audit
description: Audit deploy configs (fly.toml, Dockerfile, vercel.json, railway.json, docker-compose) for missing env vars, absent health checks, rollback gaps, and cross-environment drift — run before shipping infra changes or when deploys misbehave in one environment but not another.
---

# deploy-audit

Pure grep/parse of config files — no code execution, no judgment beyond severity grading.
Scope: the repo root, whatever deploy configs exist (`fly.toml`, `vercel.json`,
`railway.json`, `Dockerfile`, `docker-compose.yml`), `.env.example` (or equivalent),
and the environments in play (default: production and staging).

Before starting, read the matching section of memory/MEMORY.md and grep memory/ for
prior deploy lessons (platform quirks, past incidents on this project).

## Steps

1. **Parse deploy configs.** For each config file present:
   ```bash
   cd "$project_root"
   [ -f fly.toml ] && grep -n 'health_checks\|min_machines\|strategy\|rollback\|env\b' fly.toml
   [ -f Dockerfile ] && grep -n 'HEALTHCHECK\|ENV\|ARG\|USER\|EXPOSE' Dockerfile
   [ -f vercel.json ] && python3 -c "import json; print(json.dumps(json.load(open('vercel.json')), indent=2))"
   ```

2. **Env var completeness.** Extract all keys from `.env.example`, then check each
   deploy config for each key reference:
   ```bash
   while IFS= read -r key; do
     grep -l "$key" "$deploy_config" || echo "MISSING: $key"
   done < <(grep -oE '^[A-Z_]+' .env.example)
   ```
   Flag any key in `.env.example` not referenced in any deploy config.

3. **Health check validation.** Grep each config for a health check / liveness
   definition. Flag when missing:
   - `HEALTHCHECK` in Dockerfile.
   - `[http_service.checks]` or `health_checks` in `fly.toml`.
   - `healthCheck` in `railway.json`.

4. **Rollback configuration.** Grep for rollback / deploy strategy fields. Flag if:
   - No rolling deploy or blue-green strategy configured.
   - No `min_machines_running` (fly) or equivalent.
   - No `--wait-timeout` / health wait on deploy commands in CI.

5. **Multi-environment drift.** If per-environment configs exist (e.g.
   `fly.production.toml` / `fly.staging.toml`), diff resource settings (memory, cpu,
   replicas). Flag anywhere prod < staging on a resource — undersized production.

6. **Record findings** as BACKLOG.md lines:
   ```
   - [ ] P0 | deploy/Dockerfile | no HEALTHCHECK directive; add: HEALTHCHECK --interval=30s CMD curl -f http://localhost:3000/health || exit 1 | ev:Dockerfile | src:deploy-audit
   - [ ] P1 | deploy/fly.toml | DATABASE_URL missing from [env]; add DATABASE_URL = "{{secret:DATABASE_URL}}" or set via flyctl secrets set | ev:.env.example | src:deploy-audit
   ```
   Include the concrete fix in the line whenever it fits.

## Severity

- **P0** — missing health check in a deployed service, critical env var absent from
  every deploy config, no rollback/rolling strategy at all.
- **P1** — env var missing from one environment only, prod undersized vs staging,
  no health wait on CI deploy commands.
- **P2** — non-critical env vars unreferenced, drift in non-resource settings.
- **P3** — hygiene (unpinned base images noticed in passing, stale config comments).

## Wrap-up

- Clean result = every env var covered, health check present in each config, rollback
  strategy defined — say so explicitly rather than staying silent.
- Unrecognized deploy platform or config format: do not guess semantics; state plainly
  what was not covered.
- Fixes spanning several configs and environments are multi-unit work — via skill stage.
- A non-obvious platform gotcha uncovered during the audit → record via skill remember.

## Anti-patterns

- Reading `.env` or `.secrets.env` — audit structure only, never values; reference
  secrets as `{{secret:KEY}}`.
- Flagging env vars with obvious runtime defaults (PORT, NODE_ENV) as critical.
- Recommending multi-region when the current config provisions only one machine.
- Copying environment-specific secret values into findings or backlog lines.
