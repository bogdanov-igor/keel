---
name: memory-consolidation
description: Scan memory/ and propose (never apply) consolidation — merge duplicate lessons, promote a recurring lesson to patterns/, repair dead [[wikilinks]], flag stale notes, tighten MEMORY.md index lines. Run when memory feels noisy or on a periodic hygiene pass.
---

# Memory consolidation

Propose-only: this skill never edits, merges, deletes, or re-links a
note. Detection is deterministic (grep, file checks, title overlap,
git log); judgment is applied only to deterministic shortlists. No
embeddings, no external tooling — the corpus is plain markdown under
`memory/` with `memory/MEMORY.md` as a strict one-line index.

## Procedure

1. **Inventory.** `graph.sh` derives the graph from the notes
   themselves — totals, hubs, dead links, orphans. Call it; do not
   re-derive the same greps inline.

   ```bash
   bash .claude/skills/memory-consolidation/graph.sh
   bash .claude/skills/memory-consolidation/graph.sh --edges > /tmp/mc_edges.txt
   ```

   The summary is the read; `--edges` is the raw adjacency list
   (`src<TAB>dst`) for citations and per-pair checks below. Edge
   extraction drops fenced code blocks, inline code spans and POSIX
   classes like `[[:space:]]`, so prose about wikilinks is not
   miscounted as an edge.

   HUBS — the most-cited notes — is the cheap centrality signal that
   replaced the predecessor's PageRank: same links read out of the
   same files, minus the scoring machinery. It feeds step 6: a note
   cited by 2+ others is the promote-to-pattern trigger. For the
   picture rather than the list, open `memory/` in Obsidian or VS Code
   Foam — markdown with `[[wikilinks]]` is their native graph format,
   nothing to install.

2. **Dead wikilinks.** The DEAD LINKS block names every `[[slug]]`
   target with no note behind it, plus the notes citing it. Propose a
   repair per hit: point to the intended note (a renamed file usually
   shows up in `git log --diff-filter=R -- memory/`) or drop the link
   if the target was deliberately removed.

3. **Orphans.** The ORPHANS block names notes with no link in and no
   link out. An orphan also absent from `MEMORY.md` is unreachable —
   flag it for an index line or an explicit prune decision by the
   owner.

4. **Index integrity and hygiene.** Every index entry resolves to a
   file; every note has exactly one index line; each entry is one
   physical line, ≤120 chars, hook naming the symptom (skill
   `remember`'s contract). Flag violations and any domain section
   that has outgrown one-glance size (~40 lines → propose a split).

   ```bash
   grep -oE '\]\([^)]+\)' memory/MEMORY.md | tr -d '])(' | while read -r rel; do
     [ -f "memory/$rel" ] || echo "INDEX_DANGLING: $rel"
   done
   awk 'length > 120 {print "OVERLONG:" FNR": " substr($0,1,60) "..."}' memory/MEMORY.md
   ```

5. **Near-duplicate lessons.** Shortlist lesson pairs whose titles
   share high token overlap (Jaccard over title words ≥ 0.6), then
   judge each shortlisted pair: same trap or fix described twice →
   propose a merge into one note that supersedes both.

6. **Promote to pattern.** A lesson cited via `[[slug]]` from 2+
   other notes (HUBS counts this directly, `count ← slug`), or whose
   theme recurs across 2+ lessons, has the real-use count a pattern
   requires — propose promotion into `memory/patterns/` with the
   source lessons linked as evidence.

7. **Stale notes.** Date each note with
   `git log -1 --format=%cs -- <file>`. A lesson untouched ~90+ days
   whose cited `path:line` or commit evidence no longer resolves, or
   that a later note contradicts, is a stale candidate — flag it for
   update-in-place or pruning. Age alone is never grounds: patterns
   and antipatterns are reference knowledge regardless of date or
   inbound-link count.

## Output

Present the proposal list in chat — action (merge / promote /
repair-link / flag-stale / index-fix), targets, one-line rationale,
and a grep or `path:line` citation each — plus summary counts. Queue
proposals so they survive the session, one `BACKLOG.md` line each:

`- [ ] P2 | memory | repair-link: [[old-slug]] -> lessons/new-slug | ev:mc_edges grep | src:memory-consolidation`

Dead links and index integrity breaks are P2 (they silently break
recall); merges, promotions, and stale flags are P3. Owner-approved
proposals are applied in a later step via skill `remember`
(update-in-place, never a duplicate alongside) or manual edit.

## Do not

- Apply anything in the same pass, however obvious the fix looks.
- Propose pruning a pattern or antipattern for low inbound links.
- Silently cap coverage: if only part of `memory/` was scanned,
  say exactly what was skipped in the summary.
