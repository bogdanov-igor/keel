#!/usr/bin/env bash
# What does this project already know about this code?
#
#   bash anchors.sh apps/web/proxy.ts          # before you touch it
#   bash anchors.sh handleRequest              # by symbol
#   bash anchors.sh --check                    # dead anchors: code moved, notes now lie
#   bash anchors.sh --list                     # every anchor in memory
#
# Grounding by SYMPTOM is grep. Grounding by LOCATION is this. Contract rule 2
# asks for memory before nontrivial work — but a lesson about proxy.ts is
# useless if the only way to find it is guessing the symptom that led to it.
#
# Anchors live in note front-matter, which makes them checkable:
#
#   ---
#   name: cron-runner-host-header-regression
#   kind: antipattern
#   code:
#     - apps/web/proxy.ts#handleRequest
#     - apps/web/middleware.ts
#   ---
#
# Code→code edges (callers, references, call hierarchy) are NOT rebuilt here:
# serena/LSP computes them exactly and live. Hand-maintained code structure
# rots; an LSP does not. This layer only carries what an LSP cannot know —
# what we LEARNED about a place in the code.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MEM="$ROOT/memory"
[ -d "$MEM" ] || { echo "recall: no memory/ at $ROOT" >&2; exit 1; }

# Emit "note<TAB>anchor" for every `code:` entry in every note's front-matter.
anchors() {
  find "$MEM" -name '*.md' ! -name 'MEMORY.md' | while read -r f; do
    awk -v note="$f" '
      NR == 1 && $0 ~ /^---[[:space:]]*$/ { fm = 1; next }
      fm && $0 ~ /^---[[:space:]]*$/      { exit }
      fm && $0 ~ /^code:[[:space:]]*$/    { incode = 1; next }
      fm && incode && $0 ~ /^[[:space:]]*-[[:space:]]*/ {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        gsub(/^["'"'"']|["'"'"']$/, "", line)
        if (line != "") printf "%s\t%s\n", note, line
        next
      }
      fm && incode && $0 !~ /^[[:space:]]/ { incode = 0 }
    ' "$f"
  done
}

slug() { basename "$1" .md; }

# ── --check: an anchor that no longer resolves means the note is stale.
if [ "${1:-}" = "--check" ]; then
  total=0; dead=0
  while IFS=$'\t' read -r note anchor; do
    [ -n "$anchor" ] || continue
    total=$((total + 1))
    path="${anchor%%#*}"; sym="${anchor#*#}"; [ "$sym" = "$anchor" ] && sym=""
    if [ ! -e "$ROOT/$path" ]; then
      echo "DEAD_FILE   $anchor  ← $(slug "$note")"
      dead=$((dead + 1))
    # Word boundary, and comment lines do not count as existence.
    #   -w   : without it, renaming handleRequest → handleRequestV2 leaves the old
    #          anchor "alive" as a substring — and the suffix rename (V2, Async,
    #          Internal) is the commonest refactor there is.
    #   -v … : a symbol that survives only in "// handleRequest was removed in v3"
    #          does not exist. A comment is a tombstone, not a definition.
    # Both are false negatives, and a false negative here is the silent rot this
    # check exists to catch.
    elif [ -n "$sym" ] && ! grep -vE '^[[:space:]]*(//|\*|#|--)' "$ROOT/$path" 2>/dev/null \
                          | grep -qwF "$sym"; then
      echo "DEAD_SYMBOL $anchor  ← $(slug "$note")  (file exists; symbol gone — renamed?)"
      dead=$((dead + 1))
    fi
  done < <(anchors)
  echo
  if [ "$total" -eq 0 ]; then
    echo "recall: no code: anchors in memory yet — notes about code cannot be found by location."
    echo "        add them as you write (skill remember), starting with the code you touch most."
  else
    echo "recall: $total anchors, $dead dead."
    [ "$dead" -gt 0 ] && echo "        Each dead anchor is a note that now describes code which no longer exists."
    [ "$dead" -gt 0 ] && echo "        File them: - [ ] P2 | memory | repair anchor <anchor> | src:recall"
  fi
  exit 0
