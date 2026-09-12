#!/usr/bin/env bash
# Keel installer: copy the kernel into a project.
# Usage: bash install.sh [/path/to/project]     (no argument = install here)
#
# Run as often by Claude ("install keel from the archive in this folder") as by
# a human, so it never prompts, never asks a question, and says out loud every
# thing it moved, carried over or skipped.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd -P)"
# No argument = install into the current directory: the "unpack the archive
# inside your project, run keel/install.sh" flow. An explicit path still works.
DEST="${1:-$PWD}"
[ -d "$DEST" ] || { echo "keel: no such directory: $DEST" >&2; exit 1; }
DEST="$(cd "$DEST" && pwd -P)"
if [ "$DEST" = "$SRC" ]; then
  echo "keel: this is the keel folder itself — run from the project root:" >&2
  echo "      cd /path/to/project && bash keel/install.sh" >&2
  exit 1
fi
VER="$(tr -d '[:space:]' < "$SRC/VERSION")"

# Colour only for a human at a terminal: NO_COLOR and pipes/CI get plain text.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  B=$'\033[1m'; D=$'\033[2m'; C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'
else
  B=''; D=''; C=''; G=''; Y=''; R=''
fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$R" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$R" "$*"; }

printf '\n'
printf '%s      ██╗  ██╗███████╗███████╗██╗%s\n'      "$C" "$R"
printf '%s      ██║ ██╔╝██╔════╝██╔════╝██║%s\n'      "$C" "$R"
printf '%s      █████╔╝ █████╗  █████╗  ██║%s\n'      "$C" "$R"
printf '%s      ██╔═██╗ ██╔══╝  ██╔══╝  ██║%s\n'      "$C" "$R"
printf '%s      ██║  ██╗███████╗███████╗███████╗%s\n' "$C" "$R"
printf '%s      ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝%s\n' "$C" "$R"
printf '\n'
printf '      %sv%s%s  %sminimal load-bearing kernel for Claude Code%s\n' "$B" "$VER" "$R" "$D" "$R"
printf '      %sthe part of the ship you don'"'"'t see: it holds everything and adds nothing%s\n' "$D" "$R"
printf '\n'
printf '      %s→ %s%s\n' "$D" "$DEST" "$R"
printf '\n'

# .claude — always a real directory, never a symlink (symlinks break
# per-project memory and hook path resolution).
#
# The backup name must be unique, not merely timestamped: two installs in the
# same second made `mv` drop the second backup INSIDE the first, burying the
# real previous .claude two levels below the path the message named.
if [ -e "$DEST/.claude" ] || [ -L "$DEST/.claude" ]; then
  BAKBASE="$DEST/.claude.bak.$(date +%Y%m%d%H%M%S)"
  BAK="$BAKBASE"; bn=2
  while [ -e "$BAK" ]; do BAK="$BAKBASE-$bn"; bn=$((bn+1)); done
  mv "$DEST/.claude" "$BAK"
  ok "previous .claude → ${BAK##*/}"
fi
cp -R "$SRC/bundle/.claude" "$DEST/.claude"
# Every shipped script, not a hand-maintained list — a new skill script must not
# depend on someone remembering to add it here.
find "$DEST/.claude" -name '*.sh' -exec chmod +x {} +
# The update-check hook compares this against the latest upstream release.
printf '%s\n' "$VER" > "$DEST/.claude/VERSION"
# All three counted from the tree that was just installed, never from a constant
# in this script: a stale "2 agents, 3 hooks" is a lie the owner cannot spot.
# Hooks are the `"command":` keys of settings.json — the harness's own unit.
# `|| true`: pipefail turns "grep found nothing" into a failed assignment and,
# under set -e, into a dead installer — the count is the answer, not the status.
n_skills="$(ls "$DEST/.claude/skills" 2>/dev/null | wc -l | tr -d ' ' || true)"
# What the kernel being installed actually ships, read from the source bundle.
# A literal floor here was a second inventory of the same thing: it said 37
# while the bundle shipped 40, so it stopped meaning anything the moment a
# skill was added — and a half-copied bundle would still have walked past it.
n_skills_src="$(ls "$SRC/bundle/.claude/skills" 2>/dev/null | wc -l | tr -d ' ' || true)"
n_agents="$(ls "$DEST/.claude/agents"/*.md 2>/dev/null | wc -l | tr -d ' ' || true)"
n_hooks="$(grep -o '"command"[[:space:]]*:' "$DEST/.claude/settings.json" 2>/dev/null | wc -l | tr -d ' ' || true)"
ok "kernel installed ($n_skills skills, $n_agents agents, $n_hooks hooks)"

