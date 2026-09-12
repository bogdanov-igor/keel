#!/usr/bin/env bash
# Sweep SkillForge (and derivative) residue out of a Keel project.
#
#   bash sweep.sh            # detect only: print a report, change nothing
#   bash sweep.sh --apply    # move machinery into .keel-migration/<ts>/ + manifest
#
# Two hard rules:
#   1. Nothing is ever deleted — residue is MOVED to a timestamped quarantine.
#   2. Project state is never touched: memory/ notes, stages/, BACKLOG.md,
#      PARKED.md, OPS.md, .claude/skills/_user, and product source are yours.
#      Only the predecessor's *machinery* is swept.
# Anything ambiguous is FLAGGED for the owner, never moved automatically.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
cd "$ROOT" || exit 1

TS="$(date +%Y%m%d%H%M%S)"
QUAR=".keel-migration/$TS"

# SkillForge kernel skills — ghosts if they survived into a Keel .claude.
GHOST_SKILLS="dreaming memory-eval outcomes sleep-time-consolidation sf-code-review sf-security-review chat-render-enable ops-safe-dev-server"
# SkillForge persona agents — Keel decomposes by context, not by job title.
GHOST_AGENTS="orchestrator product qa security devops research copy skill-creator"

machinery=()   # swept on --apply
flagged=()     # reported only; the owner decides

add_m() { [ -e "$1" ] && machinery+=("$1"); }
add_f() { [ -e "$1" ] && flagged+=("$1|$2"); }

# --- machinery: unambiguously the predecessor's engine -----------------------
add_m "skillforge"
for f in skillforge_*.tgz skillforge_*.tgz.sha256; do add_m "$f"; done
add_m ".claude/_protocol.md"
add_m ".claude/playbooks"
add_m ".claude/hooks/memory-residue-check.sh"
for s in $GHOST_SKILLS; do add_m ".claude/skills/$s"; done
for a in $GHOST_AGENTS; do add_m ".claude/agents/$a.md"; done
# dev-safe.sh only when it is actually the predecessor's launcher.
if [ -f "dev-safe.sh" ] && grep -qi -e skillforge -e 'sf_' dev-safe.sh 2>/dev/null; then
  add_m "dev-safe.sh"
fi

# .mcp.json: the SkillForge MCP server entry points at a bundle that is going away.
MCP_DIRTY=0
if [ -f ".mcp.json" ] && grep -q skillforge .mcp.json 2>/dev/null; then
  MCP_DIRTY=1
fi

# --- flagged: plausibly yours, so never touched automatically ----------------
add_f "prompts" "task prompts — yours unless they were SkillForge scaffolding"
add_f ".backups" "snapshots — likely from a _user skill (repo-archive-snapshot)"
add_f "INSTALL.ru.md" "predecessor install docs — superseded by Keel's docs/"
add_f "INSTALL.en.md" "predecessor install docs — superseded by Keel's docs/"
add_f "LAUNCH-OPS.md" "launch ops notes — OPS.md is Keel's duty board; merge what still matters"
add_f "memory/signals" "signal notes — valuable content, non-Keel layout; keep or fold into memory/lessons"
add_f "memory/chat-render-active.md" "note from the chat-render patch system, which Keel does not ship"
# A backup with a VERSION file inside is one Keel's own installer made, so it
# holds a Keel kernel, not a predecessor's. Saying that plainly stops the owner
# from opening it looking for SkillForge state that was never there.
for d in .claude.bak.*; do
  if [ -f "$d/VERSION" ]; then
    add_f "$d" "keel's own backup left by install.sh — prune when you no longer need it"
  else
    add_f "$d" "previous kernel backup, left by install.sh — prune when you no longer need it"
  fi
done

# --- report ------------------------------------------------------------------
if [ "${#machinery[@]}" -eq 0 ] && [ "$MCP_DIRTY" -eq 0 ] && [ "${#flagged[@]}" -eq 0 ]; then
  echo "keel migrate: clean — no SkillForge residue found."
  exit 0
fi

echo "== SkillForge residue in $ROOT"
echo
if [ "${#machinery[@]}" -gt 0 ] || [ "$MCP_DIRTY" -eq 1 ]; then
  echo "MACHINERY (swept to $QUAR/ on --apply):"
  # Guarded: expanding an empty array under `set -u` is a fatal error in the
  # bash 3.2 that ships with macOS, and a dirty .mcp.json alone gets us here.
  if [ "${#machinery[@]}" -gt 0 ]; then
    for m in "${machinery[@]}"; do
      sz="$(du -sh "$m" 2>/dev/null | cut -f1)"
      echo "  - $m  (${sz:-?})"
    done
  fi
  [ "$MCP_DIRTY" -eq 1 ] && echo "  - .mcp.json  (skillforge server entry — Keel has no MCP of its own)"
  echo
