# Keel self-tests — 49-worktree. Sourced from test/run.sh; REPO/SK/HK/TMP and
# the helpers ok/bad/has/hasnt/section come from there.

# ── every hook still works when cwd is not the main checkout ─────────────────
# Measured facts (Claude Code 2.1.87, 2026-09-12):
#   --worktree launch: CLAUDE_PROJECT_DIR = the worktree;
#   entered later: stays at the main checkout, payload cwd follows (docs);
#   the worktree's own .claude/settings.json is the one read;
#   .worktreeinclude did carry .secrets.env into the worktree.
# So the hooks run twice below: once with CLAUDE_PROJECT_DIR on the main
# checkout (entered later) and once with it on the worktree (--worktree launch),
# with cwd on the worktree both times. Each hook is invoked through the copy the
# settings.json of that CLAUDE_PROJECT_DIR points at, which is how the harness
# resolves "$CLAUDE_PROJECT_DIR/.claude/hooks/<hook>".
section "worktrees — the hooks hold when cwd differs from CLAUDE_PROJECT_DIR"

WTM="$TMP/wtree/main"
WTW="$WTM/.claude/worktrees/wt1"
mkdir -p "$WTM/.claude" "$WTM/stages/001-main"
cp -R "$REPO/bundle/.claude/." "$WTM/.claude/" 2>/dev/null
mkdir -p "$WTW/.claude" "$WTW/stages/002-wt"
cp -R "$REPO/bundle/.claude/." "$WTW/.claude/" 2>/dev/null
printf 'API_TOKEN=SUPERSECRETVALUE123456\n' > "$WTM/.secrets.env"
printf 'API_TOKEN=SUPERSECRETVALUE123456\n' > "$WTW/.secrets.env"
printf '# Stage 001\n\n- Goal: the main checkout goal\n' > "$WTM/stages/001-main/brief.md"
printf '# Stage 002\n\n- Goal: the worktree goal\n' > "$WTW/stages/002-wt/brief.md"
printf -- '- [ ] P1 | web | worktree item | src:qa | claim:0912-wt\n' > "$WTW/BACKLOG.md"
[ -f "$WTM/.claude/hooks/leak-guard.sh" ] && ok || bad "the worktree fixture carries the bundle's hooks"

for wt_case in entered launched; do
  case "$wt_case" in
    entered)  wt_pd="$WTM" ;;   # session entered the worktree later
    launched) wt_pd="$WTW" ;;   # session launched with --worktree
  esac
  wt_hooks="$wt_pd/.claude/hooks"
  wt_hook() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$wt_pd" KEEL_LOOP_STATE_DIR="$TMP/wt-loop" bash "$wt_hooks/$1" 2>&1; }

  # leak-guard: a secret written into a worktree file is still a leak.
  wt_out="$(wt_hook leak-guard.sh "$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/notes.md","content":"token: SUPERSECRETVALUE123456"}}' "$WTW" "$WTW")")"
  has '"permissionDecision":"deny"' "$wt_out" "leak-guard denies the secret into the worktree ($wt_case)"
  has 'secret API_TOKEN' "$wt_out" "leak-guard names the key ($wt_case)"

  # forkbomb-guard: a dev server is a dev server on any branch.
  wt_out="$(wt_hook forkbomb-guard.sh "$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"npm run dev"}}' "$WTW")")"
  has '"permissionDecision":"deny"' "$wt_out" "forkbomb-guard denies npm run dev in the worktree ($wt_case)"

  # verdict-guard: the path is the whole scope, so a worktree report is covered.
  wt_out="$(wt_hook verdict-guard.sh "$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/stages/002-wt/report.md","content":"Verifier: 6 pass / 0 fail"}}' "$WTW" "$WTW")")"
  has '"permissionDecision":"deny"' "$wt_out" "verdict-guard denies a hand-written verdict in the worktree ($wt_case)"

  # recompact: the stage restored is the worktree's, in both launch shapes.
  wt_out="$(wt_hook recompact.sh "$(printf '{"hook_event_name":"SessionStart","source":"compact","cwd":"%s"}' "$WTW")")"
  has 'stages/002-wt' "$wt_out" "recompact restores the worktree stage ($wt_case)"
  has 'the worktree goal' "$wt_out" "recompact quotes the worktree brief ($wt_case)"
  hasnt '001-main' "$wt_out" "recompact leaves the main checkout's stage alone ($wt_case)"

  # update-check: silent when switched off, whatever the directory layout is.
  wt_out="$(KEEL_NO_UPDATE_CHECK=1 CLAUDE_PROJECT_DIR="$wt_pd" bash "$wt_hooks/update-check.sh" </dev/null 2>&1)"; wt_code=$?
  [ -z "$wt_out" ] && ok || bad "update-check stays silent when disabled ($wt_case, got: $wt_out)"
  [ "$wt_code" -eq 0 ] && ok || bad "update-check exits 0 when disabled ($wt_case, got: $wt_code)"

  # The two advisory hooks: a neutral payload gets a neutral answer.
  wt_out="$(wt_hook loop-guard.sh "$(printf '{"session_id":"wt-%s","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"notes.md"}}' "$wt_case" "$WTW")")"
  [ "$wt_out" = "{}" ] && ok || bad "loop-guard is quiet on a neutral payload ($wt_case, got: $wt_out)"
  wt_out="$(wt_hook index-guard.sh "$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"notes.md"}}' "$WTW")")"
  [ "$wt_out" = "{}" ] && ok || bad "index-guard is quiet on a neutral payload ($wt_case, got: $wt_out)"
done
unset -f wt_hook

# ── a worktree with its own secrets is scanned against its own file ──────────
# .worktreeinclude copies the main file, so the two normally agree; a worktree
# that holds a value the main checkout does not must still be guarded when
# CLAUDE_PROJECT_DIR names the main checkout (entered later). Both files count.
section "worktrees — leak-guard reads the worktree's own .secrets.env too"
printf 'WT_ONLY=WORKTREEONLYVALUE9876\n' > "$WTW/.secrets.env"
wt_own="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/notes.md","content":"x=WORKTREEONLYVALUE9876"}}' "$WTW" "$WTW" \
  | CLAUDE_PROJECT_DIR="$WTM" bash "$WTM/.claude/hooks/leak-guard.sh" 2>/dev/null)"
has '"permissionDecision":"deny"' "$wt_own" "a value only the worktree's .secrets.env knows is denied (entered later)"
has 'secret WT_ONLY' "$wt_own" "the worktree's key is named"
wt_main="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/notes.md","content":"x=SUPERSECRETVALUE123456"}}' "$WTW" "$WTW" \
  | CLAUDE_PROJECT_DIR="$WTM" bash "$WTM/.claude/hooks/leak-guard.sh" 2>/dev/null)"
has '"permissionDecision":"deny"' "$wt_main" "the main checkout's value is still denied alongside"
wt_none="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/notes.md","content":"nothing secret here"}}' "$WTW" "$WTW" \
  | CLAUDE_PROJECT_DIR="$WTM" bash "$WTM/.claude/hooks/leak-guard.sh" 2>/dev/null)"
[ "$wt_none" = "{}" ] && ok || bad "a clean write in the worktree passes (got: $wt_none)"
