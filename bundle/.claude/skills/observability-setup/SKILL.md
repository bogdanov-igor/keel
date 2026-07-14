---
name: observability-setup
description: Audit or scaffold structured logging, error tracking, metrics, and alerting for a production service — gaps land as BACKLOG.md findings, missing instrumentation is stubbed in.
---

# Observability setup

## Scope

One pass = one service. Establish up front: runtime (node / bun /
python / go / rust), providers in use (error tracking: sentry, bugsnag,
rollbar; metrics: prometheus, datadog, otel; logging: pino, winston,
stdout-json), alert channels, and SLO targets (e.g. error rate 0.1%,
p99 latency 500ms). Providers are auto-detected from dependencies when
not stated. If SLO targets are unknown and no existing baselines are
found, ask the owner once; no answer → park the alerting part in
`PARKED.md` and still deliver the logging/error/metrics checks.
Scaffolding across several services is a stage (skill `stage`).

Before starting, read the matching section of `memory/MEMORY.md` and
grep `memory/` for this service's known observability traps.

## Checks

1. Detect existing instrumentation.
   ```bash
   grep -rn --include="*.ts" --include="*.js" --include="*.py" \
     'Sentry\|pino\|winston\|prometheus\|opentelemetry\|@sentry\|structlog' \
     src/ app/ lib/ 2>/dev/null | head -40
   ```
   Build a map of provider → file → what it covers.

2. Structured logging. Count raw `console.log` / `console.error` /
   `print(` in production code paths:
   ```bash
   grep -rn 'console\.log\|console\.error' --include="*.ts" --include="*.tsx" src/ app/ | wc -l
   ```
   Any count above zero in prod paths is a finding (exclude test
   files, scripts, CLI tools). Also flag log output missing `level`,
   `trace_id`, or `request_id`.

3. Error boundary / unhandled rejection.
   ```bash
   grep -rn 'process\.on.*uncaughtException\|process\.on.*unhandledRejection' --include="*.ts" src/
   grep -rn 'ErrorBoundary\|error\.tsx\|error\.js' app/ src/
   ```
   Flag when neither a global error handler nor a framework error
   boundary exists.

4. Metrics. Grep for custom metric emission (counter, histogram,
   gauge). Flag hot paths — API handlers, background workers — with
   no metrics at all.

5. Alert rules. For each metrics provider, check its config files for
   alert/threshold definitions and validate against the SLO targets:
   error-rate alert threshold ≤ target error rate; latency alert
   threshold ≤ target p99. Flag missing or over-threshold alerts.

6. Scaffold what is missing. For each gap, append a minimal stub
   (import + init) to the appropriate entry file, marked
   `// TODO: observability-setup — review before commit`. DSNs and
   API keys are referenced as `{{secret:SENTRY_DSN}}` etc.; values
   live in `.secrets.env`.

## Severity and output

- P0 — no error tracking and no global error handler on a production
  service (failures are invisible).
- P1 — unstructured logging on prod paths; SLO alert missing or set
  looser than the target.
- P2 — hot paths without metrics; logs missing trace_id/request_id
  correlation.
- P3 — polish (log field naming, dashboard gaps).

Write each finding into `BACKLOG.md`:
`- [ ] P1 | <service> | <gap, one line> | ev:<path or grep output> | src:observability-setup`

Report totals honestly (found N: P0/P1/P2/P3), list files stubbed, and
state what the pass did not cover. A healthy baseline = structured
logging present, error handler present, at least one metrics provider,
SLO alerts configured — say explicitly whether the service meets it.

## Anti-patterns

- Do not install providers — write stubs and reference
  `{{secret:...}}` keys only.
- Do not flag console.log in test files, scripts, or CLI tools.
- Do not generate alert rules that require infra access the repo does
  not have.
- Do not recommend multiple overlapping error-tracking providers.
