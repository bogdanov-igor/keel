# Keel self-tests — 80-install. Sourced from test/run.sh; REPO/SK/HK/TMP and the
# helpers ok/bad/has/hasnt/section come from there.
#
# install.sh is run as often by Claude as by a human and is the one script that
# writes into somebody's real project, so every case here is a way it has already
# destroyed, buried or silently dropped something.

section "install — fresh install"
I1="$TMP/i1"; mkdir -p "$I1"
out="$(bash "$REPO/install.sh" "$I1" 2>&1)"
has "self-check — OK" "$out" "fresh install passes its own self-check"
has "no previous-system residue" "$out" "clean project reports no residue"
has "integrations" "$out" "integrations block is printed"
has "serena LSP navigation" "$out" "integrations name what each tool buys keel"
has "nothing was installed or signed in" "$out" "integrations block says it installed nothing"
has "/integrations" "$out" "next: points at the /integrations command"
[ "$(cat "$I1/.claude/VERSION")" = "$(tr -d '[:space:]' < "$REPO/VERSION")" ] \
  && ok || bad "VERSION stamped for the update-check hook"
[ -f "$I1/.worktreeinclude" ] && grep -qxF '.secrets.env' "$I1/.worktreeinclude" \
  && ok || bad ".worktreeinclude seeded with .secrets.env"
grep -qxF '.claude/worktrees/' "$I1/.gitignore" && ok || bad ".claude/worktrees/ is gitignored"

# ── reinstall keeps the owner's own Claude Code setup and project state ─────
section "install — reinstall carries the owner's setup over"
mkdir -p "$I1/.claude/commands" "$I1/.claude/rules" "$I1/.claude/output-styles" \
         "$I1/.claude/skills/my-skill"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$I1/.claude/settings.local.json"
echo "command"  > "$I1/.claude/commands/my-cmd.md"
echo "rule"     > "$I1/.claude/rules/my-rule.md"
echo "style"    > "$I1/.claude/output-styles/x.md"
echo "project"  > "$I1/.claude/skills/my-skill/SKILL.md"
echo "custom"   > "$I1/.claude/agents/my-agent.md"
echo "- [ ] P2 | own | keep me | ev:x | src:owner" >> "$I1/BACKLOG.md"
out="$(bash "$REPO/install.sh" "$I1" 2>&1)"
has "carried over from the previous .claude" "$out" "installer names what it carried over"
has "preserved project skills" "$out" "installer names the project skills it kept"
[ -f "$I1/.claude/settings.local.json" ] && ok || bad "settings.local.json (permissions) survived"
[ -f "$I1/.claude/commands/my-cmd.md" ] && [ -f "$I1/.claude/rules/my-rule.md" ] \
  && ok || bad "commands/ and rules/ survived"
[ -f "$I1/.claude/output-styles/x.md" ] && ok || bad "own output-style survived"
[ -f "$I1/.claude/agents/my-agent.md" ] && ok || bad "own agent survived"
[ -f "$I1/.claude/skills/my-skill/SKILL.md" ] && ok || bad "project skill survived"
grep -q 'src:owner' "$I1/BACKLOG.md" && ok || bad "BACKLOG line survived"
has "self-check — OK" "$out" "reinstall passes its own self-check"

# ── .gitignore without a trailing newline is not glued ──────────────────────
section "install — .gitignore edges"
I5="$TMP/i5"; mkdir -p "$I5"; printf 'node_modules' > "$I5/.gitignore"
bash "$REPO/install.sh" "$I5" >/dev/null 2>&1
grep -qxF 'node_modules' "$I5/.gitignore" && grep -qxF '.secrets.env' "$I5/.gitignore" \
  && ok || bad "last .gitignore pattern not glued onto .secrets.env"

# ── two installs in the same second: backups side by side, not nested ───────
section "install — two runs in one second"
FB="$TMP/fakebin"; mkdir -p "$FB"
printf '#!/bin/sh\necho 20260101000000\n' > "$FB/date"; chmod +x "$FB/date"
I6="$TMP/i6"; mkdir -p "$I6/.claude/skills/proj-skill"
echo "project" > "$I6/.claude/skills/proj-skill/SKILL.md"
PATH="$FB:$PATH" bash "$REPO/install.sh" "$I6" >/dev/null 2>&1
PATH="$FB:$PATH" bash "$REPO/install.sh" "$I6" >/dev/null 2>&1
cnt="$(ls -d "$I6"/.claude.bak.* 2>/dev/null | wc -l | tr -d ' ')"
[ "$cnt" = "2" ] && ok || bad "two backups side by side (found: $cnt)"
[ ! -e "$I6/.claude.bak.20260101000000/.claude.bak.20260101000000" ] \
  && ok || bad "a backup did not end up nested inside the previous one"
[ -f "$I6/.claude/skills/proj-skill/SKILL.md" ] \
  && ok || bad "project skill survived both runs"

