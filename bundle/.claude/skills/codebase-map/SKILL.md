---
name: codebase-map
description: Produce a structural map of a codebase — top-level directories, entry points, framework, major modules, config files, dependency counts — using only grep and filesystem commands; use before an audit or any work in an unfamiliar repo.
---

# codebase-map

Maps structure only. Deterministic for a given codebase state: every step is a
filesystem or grep command — no builds, no installs, no narrative prose.

## Inputs

| Input | Default | Notes |
|---|---|---|
| project path | (required) | absolute path to the repo root |
| max depth | 3 | directory scan depth |
| exclude | `node_modules .git dist build .next __pycache__` | directories to skip |

Before starting, read the matching section of memory/MEMORY.md and grep memory/
for prior notes on this repo — an earlier map or lesson may already cover it.

## Steps

1. Directory tree.
   ```bash
   find "$project_path" -maxdepth "$max_depth" -type d \
     $(printf " -not -path '*/%s/*'" "${exclude[@]}") | sort
   ```

2. Framework detection.
   ```bash
   # JS/TS: check package.json dependencies
   grep -E '"next"|"vite"|"remix"|"astro"|"nuxt"' "$project_path/package.json" 2>/dev/null
   # Python
   ls "$project_path/pyproject.toml" "$project_path/setup.py" 2>/dev/null
   # Go
   ls "$project_path/go.mod" 2>/dev/null
   # Rust
   ls "$project_path/Cargo.toml" 2>/dev/null
   ```

3. Entry points.
   ```bash
   grep -rn '"main"\|"module"\|"exports"' "$project_path/package.json" 2>/dev/null | head -20
   find "$project_path/src" "$project_path/app" -maxdepth 2 \
     -name "index.*" -o -name "main.*" -o -name "server.*" 2>/dev/null | head -20
   ```

4. Major modules. List subdirectories of `src/`, `app/`, `lib/`, `packages/` at
   depth 1. For each: count files (`find <dir> -type f | wc -l`) and note the
   dominant extension.

5. Key config files.
   ```bash
   find "$project_path" -maxdepth 1 -name "*.config.*" -o -name "*.json" \
     -o -name "Dockerfile" -o -name "docker-compose*.yml" 2>/dev/null | sort
   ```

6. Dependency count.
   ```bash
   jq '.dependencies | length, .devDependencies | length' "$project_path/package.json" 2>/dev/null
   ```

## Output

Report the map as a short markdown block in the reply, e.g.:

```
Framework: Next.js 14 (TypeScript)
Entry points: src/app/layout.tsx, src/server.ts
Modules: monitors (src/app/monitors, 12 files, .tsx), ...
Config: next.config.ts, tailwind.config.ts, Dockerfile
Dependencies: 142 prod / 38 dev; tree depth mapped: 3
```

If the map surfaces an actionable defect (missing manifest, no entry point,
orphaned module), log it as a BACKLOG.md line:
`- [ ] P0..P3 | <surface> | <one line> | ev:<path> | src:codebase-map`.
A surprising structural fact worth keeping (e.g. non-obvious monorepo layout)
goes to memory via skill remember. If the map is step one of larger
multi-surface work, continue via skill stage.

## Success criteria

- Complete: framework detected AND at least one entry point found AND module
  list non-empty.
- Not applicable: project path does not exist or is empty — say so and stop.
- Partial: monorepo with more than 10 packages — auto-discovery may be
  incomplete; map top-level packages only and flag the gap explicitly.

## Anti-patterns

- Do not recurse into `node_modules`, `.git`, `dist` — use the exclude list.
- Do not infer framework from file names alone; confirm with `package.json` or
  the language manifest.
- Do not produce a narrative description of the codebase; this skill maps
  structure only.
- Do not run build tools or install dependencies as part of this skill.
