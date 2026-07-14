#!/usr/bin/env bash
# Keel installer: copy the kernel into a project.
# Usage: bash install.sh [/path/to/project]     (no argument = install here)
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
if [ -e "$DEST/.claude" ] || [ -L "$DEST/.claude" ]; then
  BAK="$DEST/.claude.bak.$(date +%Y%m%d%H%M%S)"
  mv "$DEST/.claude" "$BAK"
  ok "previous .claude → ${BAK##*/}"
fi
cp -R "$SRC/bundle/.claude" "$DEST/.claude"
chmod +x "$DEST/.claude/hooks/"*.sh \
         "$DEST/.claude/skills/safe-dev-server/safe-run.sh" \
         "$DEST/.claude/skills/migrate/sweep.sh"
# The update-check hook compares this against the latest upstream release.
printf '%s\n' "$VER" > "$DEST/.claude/VERSION"
ok "kernel installed ($(ls "$DEST/.claude/skills" | wc -l | tr -d ' ') skills, 2 agents, 3 hooks)"

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

# Keep secret values and QA output out of git (contract rule 8 / qa-browser).
touch "$DEST/.gitignore"
for pat in ".secrets.env" ".qa/"; do
  grep -qxF "$pat" "$DEST/.gitignore" || printf '%s\n' "$pat" >> "$DEST/.gitignore"
done

# MCP: seed serena (LSP navigation) + context7 (live library docs) if absent.
if [ ! -f "$DEST/.mcp.json" ]; then
  cp "$SRC/bundle/seed/mcp.json" "$DEST/.mcp.json"
  ok ".mcp.json seeded: serena (needs uvx) + context7 (needs npx)"
elif ! grep -q '"serena"' "$DEST/.mcp.json" 2>/dev/null; then
  warn "existing .mcp.json has no serena entry — consider adding it (see bundle/seed/mcp.json)"
fi

# Previous-system residue: detect only. Sweeping is the migrate skill's job,
# with the owner present — an installer does not move someone's files.
residue=0
if [ -x "$DEST/.claude/skills/migrate/sweep.sh" ]; then
  report="$(cd "$DEST" && CLAUDE_PROJECT_DIR="$DEST" bash .claude/skills/migrate/sweep.sh 2>/dev/null || true)"
  case "$report" in
    *"no SkillForge residue found"*) ok "no previous-system residue" ;;
    '') ok "no previous-system residue" ;;
    *) residue=1 ;;
  esac
fi

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
say "    · optional browser QA dependency: npx playwright install chromium"
say "    · if you ran this from a terminal: open the project in Claude Code"
case "$SRC" in
  "$DEST"/*) printf '\n  %skeep keel/ for updates (re-run this script) or delete it; consider gitignoring keel/%s\n' "$D" "$R" ;;
esac
printf '\n'
