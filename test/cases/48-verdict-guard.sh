# Keel self-tests — 48-verdict-guard. Sourced from test/run.sh; REPO/SK/HK/TMP
# and the helpers ok/bad/has/hasnt/section come from there.

# ── verdict-guard: a verdict in a stage report needs a real run behind it ────
section "verdict-guard — a hand-written verifier verdict is blocked"
vg() { printf '%s' "$1" | bash "$HK/verdict-guard.sh" 2>&1; }
vg_allow() { vg_out="$(vg "$1")"; [ "$vg_out" = "{}" ] && ok || bad "$2 (got: $vg_out)"; }

vg_out="$(vg '{"tool_name":"Write","tool_input":{"file_path":"stages/007-a/report.md","content":"Verifier: 6 pass / 0 fail"}}')"
has '"permissionDecision":"deny"' "$vg_out" "a verdict count with no agent id → deny"
has 'run pending' "$vg_out" "the deny names the honest placeholder"
printf '%s' "$vg_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["hookSpecificOutput"]["permissionDecision"]=="deny" else 1)' \
  && ok || bad "the deny answer is valid JSON (got: $vg_out)"

vg_allow '{"tool_name":"Write","tool_input":{"file_path":"stages/007-a/report.md","content":"Verifier: 6 pass / 0 fail (agent id a1b2c3d4e5f6a7b8c)"}}' \
  "a verdict carrying its agent id is allowed"
vg_allow '{"tool_name":"Write","tool_input":{"file_path":"stages/007-a/report.md","content":"Verifier: run pending"}}' \
  "the run-pending placeholder is allowed"
vg_allow '{"tool_name":"Write","tool_input":{"file_path":"docs/report.md","content":"Verifier: 6 pass / 0 fail"}}' \
  "the same text outside stages/ is none of the hook's business"
vg_allow '{"tool_name":"Edit","tool_input":{"file_path":"stages/007-a/report.md","old_string":"a","new_string":"Unit 3 shipped; evidence in .qa/rail.png"}}' \
  "an edit with no verdict count is allowed"

# An Edit that introduces the fabricated count is the same fabrication.
vg_out="$(vg '{"tool_name":"Edit","tool_input":{"file_path":"stages/007-a/report.md","old_string":"Verifier: run pending","new_string":"Verifier: 12 PASS / 1 FAIL"}}')"
has '"permissionDecision":"deny"' "$vg_out" "case and spacing variants are caught in an Edit"
