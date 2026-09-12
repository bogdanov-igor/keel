# Keel self-tests — 43-index-guard. Sourced from test/run.sh; REPO/SK/HK/TMP and
# the helpers ok/bad/has/hasnt/section come from there.

# ── index-guard: the memory index stays an index ─────────────────────────────
# The failure this encodes is slow: bodies creep into MEMORY.md one convenient
# paragraph at a time until the index costs more to read than the notes it
# points at, and then nobody reads it. The hook is advisory — it fires after the
# write and only says a number.
section "index-guard — MEMORY.md over the limits gets an advisory"
IDX="$TMP/idx"; mkdir -p "$IDX/memory/lessons"
idx_run() { printf '%s' "$1" | bash "$HK/index-guard.sh" 2>&1; }
idx_pay() { printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' "$IDX" "$1"; }

# A healthy index: ten one-liners, nothing to say.
{ idx_i=0; while [ "$idx_i" -lt 10 ]; do idx_i=$((idx_i + 1))
    printf -- '- [note %s](lessons/%s.md) — one line about one thing\n' "$idx_i" "$idx_i"
  done; } > "$IDX/memory/MEMORY.md"
idx_out="$(idx_run "$(idx_pay 'memory/MEMORY.md')")"
[ "$idx_out" = "{}" ] && ok || bad "a healthy index is silent (got: $idx_out)"

# Too many lines: the index has become a document.
{ idx_i=0; while [ "$idx_i" -lt 251 ]; do idx_i=$((idx_i + 1)); printf -- '- note %s\n' "$idx_i"; done; } > "$IDX/memory/MEMORY.md"
idx_out="$(idx_run "$(idx_pay 'memory/MEMORY.md')")"
has '251 lines' "$idx_out" "an over-long index is counted and named"
has 'memory-consolidation' "$idx_out" "the advisory names the skill that fixes it"
hasnt 'chars' "$idx_out" "only the limit that was exceeded is mentioned"
printf '%s' "$idx_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["hookSpecificOutput"]["hookEventName"]=="PostToolUse" and d["hookSpecificOutput"]["additionalContext"] else 1)' \
  && ok || bad "the advisory is valid PostToolUse JSON (got: $idx_out)"

# One body-length line: nine short lines and a 350-character one.
{ idx_i=0; while [ "$idx_i" -lt 9 ]; do idx_i=$((idx_i + 1)); printf -- '- note %s\n' "$idx_i"; done
  printf '%350s\n' '' | tr ' ' 'x'; } > "$IDX/memory/MEMORY.md"
idx_out="$(idx_run "$(idx_pay 'memory/MEMORY.md')")"
has '350 chars' "$idx_out" "a body-length line is measured"
hasnt 'lines (limit' "$idx_out" "a short index is not accused of being long"

# An absolute file_path resolves without a cwd; a relative one needs the payload
# cwd, which in a worktree session is not the main checkout.
idx_out="$(idx_run "$(printf '{"tool_name":"Edit","cwd":"/nowhere","tool_input":{"file_path":"%s/memory/MEMORY.md"}}' "$IDX")")"
has '350 chars' "$idx_out" "an absolute path is read as given"

# Characters, not bytes: a Cyrillic index line is two bytes per character and a
# byte limit would accuse it at half its real length.
python3 -c 'import io,sys; io.open(sys.argv[1],"w",encoding="utf-8").write("- "+"я"*200+"\n")' "$IDX/memory/MEMORY.md"
idx_out="$(idx_run "$(idx_pay 'memory/MEMORY.md')")"
[ "$idx_out" = "{}" ] && ok || bad "a 202-character Cyrillic line is under the limit (got: $idx_out)"

# Everything that is not the index is none of the hook's business.
printf -- '- a lesson body, as long as it likes\n' > "$IDX/memory/lessons/x.md"
idx_out="$(idx_run "$(idx_pay 'memory/lessons/x.md')")"
[ "$idx_out" = "{}" ] && ok || bad "a write to a note is ignored (got: $idx_out)"

idx_out="$(idx_run '{"tool_name":"Write","cwd":"/nowhere","tool_input":{"file_path":"memory/MEMORY.md"}}')"
[ "$idx_out" = "{}" ] && ok || bad "a path that resolves nowhere is silent (got: $idx_out)"

idx_out="$(printf 'not json at all' | bash "$HK/index-guard.sh" 2>&1)"; idx_code=$?
[ "$idx_out" = "{}" ] && ok || bad "garbage on stdin answers {} (got: $idx_out)"
[ "$idx_code" -eq 0 ] && ok || bad "garbage on stdin still exits 0 (got: $idx_code)"

# ── both limits at once, and a look-alike path ───────────────────────────────
section "index-guard — both limits in one message; a look-alike path is ignored"
{ idx_i=0; while [ "$idx_i" -lt 251 ]; do idx_i=$((idx_i + 1)); printf -- '- note %s\n' "$idx_i"; done
  printf -- '- %s\n' "$(printf 'x%.0s' $(seq 1 320))"; } > "$IDX/memory/MEMORY.md"
idx_out="$(idx_run "$(idx_pay 'memory/MEMORY.md')")"
has '252 lines' "$idx_out" "both limits: the line count is named"
has '322 chars' "$idx_out" "both limits: the longest line is named in the same message"
printf '%s' "$idx_out" | python3 -c 'import json,sys; json.load(sys.stdin)' && ok || bad "both-limits answer is valid JSON (got: $idx_out)"
mkdir -p "$IDX/notmymemory"; cp "$IDX/memory/MEMORY.md" "$IDX/notmymemory/MEMORY.md"
idx_out="$(idx_run "$(idx_pay 'notmymemory/MEMORY.md')")"
[ "$idx_out" = "{}" ] && ok || bad "a path that merely ends in memory/MEMORY.md is not the index (got: $idx_out)"