# Project-owned skills survive kernel (re)install: any skill directory the
# kernel does not ship is carried over from the previous .claude — including
# ones nested under the legacy SkillForge skills/_user/. When the previous
# install was a SkillForge kernel (marker: _protocol.md), only _user/ skills
# are project-owned; its flat kernel skills stay buried in the backup.
restored=""
preserve_skill() {
  local d="$1" name
  [ -d "$d" ] || return 0
  name="$(basename "$d")"
  [ "$name" = "_user" ] && return 0
  if [ ! -d "$DEST/.claude/skills/$name" ]; then
    cp -R "$d" "$DEST/.claude/skills/$name"
    restored="$restored $name"
  fi
}
if [ -n "${BAK:-}" ] && [ -d "$BAK/skills" ]; then
  if [ -f "$BAK/_protocol.md" ]; then
    for d in "$BAK/skills/_user"/*/; do preserve_skill "$d"; done
  else
    for d in "$BAK/skills"/*/ "$BAK/skills/_user"/*/; do preserve_skill "$d"; done
  fi
  [ -n "$restored" ] && ok "preserved project skills:$restored"
fi

# The owner's own Claude Code setup survives a reinstall too: permissions
# (settings.local.json), slash commands, rules, output styles, personal agents.
# The kernel ships none of those paths, so they are carried over file by file —
# and only where the kernel has nothing at that path, so a kernel file is never
# shadowed by a stale copy of itself.
carried=""
carry_file() {
  local rel="$1"
  [ -f "$BAK/$rel" ] || return 0
  [ -e "$DEST/.claude/$rel" ] && return 0
  mkdir -p "$(dirname "$DEST/.claude/$rel")"
  cp "$BAK/$rel" "$DEST/.claude/$rel"
  carried="$carried $rel"
  return 0
}
carry_tree() {
  local rel="$1" f sub n=0
  [ -d "$BAK/$rel" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sub="${f#$BAK/}"
    [ -e "$DEST/.claude/$sub" ] && continue
    mkdir -p "$(dirname "$DEST/.claude/$sub")"
    cp "$f" "$DEST/.claude/$sub"
    n=$((n+1))
  done <<EOF
$(find "$BAK/$rel" -type f 2>/dev/null)
EOF
  [ "$n" -gt 0 ] && carried="$carried $rel/"
  return 0
}
if [ -n "${BAK:-}" ]; then
  carry_file "settings.local.json"
  carry_tree "commands"
  carry_tree "rules"
  carry_tree "output-styles"
  # Agents: a SkillForge backup (marker: _protocol.md) holds its persona agents,
  # which are the predecessor's machinery, not this project's — leave them buried.
  if [ ! -f "$BAK/_protocol.md" ] && [ -d "$BAK/agents" ]; then
    for f in "$BAK/agents"/*.md; do
      [ -f "$f" ] || continue
      name="${f##*/}"
      [ -e "$DEST/.claude/agents/$name" ] && continue
      cp "$f" "$DEST/.claude/agents/$name"
      carried="$carried agents/$name"
    done
  fi
  [ -n "$carried" ] && ok "carried over from the previous .claude:$carried"
fi

