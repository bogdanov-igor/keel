#!/usr/bin/env bash
# PostToolUse index guard: after a write to memory/MEMORY.md, say so when the
# index has outgrown "one line per note, never a body" (the contract's memory
# rule). Advisory — the write already happened, so this hook only speaks.
# Matcher (settings.json): Write|Edit. Full hook JSON on stdin.
#
# Why: the predecessor system's index grew bodies into itself one convenient
# paragraph at a time, until reading the index cost more than reading the notes,
# so it stopped being read — and memory that is not read is not memory. Nothing
# announces that moment; the file just gets longer. These two numbers are where
# the slide starts, and they are cheap to check on every write.
#
# What is scanned: the file on disk, not the payload. PostToolUse fires after
# the write, an Edit only carries its fragment, and the question ("how big is
# the index now") is about the whole file either way.
#
# Scope: a file_path ending in memory/MEMORY.md, nothing else — lessons, notes
# and code are none of this hook's business. A relative path is resolved against
# the payload's `cwd` first (a worktree session's cwd is not the main checkout),
# then CLAUDE_PROJECT_DIR, then PWD. jq reads the payload, python3 when jq is
# missing; with neither, or with no file_path, the hook stays silent.
# Never fails, never blocks: exit 0 on every path.
set -uo pipefail
MAXLINES=250   # an index longer than this is a document
MAXCHARS=300   # a line longer than this is a body

quiet() { echo '{}'; exit 0; }

payload="$(cat)"
[ -n "$payload" ] || quiet

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -z "$file_path" ] && file_path="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tool_input",{}).get("file_path","") or "")' 2>/dev/null || true)"
[ -z "$file_path" ] && quiet

case "$file_path" in
  memory/MEMORY.md|*/memory/MEMORY.md) ;;
  *) quiet ;;
esac

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$cwd" ] && cwd="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("cwd","") or "")' 2>/dev/null || true)"

target=""
case "$file_path" in
  /*) [ -f "$file_path" ] && target="$file_path" ;;
  *)
    for base in "$cwd" "${CLAUDE_PROJECT_DIR:-}" "$PWD"; do
      [ -n "$base" ] || continue
      [ -f "$base/$file_path" ] || continue
      target="$base/$file_path"
      break
    done ;;
esac
[ -n "$target" ] || quiet    # a path that resolves nowhere is not a verdict

# Counted in bash so the numbers are characters, not bytes: a Russian index line
# is two bytes per character and would trip a byte limit at half its real length.
lines=0; longest=0; line=""
while IFS= read -r line || [ -n "$line" ]; do
  lines=$((lines + 1))
  line="${line%$'\r'}"
  n=${#line}
  [ "$n" -gt "$longest" ] && longest="$n"
done < "$target"

msg=""
[ "$lines" -gt "$MAXLINES" ] && msg="has $lines lines (limit $MAXLINES)"
if [ "$longest" -gt "$MAXCHARS" ]; then
  if [ -n "$msg" ]; then
    msg="$msg and a line of $longest chars (limit $MAXCHARS)"
  else
    msg="has a line of $longest chars (limit $MAXCHARS)"
  fi
fi
[ -n "$msg" ] || quiet

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"keel index-guard: memory/MEMORY.md %s — the index is one short line per note; move the detail into the note and run skill memory-consolidation."}}\n' "$msg"
exit 0
