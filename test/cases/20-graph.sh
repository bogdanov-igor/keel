# Keel self-tests — 20-graph. Sourced by test/run.sh.
graph() { CLAUDE_PROJECT_DIR="$1" bash "$SK/memory-consolidation/graph.sh" "${@:2}" 2>&1; }

section "graph — edges, code-fence exclusion, empty"
G="$TMP/graph"; mkdir -p "$G/memory/lessons"
printf -- '---\nname: a\n---\nSee [[b]].\n\n```sh\ngrep "[[:space:]]" f  # not an edge\n```\nAnd `[[inline]]` prose.\n' > "$G/memory/lessons/a.md"
printf -- '---\nname: b\n---\nBack to [[a]].\n' > "$G/memory/lessons/b.md"
out="$(graph "$G" --edges)"
has "a	b" "$out" "real [[b]] edge extracted"
hasnt ":space:" "$out" "POSIX class in a code fence is not an edge"
hasnt "inline" "$out" "inline-code [[x]] is not an edge"
out="$(graph "$G")"; has "2 notes · 2 edges" "$out" "totals correct"
GE="$TMP/graph-empty"; mkdir -p "$GE/memory/lessons"; cp "$REPO/bundle/seed/MEMORY.md" "$GE/memory/"
out="$(graph "$GE")"; has "none yet" "$out" "empty memory says none yet, no phantom hub"