fi

# ── --list
if [ "${1:-}" = "--list" ]; then
  anchors | while IFS=$'\t' read -r note anchor; do
    printf '%-48s %s\n' "$anchor" "$(slug "$note")"
  done | sort
  exit 0
fi

# ── --backfill: existing notes name code in prose but cannot be found by it.
# Resolve each mention against the real tree and anchor the ones that resolve to
# exactly one file. Dry-run by default; --apply writes. Ambiguous and missing
# mentions are reported, never guessed — anchoring a path that does not resolve
# would just manufacture a dead anchor.
if [ "${1:-}" = "--backfill" ]; then
  APPLY=0; [ "${2:-}" = "--apply" ] && APPLY=1
  EXT='ts|tsx|js|jsx|mjs|cjs|sql|py|go|css|json|sh'
  IDX="$(mktemp)"; trap 'rm -f "$IDX"' EXIT
  # index of real source files (relpaths from ROOT), machinery excluded
  find "$ROOT" \( -name node_modules -o -name .git -o -name .data -o -name dist \
       -o -name build -o -name .next -o -name .turbo -o -path "$MEM" \) -prune -o \
       -type f -print 2>/dev/null | sed "s|^$ROOT/||" > "$IDX"
  [ -s "$IDX" ] || { echo "recall backfill: no source files under $ROOT to resolve against." >&2; exit 1; }

  body() { awk 'NR==1 && /^---[[:space:]]*$/{fm=1;next} fm&&/^---[[:space:]]*$/{fm=0;next} !fm' "$1"; }
  has_code() { awk 'NR==1 && /^---[[:space:]]*$/{fm=1;next} fm&&/^---[[:space:]]*$/{exit} fm&&/^code:[[:space:]]*$/{print"y";exit}' "$1"; }
  # candidates for a mention: index line == mention, or ending in "/"+mention
  resolve() { awk -v m="$1" 'BEGIN{n=length(m)} $0==m{print;next} length($0)>n && substr($0,length($0)-n)=="/"m{print}' "$IDX"; }

  n_notes=0; n_anch=0; n_res=0; n_amb=0; n_miss=0
  while read -r f; do
    [ -n "$f" ] || continue
    n_notes=$((n_notes+1))
    [ -n "$(has_code "$f")" ] && continue         # idempotent: skip already-anchored
    declare -a picks=(); seen=" "
    while read -r tok; do
      [ -n "$tok" ] || continue
      base="${tok%%#*}"; base="${base%%:*}"; base="${base%[.,);:]}"
      sym=""; case "$tok" in *#*) sym="${tok#*#}";; esac
      case "$seen" in *" $base "*) continue;; esac; seen="$seen$base "
      cands="$(resolve "$base")"; c="$(printf '%s' "$cands" | grep -c . )"
      if [ "$c" -eq 1 ]; then
        n_res=$((n_res+1)); picks+=("$cands${sym:+#$sym}")
      elif [ "$c" -gt 1 ]; then n_amb=$((n_amb+1))
      else n_miss=$((n_miss+1)); fi
    done < <(body "$f" | grep -oE "[A-Za-z0-9_][A-Za-z0-9_./-]*\.($EXT)(#[A-Za-z0-9_]+)?" 2>/dev/null)

    [ "${#picks[@]}" -eq 0 ] && continue
    n_anch=$((n_anch+1))
    # cap per note to keep front-matter sane
    block="code:"$'\n'; i=0
    for a in "${picks[@]}"; do [ "$i" -ge 12 ] && break; block="$block  - $a"$'\n'; i=$((i+1)); done
    echo "  $(slug "$f"): ${#picks[@]} anchor(s)"
    printf '%s' "$block" | sed 's/^/      /'
    if [ "$APPLY" -eq 1 ]; then
      tmp="$(mktemp)"
      if head -1 "$f" | grep -q '^---[[:space:]]*$'; then
        # insert the block just before the closing --- of the front-matter.
        # (awk -v cannot carry a multi-line value, so splice with head/tail.)
        close="$(awk 'NR>1 && /^---[[:space:]]*$/{print NR; exit}' "$f")"
        if [ -n "$close" ]; then
          head -n "$((close-1))" "$f" > "$tmp"
          printf '%s' "$block" >> "$tmp"
          tail -n "+$close" "$f" >> "$tmp"
        else
          cp "$f" "$tmp"   # malformed front-matter (no close): leave untouched
        fi
      else
        { printf -- '---\n%s---\n\n' "$block"; cat "$f"; } > "$tmp"
      fi
      mv "$tmp" "$f"
    fi
  done < <(find "$MEM" -name '*.md' ! -name 'MEMORY.md')

  echo
  echo "recall backfill: $n_notes notes · $n_anch anchored · $n_res resolved · $n_amb ambiguous · $n_miss unresolved"
  [ "$APPLY" -eq 0 ] && echo "        dry run — nothing written. Re-run with --apply to write the anchors." \
                     || echo "        written. Verify: bash .claude/skills/recall/anchors.sh --check"
  [ "$n_amb" -gt 0 ] && echo "        ambiguous mentions (many files match a bare name) were left for you to anchor by hand."
  exit 0
