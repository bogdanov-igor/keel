# Keel self-tests — 46-forkbomb-guard. Sourced from test/run.sh; REPO/SK/HK/TMP
# and the helpers ok/bad/has/hasnt/section come from there.

# ── forkbomb-guard: persistent launches denied, one-shots untouched ──────────
# The classifier is head-based, so the two failure modes it must never have are
# both covered here: a build segment shadowing a dev segment in a compound
# command, and a neutral head (grep) tripping on a persistent-looking argument.
section "forkbomb-guard — dev servers denied, one-shot commands allowed"
fb() { printf '%s' "$1" | bash "$HK/forkbomb-guard.sh" 2>&1; }
fb_deny()  { fb_out="$(fb "$1")"; has '"permissionDecision":"deny"' "$fb_out" "$2"; }
fb_allow() { fb_out="$(fb "$1")"; [ "$fb_out" = "{}" ] && ok || bad "$2 (got: $fb_out)"; }

fb_deny  '{"tool_input":{"command":"npm run dev"}}'                  "npm run dev is a dev server"
fb_deny  '{"tool_input":{"command":"bash -c \"next dev\""}}'         "a shell -c wrapper does not hide next dev"
fb_deny  '{"tool_input":{"command":"PORT=3000 npm start"}}'          "leading env assignments do not hide npm start"
fb_deny  '{"tool_input":{"command":"npm run build && npm run dev"}}' "a build segment cannot shadow a dev segment"
fb_deny  '{"tool_input":{"command":"npx playwright test"}}'          "playwright test drives a browser"
fb_deny  '{"tool_input":{"command":"python3 -m http.server 8000"}}'  "python3 -m http.server serves"

fb_allow '{"tool_input":{"command":"next build"}}'                        "next build is one-shot"
fb_allow '{"tool_input":{"command":"grep -rn serve ."}}'                  "grep for the word serve is not a server"
fb_allow '{"tool_input":{"command":"vitest run"}}'                        "vitest run is one-shot"
fb_allow '{"tool_input":{"command":"safe-run --label web -- npm run dev"}}' "the safe-run launcher is the sanctioned path"
fb_allow '{"tool_input":{"command":"npx playwright install chromium"}}'   "playwright install downloads and exits"
fb_allow '{"tool_input":{"command":"tsc"}}'                               "tsc is one-shot"
