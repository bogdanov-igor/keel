---
name: architecture-review
description: Evaluate a codebase's architectural fitness — layer separation, coupling, scalability risks, and alignment with stated goals — and file graded findings into BACKLOG.md. Use when structure, not line-level code, is in question.
---

# architecture-review

Structural review of a project. Inputs to settle before starting:

- project path (root of the codebase under review)
- stated architectural goals, if any (e.g. "horizontal scale", "multi-tenant") — these drive the fitness verdicts
- focus areas: layers, coupling, scalability, security-boundaries (default: all four)

Before starting, read the matching section of memory/MEMORY.md and grep memory/ for
prior architecture notes on this project — earlier reviews often already name the hotspots.

## Steps

1. **Build a lightweight map.** `find "$project_path" -maxdepth 3 -type d` (excluding
   vendor/node_modules dirs) to identify modules, entry points, and layer candidates.

2. **Layer separation check.**
   ```bash
   # Cross-layer imports: UI importing from DB layer directly
   grep -rn "from.*db\|from.*prisma\|from.*supabase" "$project_path/src/components/" 2>/dev/null
   grep -rn "from.*components\|from.*ui" "$project_path/src/api" "$project_path/src/server" 2>/dev/null
   ```
   Flag files where UI imports the data layer, or the API layer imports UI.

3. **Coupling analysis.**
   ```bash
   # Fan-in per module: imports of the module from outside it
   for module in "${modules[@]}"; do
     grep -rn "from.*$module" "$project_path/src/" | grep -v "/$module/" | wc -l
   done
   ```
   Modules with fan-in > 10 are high-coupling hotspots.

4. **Scalability risk scan.**
   ```bash
   grep -rn "global\|singleton\|in-memory\|localStorage\|__dirname" \
     "$project_path/src/" --include="*.ts" --include="*.tsx" | grep -v node_modules
   ```
   Flag in-process state that prevents horizontal scaling, and missing cache layers.

5. **Security boundary check.**
   ```bash
   grep -rn "req.body\|JSON.parse\|eval\|Function(" \
     "$project_path/src/api" "$project_path/app/api" 2>/dev/null
   ```
   Flag unvalidated inputs at the API boundary.

6. **Assess against goals.** For each stated goal, evaluate whether the current structure
   supports it and give a verdict: aligned / partial / misaligned. Name the concrete blocker
   for anything misaligned (e.g. "in-process session store blocks horizontal scale").
   When goals were provided, this section is the primary output — do not skip it.

7. **Grade and file findings.** Severity mapping:
   - P0 — blocks a stated goal (goal verdict: misaligned)
   - P1 — critical layer violation or security-boundary gap
   - P2 — degrades reliability (high-coupling hotspot, risky shared state)
   - P3 — structural tech debt

   Append one line per finding to BACKLOG.md:
   ```
   - [ ] P1 | src/components/Dashboard.tsx | UI imports prisma client directly; move DB access behind a service layer | ev:src/components/Dashboard.tsx:4 | src:architecture-review
   ```
   Include the goal-fitness verdicts in your summary to the user, with blockers per
   misaligned goal. If fixing the findings spans multiple surfaces or sessions, open
   it as a stage via skill stage instead of ad-hoc edits.

8. **Escalation.** If the codebase uses an uncommon framework the grep heuristics can't
   parse, say so explicitly and recommend a manual review — do not fabricate findings
   from patterns that didn't match.

If the review taught something non-obvious about this codebase's structure (a recurring
hotspot, a framework quirk that defeats the greps), record it via skill remember.

## Anti-patterns

- Do not report style issues (formatting, naming) — those belong to a code review, not here.
- Do not recommend specific libraries; recommend structural patterns only.
- Do not skip the goal-fitness section when goals were provided; that is the primary output.
- Do not rate all findings P0/P1 to force attention; calibrate severity carefully.