fi
if [ "${#flagged[@]}" -gt 0 ]; then
  echo "FLAGGED (never moved automatically — your call):"
  for f in "${flagged[@]}"; do
    echo "  - ${f%%|*}  — ${f#*|}"
  done
  echo
fi
echo "NEVER TOUCHED: memory/ notes · stages/ · BACKLOG.md · PARKED.md · OPS.md · .claude/skills/_user · your source"

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "Detection only — nothing changed. To sweep: bash .claude/skills/migrate/sweep.sh --apply"
  exit 0
fi

# --- apply -------------------------------------------------------------------
[ "${#machinery[@]}" -eq 0 ] && [ "$MCP_DIRTY" -eq 0 ] && { echo; echo "Nothing to sweep."; exit 0; }

mkdir -p "$QUAR" || exit 1
MAN="$QUAR/MANIFEST.md"
{
  echo "# Keel migration — $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "SkillForge machinery moved out of the project. Nothing was deleted:"
  echo "every path below is preserved here; the \`## Restore\` block at the end"
  echo "puts any of it back verbatim."
  echo
  echo "## Moved"
} > "$MAN"

# Each moved item earns its own restore command, carrying its own mkdir -p: by
# the time anyone reads this manifest the parent directory may well be gone
# (that is usually why the sweep happened), and a bare `mv` would fail there.
restores=()
if [ "${#machinery[@]}" -gt 0 ]; then
  for m in "${machinery[@]}"; do
    dst="$QUAR/$m"
    mkdir -p "$(dirname "$dst")"
    if mv "$m" "$dst" 2>/dev/null; then
      echo "- \`$m\` → \`$dst\`" >> "$MAN"
      restores+=("mkdir -p \"$(dirname "$m")\" && mv \"$dst\" \"$m\"")
      echo "keel migrate: swept $m"
    fi
  done
fi

if [ "$MCP_DIRTY" -eq 1 ]; then
  cp .mcp.json "$QUAR/mcp.json.before" 2>/dev/null
  # Drop the skillforge server; keep every other entry byte-for-byte.
  if python3 - "$PWD/.mcp.json" <<'PY' 2>/dev/null
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
servers = d.get("mcpServers", {})
if servers.pop("skillforge", None) is None:
    sys.exit(1)
with open(p, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  then
    echo "- \`.mcp.json\`: removed the \`skillforge\` server entry (original: \`$QUAR/mcp.json.before\`)" >> "$MAN"
    echo "keel migrate: removed the skillforge MCP entry from .mcp.json"
  else
    echo "- \`.mcp.json\`: **manual edit needed** — remove the \`skillforge\` server entry by hand" >> "$MAN"
    echo "keel migrate: could not edit .mcp.json automatically — remove the skillforge entry by hand" >&2
  fi
fi

{
  echo
  echo "## Flagged, left in place"
  if [ "${#flagged[@]}" -gt 0 ]; then
    for f in "${flagged[@]}"; do echo "- \`${f%%|*}\` — ${f#*|}"; done
  else
    echo "- none"
  fi
  echo
  echo "## Not touched"
  echo "\`memory/\` notes · \`stages/\` · \`BACKLOG.md\` · \`PARKED.md\` · \`OPS.md\` ·"
  echo "\`.claude/skills/_user\` · product source."
  echo
  echo "## Restore"
  echo "Run from the project root. Each line puts one item back where it was;"
  echo "run the whole block to undo the sweep entirely."
  echo "\`\`\`sh"
  if [ "${#restores[@]}" -gt 0 ]; then
    for r in "${restores[@]}"; do echo "$r"; done
  else
    echo "# nothing was moved"
  fi
  echo "\`\`\`"
} >> "$MAN"

# A .gitignore whose last line has no newline is ordinary; appending blind glues
# our pattern onto the project's last one and silently breaks both.
touch .gitignore
if [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ]; then
  printf '\n' >> .gitignore
fi
grep -qxF ".keel-migration/" .gitignore 2>/dev/null || echo ".keel-migration/" >> .gitignore

# The re-audit is the point of migrating, so the script files it itself: an item
# that depends on the agent remembering to write it is an item that gets lost.
if [ -f "BACKLOG.md" ] && ! grep -q "src:migrate" BACKLOG.md 2>/dev/null; then
  printf -- '- [ ] P1 | kernel | Re-audit after Keel migration: codebase-map + scoped audits + memory consolidation | ev:%s | src:migrate\n' \
    "$MAN" >> BACKLOG.md
  echo "keel migrate: filed the re-audit into BACKLOG.md"
fi

# Removing the skillforge server can leave .mcp.json with nothing in it.
if [ -f ".mcp.json" ] && tr -d ' \n\t' < .mcp.json | grep -q '"mcpServers":{}'; then
  echo "keel migrate: .mcp.json now has no servers — seed serena + context7 from keel/bundle/seed/mcp.json"
fi

echo
echo "keel migrate: done — manifest at $MAN"
echo "next: the kernel changed underneath this project; a re-audit is due (skill: audit)"
