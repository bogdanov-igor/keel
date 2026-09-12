# Keel self-tests — 45-leak-guard. Sourced from test/run.sh; REPO/SK/HK/TMP and
# the helpers ok/bad/has/hasnt/section come from there.

# ── leak-guard: only the NEW text is scanned, only real values are secrets ───
section "leak-guard — secret values in a write"
LG="$TMP/lg"; mkdir -p "$LG"
lg() { CLAUDE_PROJECT_DIR="$LG" bash "$HK/leak-guard.sh" 2>&1; }

# Silent without .secrets.env: the hook sleeps until there are secrets to leak.
lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"content":"sk-super-secret-value"}}' | lg)"
[ "$lg_out" = "{}" ] && ok || bad "no .secrets.env → hook stays silent (got: $lg_out)"

{
  printf 'TOKEN=sk-super-secret-value\n'
  printf 'PORT=8080\n'
  printf 'export CRLFKEY=crlf-value-long\r\n'
  printf '%s\n' 'Q=abc"def\ghi'
  printf '%s\n' '  CMT=commentvalue # trailing note'
  printf '%s\n' 'WEIRD"KEY=weird-value-123'
} > "$LG/.secrets.env"

lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"host: sk-super-secret-value"}}' | lg)"
has '"permissionDecision":"deny"' "$lg_out" "secret in Write.content → deny"
has 'secret TOKEN' "$lg_out" "the deny names the key"
has '{{secret:TOKEN}}' "$lg_out" "the deny offers the placeholder form"

lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"ordinary prose"}}' | lg)"
[ "$lg_out" = "{}" ] && ok || bad "clean write passes (got: $lg_out)"

# A value carrying a quote and a backslash arrives JSON-escaped in the payload.
lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"v=abc\"def\\ghi"}}' | lg)"
has 'secret Q' "$lg_out" "JSON-escaped value is recognised"

# The edit that REMOVES a leaked secret: the value only sits in old_string.
lg_out="$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"a.md","old_string":"TOKEN=sk-super-secret-value","new_string":"TOKEN={{secret:TOKEN}}"}}' | lg)"
[ "$lg_out" = "{}" ] && ok || bad "Edit removing the secret is allowed (got: $lg_out)"
lg_out="$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"a.md","old_string":"x","new_string":"sk-super-secret-value"}}' | lg)"
has '"deny"' "$lg_out" "Edit introducing the secret → deny"

# Short values are never secrets: otherwise PORT=8080 matches any number.
lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"listening on port 8080"}}' | lg)"
[ "$lg_out" = "{}" ] && ok || bad "short value is not a secret (got: $lg_out)"

# Tolerant .secrets.env parsing: export, CRLF, inline comment.
lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"crlf-value-long"}}' | lg)"
has 'secret CRLFKEY' "$lg_out" "export KEY= and CRLF are parsed"
lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"commentvalue"}}' | lg)"
has 'secret CMT' "$lg_out" "inline comment stays out of the value"

# A key with a quote must not break the answer JSON — else the harness cannot
# read the denial and the write goes through.
lg_out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.md","content":"weird-value-123"}}' | lg)"
printf '%s' "$lg_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["hookSpecificOutput"]["permissionDecision"]=="deny" else 1)' \
  && ok || bad "answer JSON stays valid for a key with a quote (got: $lg_out)"