# Seeds: create only if absent — never overwrite project state.
mkdir -p "$DEST/memory/lessons" "$DEST/memory/antipatterns" "$DEST/memory/patterns" "$DEST/stages"
for d in memory/lessons memory/antipatterns memory/patterns stages; do
  touch "$DEST/$d/.gitkeep"   # empty dirs survive git clone
done
seeded=""
for f in BACKLOG.md PARKED.md OPS.md keel.json; do
  [ -f "$DEST/$f" ] || { cp "$SRC/bundle/seed/$f" "$DEST/$f"; seeded="$seeded $f"; }
done
[ -f "$DEST/memory/MEMORY.md" ] || cp "$SRC/bundle/seed/MEMORY.md" "$DEST/memory/MEMORY.md"
[ -n "$seeded" ] && ok "seeded:$seeded" || ok "project state preserved (nothing overwritten)"

# Keep secret values, QA output and worktree copies out of the index.
# A .gitignore whose last line has no newline is ordinary; appending to it blind
# glues our first pattern onto the project's last one and silently breaks both.
# One newline, once, before the loop — not per pattern.
touch "$DEST/.gitignore"
if [ -s "$DEST/.gitignore" ] && [ -n "$(tail -c 1 "$DEST/.gitignore")" ]; then
  printf '\n' >> "$DEST/.gitignore"
fi
for pat in ".secrets.env" ".qa/" ".claude/worktrees/" ".claude.bak.*"; do
  grep -qxF "$pat" "$DEST/.gitignore" || printf '%s\n' "$pat" >> "$DEST/.gitignore"
done

# A `claude --worktree` session starts in a fresh checkout, which by definition
# has no ignored files — so the secrets file the whole project depends on is
# absent there unless it is named here.
if [ ! -f "$DEST/.worktreeinclude" ]; then
  printf '%s\n' ".secrets.env" > "$DEST/.worktreeinclude"
  ok ".worktreeinclude seeded (.secrets.env follows you into a worktree session)"
fi

# MCP: seed only when the project has no .mcp.json at all — an existing one is
# the owner's, and merging into it blind is how a working config gets broken.
# A server whose launcher is missing is worse than no server: Claude Code retries
# it every session start and reports a failure the owner did not cause. So the
# seed is filtered down to the servers this machine can actually run.
mcp_note=""
if [ ! -f "$DEST/.mcp.json" ]; then
  if command -v python3 >/dev/null 2>&1; then
    mcp_note="$(python3 - "$SRC/bundle/seed/mcp.json" "$DEST/.mcp.json" <<'PY' || true
import json, shutil, sys

seed, out = sys.argv[1], sys.argv[2]
d = json.load(open(seed, encoding="utf-8"))
servers = d.get("mcpServers", {})
kept, dropped = {}, []
for name, cfg in servers.items():
    cmd = cfg.get("command") if isinstance(cfg, dict) else None
    if cmd and shutil.which(cmd):
        kept[name] = cfg
    else:
        dropped.append("%s (needs %s)" % (name, cmd or "?"))
if kept:
    d["mcpServers"] = kept
    with open(out, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
print("kept:" + ", ".join(sorted(kept)))
print("dropped:" + ", ".join(dropped))
PY
)"
    kept="$(printf '%s\n' "$mcp_note" | sed -n 's/^kept: *//p')"
    dropped="$(printf '%s\n' "$mcp_note" | sed -n 's/^dropped: *//p')"
    [ -n "$kept" ] && ok ".mcp.json seeded: $kept"
    [ -n "$dropped" ] && warn "not seeded — launcher missing: $dropped (add from keel/bundle/seed/mcp.json once installed)"
    [ -n "$kept" ] || warn "no .mcp.json written: none of the seed's servers can run here"
  else
    cp "$SRC/bundle/seed/mcp.json" "$DEST/.mcp.json"
    warn ".mcp.json seeded unfiltered (no python3 to check launchers) — remove any server whose command you do not have"
  fi
