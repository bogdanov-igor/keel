# Keel self-tests — 50-update-check. Sourced from test/run.sh; REPO/SK/HK/TMP
# and the helpers ok/bad/has/hasnt/section come from there.

# ── update-check: one line, and only when upstream is strictly newer ─────────
# Hermetic: the GitHub cache is seeded, so no case here touches the network.
section "update-check — speaks only when strictly newer, silent otherwise"
U="$TMP/upd"; mkdir -p "$U/.claude" "$U/cache/keel"
cp "$REPO/bundle/seed/keel.json" "$U/keel.json"
printf '%s\n1.9.9\n' "9999999999" > "$U/cache/keel/latest-bogdanov-igor-keel"   # fresh cache, no network
uc() { echo "$1" > "$U/.claude/VERSION"; CLAUDE_PROJECT_DIR="$U" XDG_CACHE_HOME="$U/cache" KEEL_NO_UPDATE_CHECK=0 bash "$HK/update-check.sh" 2>&1; }
has    "1.9.9 is available" "$(uc 1.0.0)" "older local → announces"
hasnt  "available"          "$(uc 1.9.9)" "current local → silent"
hasnt  "available"          "$(uc 2.0.0)" "local ahead of release → silent"
hasnt  "available"          "$(echo 1.0.0 > "$U/.claude/VERSION"; CLAUDE_PROJECT_DIR="$U" XDG_CACHE_HOME="$U/cache" KEEL_NO_UPDATE_CHECK=1 bash "$HK/update-check.sh" 2>&1)" \
  "KEEL_NO_UPDATE_CHECK=1 → silent"
python3 - "$U/keel.json" <<'PY' 2>/dev/null || sed -i.bak 's/"enabled": true/"enabled": false/' "$U/keel.json"
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["update_check"]["enabled"]=False; json.dump(d,open(p,"w"))
PY
hasnt  "available"          "$(uc 1.0.0)" "opt-out → silent"

# ── an unreachable network is not paid for three seconds every session ──────
# curl is shadowed by a stub: without the negative cache the hook would call it
# on every single session start.
section "update-check — a failed fetch is cached too"
UN="$TMP/updn"; mkdir -p "$UN/.claude" "$UN/cache" "$UN/bin"
echo "1.0.0" > "$UN/.claude/VERSION"
printf '#!/bin/sh\necho call >> "%s"\nexit 7\n' "$UN/curl.log" > "$UN/bin/curl"
chmod +x "$UN/bin/curl"; : > "$UN/curl.log"
ucn() { PATH="$UN/bin:$PATH" CLAUDE_PROJECT_DIR="$UN" XDG_CACHE_HOME="$UN/cache" KEEL_NO_UPDATE_CHECK=0 bash "$HK/update-check.sh" 2>&1; }
out="$(ucn)"
[ -z "$out" ] && ok || bad "network down → silent (got: $out)"
[ -f "$UN/cache/keel/latest-bogdanov-igor-keel" ] && ok || bad "a failed fetch is written to the cache"
out="$(ucn)"
[ "$(wc -l < "$UN/curl.log" | tr -d ' ')" = "1" ] && ok || bad "negative cache: the second start does not hit the network"

# ── neither HOME nor XDG_CACHE_HOME: no cache, but no crash either ──────────
section "update-check — survives an environment without HOME"
mkdir -p "$UN/keel"; echo "9.9.9" > "$UN/keel/VERSION"
out="$(env -u HOME -u XDG_CACHE_HOME PATH="$UN/bin:$PATH" CLAUDE_PROJECT_DIR="$UN" KEEL_NO_UPDATE_CHECK=0 bash "$HK/update-check.sh" 2>&1)"; code=$?
[ "$code" -eq 0 ] && ok || bad "HOME unset → exits 0 (got: $code)"
hasnt "unbound" "$out" "HOME unset → no unbound variable"
has "9.9.9 is available in keel/ next to this project" "$out" "a newer local keel/ is announced without a cache"

# ── the config is read scoped to update_check, not by whole-file grep ───────
# keel.json has several objects; circuit_breaker keys must not switch the
# update check off. Second pass: python3 shadowed by a stub, so the sed
# fallback has to scope the substring by itself.
section "update-check — keel.json is parsed scoped to update_check"
US="$TMP/upds"; mkdir -p "$US/.claude" "$US/keel" "$US/bin"
echo "1.0.0" > "$US/.claude/VERSION"; echo "2.0.0" > "$US/keel/VERSION"
cat > "$US/keel.json" <<'JSON'
{
  "circuit_breaker": { "enabled": false, "max_tree_procs": 80 },
  "update_check": { "enabled": true, "repo": "bogdanov-igor/keel", "interval_hours": 24 }
}
JSON
printf '#!/bin/sh\nexit 1\n' > "$US/bin/python3"; chmod +x "$US/bin/python3"
out="$(env -u HOME -u XDG_CACHE_HOME CLAUDE_PROJECT_DIR="$US" KEEL_NO_UPDATE_CHECK=0 bash "$HK/update-check.sh" 2>&1)"
has "2.0.0 is available" "$out" "\"enabled\": false in another section does not disable the check"
out="$(env -u HOME -u XDG_CACHE_HOME PATH="$US/bin:$PATH" CLAUDE_PROJECT_DIR="$US" KEEL_NO_UPDATE_CHECK=0 bash "$HK/update-check.sh" 2>&1)"
has "2.0.0 is available" "$out" "without python3 the sed fallback scopes the substring too"
