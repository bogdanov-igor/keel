# Keel self-tests — 47-recompact. Sourced from test/run.sh; REPO/SK/HK/TMP and
# the helpers ok/bad/has/hasnt/section come from there.

# ── recompact: the state compaction dropped, within a hard line budget ───────
section "recompact — stage, claims and gates come back after compaction"
RC="$TMP/rc"; mkdir -p "$RC/stages/001-old" "$RC/stages/003-x"
printf '# Stage 001\n\n- Goal: the stage that already closed\n' > "$RC/stages/001-old/brief.md"
printf '# Stage 003\n\n- Goal: ship the widget rail end to end\n' > "$RC/stages/003-x/brief.md"
{
  printf -- '- [ ] P1 | web | rail overflows on mobile | src:qa | claim:0911-rail\n'
  printf -- '- [ ] P2 | api | tidy the handlers | src:audit | claim:0911-api\n'
  printf -- '- [ ] P3 | docs | rewrite the readme | src:owner\n'
} > "$RC/BACKLOG.md"

rc_out="$(CLAUDE_PROJECT_DIR="$RC" bash "$HK/recompact.sh" </dev/null 2>&1)"; rc_code=$?
[ "$rc_code" -eq 0 ] && ok || bad "recompact exits 0 (got: $rc_code)"
has "stage: stages/003-x" "$rc_out" "the last stage with a brief is the active one"
has "ship the widget rail end to end" "$rc_out" "the brief's Goal line is quoted"
hasnt "001-old" "$rc_out" "an older stage is not restored"
has "claim:0911-rail" "$rc_out" "a claimed backlog item comes back"
has "claim:0911-api" "$rc_out" "the second claim comes back too"
hasnt "rewrite the readme" "$rc_out" "an unclaimed item is not restored"
has "gates:" "$rc_out" "the gates reminder is printed"
has "ls .claude/skills" "$rc_out" "the skill listing pointer is printed"
rc_lines="$(printf '%s\n' "$rc_out" | wc -l | tr -d ' ')"
[ "$rc_lines" -le 12 ] && ok || bad "output stays within 12 lines (got: $rc_lines)"

# An empty project has no state to restore: only the two standing reminders.
RE="$TMP/rc-empty"; mkdir -p "$RE"
re_out="$(CLAUDE_PROJECT_DIR="$RE" bash "$HK/recompact.sh" </dev/null 2>&1)"; re_code=$?
[ "$re_code" -eq 0 ] && ok || bad "recompact on an empty project exits 0 (got: $re_code)"
re_lines="$(printf '%s\n' "$re_out" | wc -l | tr -d ' ')"
[ "$re_lines" -eq 2 ] && ok || bad "empty project prints exactly the two fixed lines (got: $re_lines)"
hasnt "stage:" "$re_out" "no stage line without stages/"

# ── the branch the session is on wins over the environment ──────────────────
# Measured on Claude Code 2.1.87: `claude --worktree` sets CLAUDE_PROJECT_DIR to
# the worktree, while a session that entered a worktree later keeps it on the
# main checkout and only the payload's cwd follows. After a compaction the stage
# and the claims that matter are the ones on the branch being worked.
RW="$TMP/rc-wt"; mkdir -p "$RW/main/stages/001-main" "$RW/wt/.claude" "$RW/wt/stages/002-wt"
printf '# Stage 001\n\n- Goal: the main checkout goal\n' > "$RW/main/stages/001-main/brief.md"
printf '# Stage 002\n\n- Goal: worktree goal\n' > "$RW/wt/stages/002-wt/brief.md"
printf -- '- [ ] P1 | web | worktree item | src:qa | claim:0912-wt\n' > "$RW/wt/BACKLOG.md"
printf -- '- [ ] P1 | api | main item | src:qa | claim:0912-main\n' > "$RW/main/BACKLOG.md"

rw_out="$(printf '{"hook_event_name":"SessionStart","source":"compact","cwd":"%s"}' "$RW/wt" \
  | CLAUDE_PROJECT_DIR="$RW/main" bash "$HK/recompact.sh" 2>&1)"; rw_code=$?
[ "$rw_code" -eq 0 ] && ok || bad "recompact with a payload exits 0 (got: $rw_code)"
has "stages/002-wt" "$rw_out" "the payload cwd decides the project, not the environment"
has "worktree goal" "$rw_out" "the worktree's own brief is the one quoted"
hasnt "001-main" "$rw_out" "the main checkout's stage is not restored into a worktree session"
has "claim:0912-wt" "$rw_out" "the claims come from the worktree's backlog"

# A cwd deeper than the project root still resolves: the walk stops at the
# nearest ancestor holding .claude/ or BACKLOG.md.
mkdir -p "$RW/wt/src/deep"
rw_out="$(printf '{"cwd":"%s"}' "$RW/wt/src/deep" | CLAUDE_PROJECT_DIR="$RW/main" bash "$HK/recompact.sh" 2>&1)"
has "stages/002-wt" "$rw_out" "a cwd below the project root walks up to it"

# No payload, or one the hook cannot read: the old env-based behaviour holds.
rw_out="$(CLAUDE_PROJECT_DIR="$RC" bash "$HK/recompact.sh" </dev/null 2>&1)"
has "stages/003-x" "$rw_out" "empty stdin keeps the CLAUDE_PROJECT_DIR behaviour"
rw_out="$(printf 'not json at all' | CLAUDE_PROJECT_DIR="$RC" bash "$HK/recompact.sh" 2>&1)"
has "stages/003-x" "$rw_out" "an unreadable payload falls back to CLAUDE_PROJECT_DIR"
rw_out="$(printf '{"cwd":"/nonexistent/path/nowhere"}' | CLAUDE_PROJECT_DIR="$RC" bash "$HK/recompact.sh" 2>&1)"
has "stages/003-x" "$rw_out" "a cwd that is not a project falls back to CLAUDE_PROJECT_DIR"
