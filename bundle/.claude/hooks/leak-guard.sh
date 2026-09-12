#!/usr/bin/env bash
# PreToolUse leak guard (the contract's secrets rule): deny any write whose NEW
# content contains a .secrets.env value. Safe — only the never-intended case is
# blocked; dormant when .secrets.env is absent. Full hook JSON on stdin.
# Matcher (settings.json): Write|Edit|NotebookEdit.
# Bash is intentionally NOT matched — command-side leaks are review territory.
#
# What is scanned: only the text being written — Write.content, Edit.new_string
# (a batched edit: every edits[].new_string), NotebookEdit.new_source. Scanning the
# whole payload blocked the edit that REMOVES a leaked secret, because the value
# still sits in old_string. jq parses the JSON when present, python3 otherwise
# (the same order forkbomb-guard uses); when neither is there, or the payload is
# unparsable, we scan the raw payload — noisier, never quieter.
#
# What counts as a secret: a .secrets.env value of 6 characters or more. Shorter
# values (PORT=8080, USER=admin) match any number or word in any document and
# would make the hook a nuisance instead of a guard.
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "$0")" && pwd -P)"
MINLEN=6

# Project root: the harness sets CLAUDE_PROJECT_DIR for hook invocations.
# Manual runs fall back to the physical up-walk (hooks -> .claude -> project).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  HOST="$(cd "$CLAUDE_PROJECT_DIR" && pwd -P)"
else
  HOST="$(cd "$HOOK_DIR/../.." && pwd -P)"
fi
SECRETS="${KEEL_SECRETS_FILE:-$HOST/.secrets.env}"

payload="$(cat)"

# A worktree session may carry its own .secrets.env (.worktreeinclude copies
# it) while CLAUDE_PROJECT_DIR still names the main checkout — measured: the
# variable follows a `claude --worktree` launch, the docs say it stays put when
# a session enters a worktree later. The payload's cwd names the branch being
# written, so its project's file is scanned too; both files, never one.
SECRETS2=""
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$cwd" ] && cwd="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("cwd","") or "")' 2>/dev/null || true)"
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  dir="$(cd "$cwd" 2>/dev/null && pwd -P)" || dir=""
  while [ -n "$dir" ]; do
    if [ -d "$dir/.claude" ] || [ -f "$dir/BACKLOG.md" ]; then
      [ "$dir/.secrets.env" != "$SECRETS" ] && [ -s "$dir/.secrets.env" ] && SECRETS2="$dir/.secrets.env"
      break
    fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
fi
[ -s "$SECRETS" ] || [ -n "$SECRETS2" ] || { echo '{}'; exit 0; }

# JSON string escaping — for the answer (a key may carry a quote or a
# backslash) and for the fallback comparison against the raw payload.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# Both extractors exit non-zero when the payload carries no new-text field at
# all, so "unknown tool" stays distinguishable from "new text is empty" — the
# first must fall back to the raw payload, the second must not.
JQ_NEW_TEXT='(.tool_input // {}) as $ti
| if ($ti | type) != "object" then error("no tool_input")
  else [ $ti.content, $ti.new_string, $ti.new_source,
         ( $ti.edits | arrays | .[] | objects | .new_string ) ]
       | map(select(. != null))
       | if length == 0 then error("no new text")
         else map(if type == "string" then . else tostring end) | join("\n") end
  end'

PY_NEW_TEXT='
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(2)
ti = d.get("tool_input")
if not isinstance(ti, dict):
    sys.exit(2)
out = []
found = False
for k in ("content", "new_string", "new_source"):
    if k in ti:
        found = True
        v = ti[k]
        if isinstance(v, list):
            out.append("".join(str(x) for x in v))
        elif v is not None:
            out.append(str(v))
edits = ti.get("edits")
if isinstance(edits, list):
    for it in edits:
        if isinstance(it, dict) and "new_string" in it:
            found = True
            out.append(str(it["new_string"]))
if not found:
    sys.exit(2)
sys.stdout.write("\n".join(out))
'

parsed=0
if subject="$(printf '%s' "$payload" | jq -r "$JQ_NEW_TEXT" 2>/dev/null)"; then
  parsed=1
elif subject="$(printf '%s' "$payload" | python3 -c "$PY_NEW_TEXT" 2>/dev/null)"; then
  parsed=1
fi
[ "$parsed" -eq 1 ] || subject="$payload"   # no parser / unknown tool: scan all

leak=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"                          # CRLF-authored .secrets.env
  line="${line#"${line%%[![:space:]]*}"}"       # leading whitespace
  case "$line" in ''|\#*) continue ;; esac
  case "$line" in 'export '*) line="${line#export }" ;; esac
  case "$line" in *=*) ;; *) continue ;; esac
  key="${line%%=*}"; val="${line#*=}"
  key="${key%"${key##*[![:space:]]}"}"          # trailing whitespace in key
  val="${val#"${val%%[![:space:]]*}"}"          # leading whitespace in value
  case "$val" in
    # quoted value: everything up to the closing quote, tail (comment) ignored
    \"*) val="${val#\"}"; val="${val%%\"*}" ;;
    \'*) val="${val#\'}"; val="${val%%\'*}" ;;
    *)   case "$val" in *' #'*) val="${val%% #*}" ;; esac   # inline comment
         val="${val%"${val##*[![:space:]]}"}" ;;
  esac
  [ "${#val}" -ge "$MINLEN" ] || continue
  esc="$(json_escape "$val")"
  case "$subject" in
    *"$val"*) leak="$key" ;;
    *"$esc"*) leak="$key" ;;                    # payload seen unparsed
  esac
  [ -n "$leak" ] && break
done < <(cat "$SECRETS" ${SECRETS2:+"$SECRETS2"} 2>/dev/null)

if [ -n "$leak" ]; then
  k="$(json_escape "$leak")"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: this write contains the value of secret %s. Reference {{secret:%s}} instead (the contract'\''s secrets rule). Values shorter than %s characters are never treated as secrets."}}\n' \
    "$k" "$k" "$MINLEN"
  exit 0
fi
echo '{}'
exit 0
