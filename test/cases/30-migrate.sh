# Keel self-tests — 30-migrate. Sourced from test/run.sh; REPO/SK/HK/TMP and the
# helpers ok/bad/has/hasnt/section come from there.

# ── migrate sweep ───────────────────────────────────────────────────────────
section "migrate — machinery quarantined, state preserved, re-audit filed"
S="$TMP/sf"; mkdir -p "$S/skillforge" "$S/memory/lessons" "$S/.claude/skills/_user/mine" \
                      "$S/stages" "$S/.claude/hooks"
echo bundle > "$S/skillforge/x"; echo lesson > "$S/memory/lessons/keep.md"
echo mine > "$S/.claude/skills/_user/mine/SKILL.md"; : > "$S/BACKLOG.md"
echo residue > "$S/.claude/hooks/memory-residue-check.sh"
# A .gitignore whose last line has no newline: appending blind glued the last
# project pattern onto .keel-migration/ and quietly broke both.
printf 'node_modules' > "$S/.gitignore"
out="$(cd "$S" && CLAUDE_PROJECT_DIR="$S" bash "$SK/migrate/sweep.sh" 2>&1)"
has "MACHINERY" "$out" "sweep detects the skillforge bundle as machinery"
( cd "$S" && CLAUDE_PROJECT_DIR="$S" bash "$SK/migrate/sweep.sh" --apply >/dev/null 2>&1 )
[ ! -d "$S/skillforge" ] && ok || bad "machinery moved out of project root"
[ -n "$(find "$S/.keel-migration" -name x 2>/dev/null)" ] && ok || bad "machinery lands in quarantine"
[ -f "$S/memory/lessons/keep.md" ] && ok || bad "memory note preserved"
[ -f "$S/.claude/skills/_user/mine/SKILL.md" ] && ok || bad "_user skill preserved"
grep -q 'src:migrate' "$S/BACKLOG.md" && ok || bad "re-audit filed into BACKLOG.md"
grep -qxF 'node_modules' "$S/.gitignore" && grep -qxF '.keel-migration/' "$S/.gitignore" \
  && ok || bad ".gitignore last pattern not glued to .keel-migration/"

# The manifest is meant to be run, not read: each Moved item gets a restore
# command that works even though the sweep left no parent directory behind.
MAN="$(find "$S/.keel-migration" -name MANIFEST.md | head -1)"
has "## Restore" "$(cat "$MAN")" "manifest carries a Restore block"
cmd="$(grep -F 'memory-residue-check.sh' "$MAN" | grep '^mkdir -p' | head -1)"
rm -rf "$S/.claude/hooks"
( cd "$S" && eval "$cmd" ) >/dev/null 2>&1
[ -f "$S/.claude/hooks/memory-residue-check.sh" ] \
  && ok || bad "restore command works with the parent directory gone (cmd: $cmd)"
rm -f "$S/.claude/hooks/memory-residue-check.sh"

# flagged-only (a .claude.bak) is NOT machinery
F="$TMP/flag"; mkdir -p "$F/memory" "$F/.claude.bak.20260101000000"
out="$(cd "$F" && CLAUDE_PROJECT_DIR="$F" bash "$SK/migrate/sweep.sh" 2>&1)"
hasnt "MACHINERY" "$out" "a lone .claude.bak is flagged, not machinery"

# A backup holding a VERSION file is one keel's own installer made — saying so
# stops the owner opening it to look for SkillForge state that was never there.
mkdir -p "$F/.claude.bak.20260102000000"
echo "1.7.0" > "$F/.claude.bak.20260102000000/VERSION"
out="$(cd "$F" && CLAUDE_PROJECT_DIR="$F" bash "$SK/migrate/sweep.sh" 2>&1)"
has "keel's own backup left by install.sh" "$out" "backup with VERSION named as keel's own"
case "$out" in
  *".claude.bak.20260101000000  — previous kernel backup"*) ok ;;
  *) bad "a backup without VERSION keeps the previous-kernel wording" ;;
esac