# ── .mcp.json is filtered to servers this machine can actually launch ───────
# A server whose launcher is missing is worse than no server: Claude Code retries
# it every session start and reports a failure the owner did not cause.
section "install — .mcp.json seeded only with runnable servers"
I7="$TMP/i7"; mkdir -p "$I7"
PATH="/usr/bin:/bin" bash "$REPO/install.sh" "$I7" >/dev/null 2>&1
grep -q '"serena"' "$I7/.mcp.json" 2>/dev/null && bad "no serena entry when uvx is absent" || ok
UVX="$TMP/uvxbin"; mkdir -p "$UVX"
printf '#!/bin/sh\nexit 0\n' > "$UVX/uvx"; chmod +x "$UVX/uvx"
I7b="$TMP/i7b"; mkdir -p "$I7b"
PATH="$UVX:/usr/bin:/bin" bash "$REPO/install.sh" "$I7b" >/dev/null 2>&1
grep -q '"serena"' "$I7b/.mcp.json" 2>/dev/null && ok || bad "serena seeded when uvx is on PATH"

# ── VS Code recommendations: seeded once, never over a project's own ────────
# memory/ is a [[wikilink]] graph. Without Foam it reads in the editor as broken
# markdown, and a graph nobody can see is a graph nobody maintains; the mermaid
# preview is the same story for the diagrams the guides ship. A project that
# already has a recommendations file made that call itself and is left alone —
# silently, because a non-event does not deserve a line in the report.
section "install — .vscode/extensions.json"
I9="$TMP/i9"; mkdir -p "$I9"
out="$(bash "$REPO/install.sh" "$I9" 2>&1)"
has ".vscode/extensions.json seeded" "$out" "the installer says it seeded the recommendations"
python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("recommendations") == ["foam.foam-vscode", "bierner.markdown-mermaid"] else 1)' \
  "$I9/.vscode/extensions.json" 2>/dev/null \
  && ok || bad "extensions.json is valid JSON recommending foam and the mermaid preview"

I10="$TMP/i10"; mkdir -p "$I10/.vscode"
printf '%s\n' '{"recommendations":["ms-python.python"]}' > "$I10/.vscode/extensions.json"
out="$(bash "$REPO/install.sh" "$I10" 2>&1)"
if grep -q 'ms-python.python' "$I10/.vscode/extensions.json" && ! grep -q 'foam' "$I10/.vscode/extensions.json"
then ok; else bad "a project's own extensions.json is left exactly as it was"; fi
hasnt ".vscode/extensions.json seeded" "$out" "nothing is reported about a file that was left alone"

# ── an existing .mcp.json is kept, and what it costs is said out loud ───────
# The installer does not touch someone's MCP config. It does count it: every
# configured server ships its whole tool schema into every session AND into
# every subagent that session spawns, which is a standing context bill nobody
# chose to pay and nothing else in the install reports.
section "install — existing .mcp.json is counted, never rewritten"
I11="$TMP/i11"; mkdir -p "$I11"
printf '%s\n' '{"mcpServers":{"a":{"command":"x"},"b":{"command":"y"},"serena":{"command":"uvx"}}}' \
  > "$I11/.mcp.json"
out="$(bash "$REPO/install.sh" "$I11" 2>&1)"
has "3 MCP servers configured" "$out" "the installer counts the servers already configured"
has "every session and every subagent" "$out" "the warning names where the cost lands"
grep -q '"a"' "$I11/.mcp.json" && ok || bad "the owner's .mcp.json is not rewritten"
hasnt "no serena entry" "$out" "no serena nag when serena is already configured"

# A config that does not parse is somebody else's problem to fix, not the
# installer's to guess at: no count, no warning, and the install still lands.
I12="$TMP/i12"; mkdir -p "$I12"; printf 'not json at all\n' > "$I12/.mcp.json"
out="$(bash "$REPO/install.sh" "$I12" 2>&1)"
hasnt "MCP servers configured" "$out" "an unparsable .mcp.json produces no count"
has "self-check — OK" "$out" "an unparsable .mcp.json does not fail the install"

# ── a failed self-check rolls the install back ──────────────────────────────
# A half-installed kernel sitting where a working one used to be is the worst
# state of all, and the owner is not required to remember the backup's name.
section "install — failed self-check rolls back"
RB="$TMP/badrepo"; mkdir -p "$RB"
cp "$REPO/VERSION" "$REPO/install.sh" "$RB/"
cp -R "$REPO/bundle" "$RB/bundle"
rm -f "$RB/bundle/.claude/CLAUDE.md"
I8="$TMP/i8"; mkdir -p "$I8/.claude"; echo "previous kernel" > "$I8/.claude/marker"
out="$(bash "$RB/install.sh" "$I8" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && ok || bad "a failed self-check exits non-zero"
has "SELF-CHECK FAILED" "$out" "the installer says the self-check failed"
has "rolled back" "$out" "the installer says it rolled back"
[ -f "$I8/.claude/marker" ] && ok || bad "the previous .claude is back in place"
ls -d "$I8"/.claude.bak.* >/dev/null 2>&1 && bad "no backup left behind as litter" || ok
