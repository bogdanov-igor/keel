#!/usr/bin/env bash
# PreToolUse verdict guard: deny a stage report that states a verifier verdict
# ("6 pass / 0 fail") without the agent id of the run that produced it.
# Matcher (settings.json): Write|Edit. Full hook JSON on stdin.
#
# Why: a stage closes on the verifier's verdict, and a verdict is the one thing
# a session cannot produce by introspection. Typing plausible numbers into
# report.md is the cheapest way to fake done-ness, and it reads exactly like a
# real pass afterwards. The agent id is the receipt — it exists only if a run
# happened. Placeholders ("Verifier: run pending") are always allowed; this
# guard blocks the fabrication, not the honest admission that no run happened.
#
# Scope: only files whose path ends in stages/<something>/report.md. Everything
# else — docs, notes, code — passes untouched.
set -uo pipefail

payload="$(cat)"
allow() { echo '{}'; exit 0; }

# Extract like forkbomb-guard does: jq if present, else python3, else allow.
# A guard that cannot read the payload must not guess.
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -z "$file_path" ] && file_path="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tool_input",{}).get("file_path","") or "")' 2>/dev/null || true)"
[ -z "$file_path" ] && allow

case "$file_path" in
  *stages/*/report.md) ;;
  *) allow ;;
esac

JQ_NEW_TEXT='(.tool_input // {}) as $ti
| [ $ti.content, $ti.new_string,
    ( $ti.edits | arrays | .[] | objects | .new_string ) ]
| map(select(. != null))
| map(if type == "string" then . else tostring end)
| join("\n")'

PY_NEW_TEXT='
import json, sys
try:
    ti = json.load(sys.stdin).get("tool_input") or {}
except Exception:
    ti = {}
out = []
for k in ("content", "new_string"):
    v = ti.get(k)
    if isinstance(v, list):
        out.append("".join(str(x) for x in v))
    elif v is not None:
        out.append(str(v))
edits = ti.get("edits")
if isinstance(edits, list):
    for it in edits:
        if isinstance(it, dict) and it.get("new_string") is not None:
            out.append(str(it["new_string"]))
sys.stdout.write("\n".join(out))
'

text="$(printf '%s' "$payload" | jq -r "$JQ_NEW_TEXT" 2>/dev/null || true)"
[ -z "$text" ] && text="$(printf '%s' "$payload" | python3 -c "$PY_NEW_TEXT" 2>/dev/null || true)"
[ -z "$text" ] && allow

# A verdict count, spaces and case tolerated: "6 pass / 0 fail", "12 PASS/3 FAIL".
COUNT_RE='[0-9]+[[:space:]]*pass[[:space:]]*/[[:space:]]*[0-9]+[[:space:]]*fail'
verdict_lines="$(printf '%s\n' "$text" | grep -Ei "$COUNT_RE" 2>/dev/null || true)"
[ -z "$verdict_lines" ] && allow

# Receipt, either shape: the words "agent id" / agentId / agent-id followed by a
# token anywhere in the new text, or a bare 12+ hex id on the verdict line.
printf '%s\n' "$text" | grep -Eiq 'agent[[:space:]_-]*id[[:space:]:=]*[A-Za-z0-9_-]{4,}' && allow
printf '%s\n' "$verdict_lines" | grep -Eiq '(^|[^0-9A-Za-z])[0-9a-f]{12,}([^0-9A-Za-z]|$)' && allow

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: a verifier verdict is pasted from a real verifier run together with its agent id — write \\"Verifier: run pending\\" until the run happened (stage rule: a hand-written verdict is a fabrication)."}}\n'
exit 0
