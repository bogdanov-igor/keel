---
name: product-pmf-eval
description: Classify each product module as core-ICP, supporting, nice-to-have, balloon-ware, or uncertain from code-level adoption signals and flow completeness; use when deciding what to cut, demote, or fix to sharpen product-market fit.
---

# product-pmf-eval

Evaluate how well the product's module set serves its ICP, using only evidence
observable in code (plus analytics data if the owner provides an export).
The output is a per-module classification and a short list of cut/demote/fix
recommendations queued in BACKLOG.md.

## Inputs

- Project root path.
- ICP definition — one sentence, e.g. "solo dev, price-sensitive, needs uptime
  + status pages". Required: if none is given and none is inferable from the
  README/landing copy, ask the owner one targeted question before proceeding.
- Optional: explicit module list (otherwise auto-discovered), path to an
  analytics export (PostHog events, DAU/WAU counts, funnel drop-offs).

Before starting, read the matching section of memory/MEMORY.md and grep
memory/ for prior notes on this product's ICP, modules, or past audits —
earlier findings often settle a module's classification outright.

## Procedure

1. **Module discovery.** If no module list was given, scan `app/`, `pages/`,
   `src/routes/`, and sidebar/tab/menu components. Produce a flat list of
   module names with entry-point paths.

2. **Code-level signals per module.** Measure:
   - Route reachability: linked from primary nav, or orphaned?
   - Flow completeness: TODO/FIXME in the critical path, stubbed handlers,
     placeholder UI (`grep -rn "TODO\|FIXME\|Coming soon\|TBD" <module_path>`).
   - Abstraction depth: count indirection layers
     (route → page → hook → service → API → DB).
   - Test proxy: any test file referencing the module
     (`grep -rl "<module_name>" tests/`).
   - Error handling: real error states vs generic fallback vs none.

3. **Adoption data.** If an analytics export was provided, parse event counts
   per module. If not, mark the evaluation "code-only" and say so in the
   summary — never invent usage numbers.

4. **Classify each module.**

   | Class | Criteria |
   |---|---|
   | core-icp | ICP needs it daily, flow complete, low abstraction debt, usage evidence |
   | supporting | ICP benefits, not a daily driver, flow works |
   | nice-to-have | Tangential to the ICP's job-to-be-done, works, deferrable |
   | balloon-ware | Broken/stubbed flows, high abstraction, no adoption signal, ICP doesn't ask for it |
   | uncertain | Insufficient signal — resolve with more code evidence first |

5. **Aggregate PMF signal.** core_ratio = core-icp / total;
   balloon_ratio = balloon-ware / total. Signal: strong (core ≥ 0.5 and
   balloon < 0.15), weak (core < 0.3 or balloon > 0.3), otherwise mixed.

6. **Recommendations.** For each balloon-ware module pick an action
   (cut | demote | fix-then-reeval), estimate effort_to_fix
   (trivial | small | medium | large), and name the risk_if_cut.

## Output

State the PMF signal, ratios, and per-module table in your reply, then queue
each actionable finding as a BACKLOG.md line:

```
- [ ] P1 | product | core-icp module "monitors" has stubbed alert flow | ev:src/routes/monitors/alerts.tsx | src:product-pmf-eval
- [ ] P2 | product | balloon-ware "incident-mgmt": cut (effort n/a, risk: none observed) | ev:src/routes/incident-management/ | src:product-pmf-eval
```

Severity guide: incomplete flow inside a core-icp module → P1; balloon-ware
cut/demote candidate → P2; debt in nice-to-have modules → P3. Actually cutting
modules is the owner's call — the backlog line proposes, it does not execute.

If acting on the findings spans multiple modules or surfaces, run it via
skill stage. A non-obvious insight about this product's ICP or module economics
(e.g. "every orphaned route here traces back to the 2024 enterprise pivot")
→ record via skill remember.

If >50% of modules land in uncertain, stop and ask the owner one targeted
question (usually: who actually uses this, or where is the analytics export)
rather than padding the report with guesses.

## Anti-patterns

- Do not hallucinate adoption numbers — use only code-observable signals or
  explicitly provided data.
- Do not mark a module balloon-ware on abstraction depth alone; require at
  least two corroborating signals.
- Do not ignore prior memory notes or open BACKLOG.md findings that already
  cover a module — reuse them as evidence instead of re-deriving.
- Do not classify uncertain liberally — it defers the decision; resolve with
  code evidence first.
