#!/usr/bin/env bash
# Keel — every number the documentation quotes, measured from the tree.
#
#   bash test/metrics.sh
#
# Prints `key=value`, one per line, and nothing else. Five releases in a row
# shipped a stale figure — the contract's line count, the shell totals, the
# bundle size, the skill count — because each was re-measured by hand and the
# hand skipped a file. The 1.8.0 docs pass repeated it: 93 lines in the guides
# where the contract had 94. Measuring is a script's job; 01-metrics.sh
# compares this output against every claim in the README, the badges, the
# guides and the diagrams, so a number can now go stale only by failing the
# suite first.
#
# The counts deliberately match the commands the docs hand the reader in
# "Reproducing the numbers" — `cat | wc -l` over a find, `du -sk`, `find -type f`
# — so a reader who runs them by hand gets the same figures.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

# Shipped: what lands inside somebody's project. Maintainer-only: the builder
# and this suite, which never leave the repo. The docs quote both and the sum.
shipped_list() { find "$ROOT/install.sh" "$ROOT/bundle/.claude" -type f -name '*.sh'; }
maint_list()   { find "$ROOT/build-archive.sh" "$ROOT/test" -type f -name '*.sh'; }

count() { wc -l | tr -d ' '; }
lines() { tr '\n' '\0' | xargs -0 cat 2>/dev/null | wc -l | tr -d ' '; }

contract="$ROOT/bundle/.claude/CLAUDE.md"
sweep="$ROOT/bundle/.claude/skills/qa-browser/sweep.mjs"

shipped_files="$(shipped_list | count)"
shipped_lines="$(shipped_list | lines)"
maint_files="$(maint_list | count)"
maint_lines="$(maint_list | lines)"

printf 'contract_lines=%s\n'           "$(wc -l < "$contract" | tr -d ' ')"
printf 'contract_chars=%s\n'           "$(wc -c < "$contract" | tr -d ' ')"
printf 'skills=%s\n'                   "$(find "$ROOT/bundle/.claude/skills" -mindepth 1 -maxdepth 1 -type d | count)"
printf 'agents=%s\n'                   "$(find "$ROOT/bundle/.claude/agents" -maxdepth 1 -type f -name '*.md' | count)"
printf 'hooks=%s\n'                    "$(find "$ROOT/bundle/.claude/hooks" -maxdepth 1 -type f -name '*.sh' | count)"
printf 'shipped_shell_files=%s\n'      "$shipped_files"
printf 'shipped_shell_lines=%s\n'      "$shipped_lines"
printf 'maintainer_shell_files=%s\n'   "$maint_files"
printf 'maintainer_shell_lines=%s\n'   "$maint_lines"
printf 'shell_files=%s\n'              "$((shipped_files + maint_files))"
printf 'shell_lines=%s\n'              "$((shipped_lines + maint_lines))"
printf 'mjs_lines=%s\n'                "$(wc -l < "$sweep" | tr -d ' ')"
printf 'bundle_kb=%s\n'                "$(du -sk "$ROOT/bundle" | awk '{print $1}')"
printf 'bundle_files=%s\n'             "$(find "$ROOT/bundle" -type f | count)"