else
  # An existing .mcp.json is the owner's and is left exactly as it is. It is
  # still worth one line: every configured server ships its whole tool schema
  # into every session AND into every subagent the session spawns, so a config
  # nobody has pruned is a standing tax on context nobody chose to pay.
  # Counting needs python3; without it, or on a file that does not parse, say
  # nothing — a guess about someone's config is worse than silence.
  if command -v python3 >/dev/null 2>&1; then
    n_mcp="$(python3 - "$DEST/.mcp.json" 2>/dev/null <<'PY' || true
import json, sys
try:
    servers = json.load(open(sys.argv[1], encoding="utf-8")).get("mcpServers")
except Exception:
    sys.exit(0)
if isinstance(servers, dict) and servers:
    print(len(servers))
PY
)"
    if [ -n "$n_mcp" ]; then
      warn "$n_mcp MCP servers configured — each costs schema tokens in every session and every subagent; keep only what this project uses"
    fi
  fi
  if ! grep -q '"serena"' "$DEST/.mcp.json" 2>/dev/null; then
    warn "existing .mcp.json has no serena entry — consider adding it (see bundle/seed/mcp.json)"
  fi
fi

# VS Code recommendations: memory/ is a [[wikilink]] graph and the guides draw
# their diagrams in mermaid — Foam renders the first, the mermaid preview the
# second, and neither is discoverable from an empty editor. Seeded only when
# the project has no recommendations file of its own; a project that wrote one
# is not ours to edit, and saying so would be noise about a non-event.
if [ ! -f "$DEST/.vscode/extensions.json" ]; then
  mkdir -p "$DEST/.vscode"
  printf '%s\n' '{"recommendations":["foam.foam-vscode","bierner.markdown-mermaid"]}' \
    > "$DEST/.vscode/extensions.json"
  ok ".vscode/extensions.json seeded (Foam graphs memory/, mermaid renders the diagrams)"
fi

# Integrations: what this machine can already reach. Detection only — an
# installer that installs toolchains or signs anything in is an installer the
# owner cannot audit. One line each, so the report stays skimmable.
tool_line() {
  if command -v "$1" >/dev/null 2>&1; then
    printf '    %s✓%s %-9s %s%s%s\n' "$G" "$R" "$1" "$D" "$2" "$R"
  else
    printf '    %s·%s %-9s %s%s%s\n' "$D" "$R" "$1" "$D" "$2" "$R"
  fi
}
printf '\n  %sintegrations%s\n' "$B" "$R"
tool_line gh      "releases and CI checks"
tool_line uvx     "serena LSP navigation"
tool_line npx     "context7 docs, Playwright"
tool_line node    "browser QA scripts"
tool_line python3 "JSON helpers in hooks"
tool_line codex   "an external second opinion the owner may ask for"
tool_line gemini  "an external second opinion the owner may ask for"
if [ -d "$HOME/Library/Caches/ms-playwright" ] || [ -d "${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright" ]; then
  printf '    %s✓%s %-9s %s%s%s\n' "$G" "$R" "browsers" "$D" "Playwright browsers present (qa-browser, site-sweep)" "$R"
else
  printf '    %s·%s %-9s %s%s%s\n' "$D" "$R" "browsers" "$D" "no Playwright browsers: npx playwright install chromium" "$R"
fi
printf '    %s%s%s\n' "$D" "Claude Design: /design drafts UI on a canvas; /design-login then /design-sync connect the repo's design system — ask the owner" "$R"
printf '    %s%s%s\n' "$D" "nothing was installed or signed in; in Claude Code run /integrations to record what this project can reach" "$R"

# Previous-system residue: detect only. Sweeping is the migrate skill's job,
# with the owner present — an installer does not move someone's files.
residue=0
if [ -x "$DEST/.claude/skills/migrate/sweep.sh" ]; then
  report="$(cd "$DEST" && CLAUDE_PROJECT_DIR="$DEST" bash .claude/skills/migrate/sweep.sh 2>/dev/null || true)"
  # Only real machinery raises the migrate banner. Flagged-only reports (e.g. the
  # .claude.bak this very install just created) are not "SkillForge residue".
  case "$report" in
    *"MACHINERY ("*) residue=1 ;;
    *) printf '\n'; ok "no previous-system residue" ;;
  esac