fi

# ── recall <path-or-symbol>
Q="${1:-}"
[ -n "$Q" ] || { echo "usage: anchors.sh <path|symbol> | --check | --list" >&2; exit 1; }
BASE="$(basename "$Q")"

echo "== what this project knows about: $Q"
echo

echo "ANCHORED (notes that declared this code in front-matter):"
hit=0
while IFS=$'\t' read -r note anchor; do
  case "$anchor" in
    *"$Q"*|*"$BASE"*)
      desc="$(sed -n 's/^description:[[:space:]]*//p' "$note" | head -1 | cut -c1-90)"
      kind="$(sed -n 's/^kind:[[:space:]]*//p' "$note" | head -1)"
      printf '  %-11s %s\n' "[${kind:-note}]" "$(slug "$note")"
      [ -n "$desc" ] && printf '              %s\n' "$desc"
      printf '              → %s  ·  %s\n' "$anchor" "${note#$ROOT/}"
      hit=1 ;;
  esac
done < <(anchors)
[ "$hit" -eq 0 ] && echo "  none"
echo

# Unanchored prose mentions: weaker and noisier — a note that says "proxy.ts"
# once in passing ranks with one that is about proxy.ts. Rank by how often the
# note names it, so the ones actually about this code float up. This noise is
# the argument for anchors, not a substitute for them.
echo "MENTIONED (notes naming it in prose — ranked by density; not anchored, so not checkable):"
found=0
while read -r n f; do
  [ -n "$f" ] || continue
  desc="$(sed -n 's/^description:[[:space:]]*//p' "$f" | head -1 | cut -c1-88)"
  kind="$(sed -n 's/^kind:[[:space:]]*//p' "$f" | head -1)"
  printf '  %2d×  %-13s %s\n' "$n" "[${kind:-note}]" "$(slug "$f")"
  [ -n "$desc" ] && printf '                     %s\n' "$desc"
  found=$((found + 1))
done < <(grep -rlF "$BASE" "$MEM" --include='*.md' 2>/dev/null | grep -v '/MEMORY.md$' \
         | while read -r f; do
             # -o | wc -l counts MENTIONS. grep -c would count matching LINES, and a
             # note naming the file five times on one line is not a passing mention.
             printf '%s %s\n' "$(grep -oF "$BASE" "$f" | wc -l | tr -d ' ')" "$f"
           done | sort -rn | head -8)
[ "$found" -eq 0 ] && echo "  none"

echo
echo "Code structure (callers, references, call hierarchy) is serena's job, not this tool's:"
echo "  serena find_symbol / find_referencing_symbols — exact and live."
if [ "$found" -gt 0 ] && [ "$hit" -eq 0 ]; then
  echo
  echo "NOTE: $found note(s) mention this code but none anchor it. Anchor them (skill remember)"
  echo "      and they become findable by location — and their rot becomes detectable."
fi
