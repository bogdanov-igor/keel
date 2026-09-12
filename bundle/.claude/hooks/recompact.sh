#!/usr/bin/env bash
# SessionStart hook, matcher "compact": hand back what compaction dropped.
#
# Compaction summarises the transcript and re-injects neither the skill listing
# nor the project state the session was carrying, so the model wakes up fluent
# in the code but blind to which stage it is in, which backlog items it claimed,
# and which gates it owes. Those three facts are cheap to recompute from disk.
#
# Budget: at most 12 lines. Everything printed here lands in context on every
# compaction, so this is a pointer back to the files, never a digest of them.
#
# Which project: the branch the session is actually on, which is not always
# CLAUDE_PROJECT_DIR. Measured on Claude Code 2.1.87: a session launched with
# `claude --worktree` gets CLAUDE_PROJECT_DIR = the worktree, while a session
# that entered a worktree later keeps it on the main checkout and only the
# payload's `cwd` follows (docs). The stage that matters after a compaction, and
# the claims that matter, are the ones on the branch being worked — so `cwd`
# wins: walk up from it to the nearest ancestor that looks like a project (a
# `.claude/` directory or a `BACKLOG.md`). A payload without `cwd`, empty stdin
# (a manual run) or a cwd outside any project falls back to the old env-based
# behaviour. Reading stdin is skipped on a terminal so a hand run cannot hang.
# Never fails and never blocks: exit 0 on every path.
set -uo pipefail
MAXLEN=140

payload=""
[ -t 0 ] || payload="$(cat)"

cwd=""
if [ -n "$payload" ]; then
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
  [ -z "$cwd" ] && cwd="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("cwd","") or "")' 2>/dev/null || true)"
fi

PROJECT=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  dir="$(cd "$cwd" 2>/dev/null && pwd -P)" || dir=""
  while [ -n "$dir" ]; do
    if [ -d "$dir/.claude" ] || [ -f "$dir/BACKLOG.md" ]; then PROJECT="$dir"; break; fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
fi
[ -n "$PROJECT" ] || PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"

# The active stage is the last one by name that has a brief — NNN prefixes make
# lexicographic order the same as creation order, and a directory without a
# brief is a stage that was never actually started.
stage_dir=""
for d in "$PROJECT"/stages/*/; do
  [ -f "$d/brief.md" ] || continue
  stage_dir="$d"
done

# The brief's goal: the first "Goal" line (the template writes "- Goal: ..."),
# else the first line of real prose — headings and front matter say nothing.
goal_of() {
  local f="$1" line stripped first=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    stripped="${line#"${line%%[![:space:]]*}"}"
    case "$stripped" in [-*]' '*) stripped="${stripped#[-*] }" ;; esac
    case "$stripped" in
      Goal*|goal*) printf '%s' "$stripped"; return 0 ;;
    esac
    if [ -z "$first" ]; then
      case "$stripped" in
        ''|'#'*|'---'*|'==='*) ;;
        *) first="$stripped" ;;
      esac
    fi
  done < "$f"
  printf '%s' "$first"
}

state=""
if [ -n "$stage_dir" ]; then
  slug="$(basename "$stage_dir")"
  goal="$(goal_of "$stage_dir/brief.md" 2>/dev/null)"
  goal="${goal:0:$MAXLEN}"
  if [ -n "$goal" ]; then
    state="stage: stages/$slug — $goal"
  else
    state="stage: stages/$slug"
  fi
fi

claims=""
if [ -f "$PROJECT/BACKLOG.md" ]; then
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [ -n "$line" ] || continue
    claims="${claims}${line:0:$MAXLEN}
"
  done <<EOF
$(grep -F 'claim:' "$PROJECT/BACKLOG.md" 2>/dev/null | head -5)
EOF
fi

# The header introduces restored state; with nothing to restore it would be a
# lie, so a project without stages or backlog claims gets only the two reminders.
if [ -n "$state" ] || [ -n "$claims" ]; then
  echo 'keel: context was compacted — restored state:'
  [ -n "$state" ] && printf '%s\n' "$state"
  [ -n "$claims" ] && printf '%s' "$claims"
fi
echo 'gates: qa-browser before UI is done · verifier before a stage closes · recall before touching unfamiliar code · remember after a lesson'
echo 'skills load on use: ls .claude/skills'
exit 0