fi

# Self-check. Failing loudly here beats handing over a kernel that loads
# half-way: a broken .claude sitting where a working one used to be is the worst
# state of all, and the owner is not required to remember the backup's name — so
# a failed check puts the previous .claude back itself.
selfcheck_fail() {
  printf 'keel: SELF-CHECK FAILED — %s\n' "$1" >&2
  rm -rf "$DEST/.claude"
  if [ -n "${BAK:-}" ] && [ -d "$BAK" ]; then
    mv "$BAK" "$DEST/.claude"
    echo "keel: rolled back — the previous .claude is back in place (from ${BAK##*/})" >&2
  else
    echo "keel: there was no previous .claude; the failed install was removed" >&2
  fi
  exit 1
}
[ -f "$DEST/.claude/CLAUDE.md" ] || selfcheck_fail "no contract at .claude/CLAUDE.md"
for h in "$DEST/.claude/hooks"/*.sh; do
  [ -e "$h" ] || continue
  [ -x "$h" ] || selfcheck_fail "hook not executable: ${h##*/}"
done
[ "$n_skills" = "$n_skills_src" ] \
  || selfcheck_fail "$n_skills skills installed, the kernel ships $n_skills_src"
[ -f "$DEST/.claude/agents/scout.md" ] && [ -f "$DEST/.claude/agents/verifier.md" ] \
  || selfcheck_fail "kernel agents missing (scout, verifier)"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$DEST/.claude/settings.json" >/dev/null 2>&1 \
    || selfcheck_fail "settings.json does not parse — the harness would load no hooks"
fi
# Shipped scripts are checked by RUNNING one, against a throwaway project: on the
# real project a tool may legitimately report findings, which is not a breakage.
SCTMP="$(mktemp -d)"
mkdir -p "$SCTMP/memory"
cp "$SRC/bundle/seed/MEMORY.md" "$SCTMP/memory/MEMORY.md" 2>/dev/null || true
if ! ( cd "$DEST" && CLAUDE_PROJECT_DIR="$SCTMP" bash .claude/skills/recall/anchors.sh --list >/dev/null 2>&1 ); then
  rm -rf "$SCTMP"
  selfcheck_fail "recall anchors.sh does not run on a fresh install"
fi
rm -rf "$SCTMP"
ok "self-check — OK"

printf '\n%s  keel %s installed%s\n\n' "$B" "$VER" "$R"

if [ "$residue" -eq 1 ]; then
  printf '  %sSkillForge residue detected.%s The kernel changed underneath this project.\n' "$Y" "$R"
  printf '  Nothing was moved. In Claude Code, run the %smigrate%s skill: it quarantines the\n' "$B" "$R"
  printf '  predecessor'"'"'s machinery (never your memory, stages, or backlog) and proposes a re-audit.\n\n'
  printf '  %sPreview what it would sweep:%s\n' "$D" "$R"
  printf '  %sbash .claude/skills/migrate/sweep.sh%s\n\n' "$D" "$R"
fi

# This script is as often run BY Claude ("install keel from the archive in this
# folder") as by a human at a prompt, so the next steps must read correctly either way.
say "  next:"
[ "$residue" -eq 1 ] && say "    · clean up the old system: run the migrate skill (preview: bash .claude/skills/migrate/sweep.sh)"
say "    · in Claude Code run /integrations to record what this project can reach"
say "    · optional browser QA dependency: npx playwright install chromium"
say "    · if you ran this from a terminal: open the project in Claude Code"
case "$SRC" in
  "$DEST"/*) printf '\n  %skeep keel/ for updates (re-run this script) or delete it; consider gitignoring keel/%s\n' "$D" "$R" ;;
esac
printf '\n'
