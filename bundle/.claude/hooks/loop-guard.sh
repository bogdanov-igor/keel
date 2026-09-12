#!/usr/bin/env bash
# PostToolUseFailure loop guard (the contract's two-attempts rule): when the
# same Bash command fails a third time with the same first error line, hand the
# rule back. Advisory — it speaks, it never blocks; the tool has already failed.
# Matcher (settings.json): Bash. Full hook JSON on stdin.
#
# Why: the contract's two-attempts rule ("stop, file the symptom in BACKLOG.md,
# continue from a fresh context") is prose that must be recalled at the one
# moment recall is worst — three retries deep on the same broken command,
# tunnel-visioned, certain the next tweak is the one. The recorded pain
# is exactly that loop, burning a context window on a fix that never lands. So
# the reminder arrives from the harness instead of from memory.
#
# What is scanned: tool_name (Bash only), tool_input.command, is_interrupt (a
# Ctrl-C is not a failed attempt), session_id, and `error` — whose first line is
# "Exit code N" and whose remainder is the interleaved output (measured against
# Claude Code 2.1.87). An error that does not start with "Exit code N" is not a
# command that ran and failed, so it is not counted.
#
# What makes two failures "the same": a hash of the command with whitespace
# collapsed, plus the first real output line with every digit run folded to '#'
# — a port, a pid, a duration or a timestamp in the message must not make three
# identical failures look like three different ones.
#
# State: one small file per session, "<sig> <count>", under
# $KEEL_LOOP_STATE_DIR (else $TMPDIR, else /tmp). The third hit fires and resets
# the count to 0, so a genuinely stubborn command can fire again after three
# more. Each fire also appends a line to the tally file next to it — the only
# way to learn whether this hook fires at all, and how often, is to count.
#
# jq parses the payload, python3 when jq is missing or broken. With neither, the
# hook stays silent: an advisory has nothing to say about a payload it cannot
# read, and guessing would mean reciting the rule at an innocent command.
# Never fails, never blocks: exit 0 on every path.
set -uo pipefail
LIMIT=3        # failures with one signature before the rule is quoted back
CMDCUT=60      # characters of the command echoed in the reminder
SIGCUT=80      # characters of the error line kept in the signature

quiet() { echo '{}'; exit 0; }

# JSON string escaping for the answer — a command carries quotes and backslashes
# far more often than not, and an unparsable answer is a silently lost hook.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

payload="$(cat)"
[ -n "$payload" ] || quiet

# One extraction, six lines: tool_name, is_interrupt, session_id, the
# whitespace-collapsed command, the error's first line, and the first non-empty
# line after it. Normalising inside the extractor keeps every field free of
# newlines, so the record stays line-readable in bash 3.2 (no mapfile).
JQ_REC='
def nrm: tostring | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
. as $d
| (($d.error // "") | tostring | split("\n")) as $e
| [ (($d.tool_name // "") | tostring),
    (if ($d.is_interrupt == true) then "true" else "false" end),
    (($d.session_id // "") | tostring),
    ((($d.tool_input // {}) | if type == "object" then (.command // "") else "" end) | nrm),
    (($e[0] // "") | nrm),
    (([ $e[1:][] | select(test("\\S")) ][0] // "") | nrm)
  ] | .[]
'

PY_REC='
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(2)
if not isinstance(d, dict):
    sys.exit(2)
def nrm(v):
    return re.sub(r"\s+", " ", "" if v is None else str(v)).strip()
ti = d.get("tool_input")
cmd = ti.get("command", "") if isinstance(ti, dict) else ""
lines = str(d.get("error") or "").split("\n")
first = lines[0] if lines else ""
rest = ""
for ln in lines[1:]:
    if ln.strip():
        rest = ln
        break
sys.stdout.write("\n".join([
    nrm(d.get("tool_name", "")),
    "true" if d.get("is_interrupt") is True else "false",
    nrm(d.get("session_id", "")),
    nrm(cmd),
    nrm(first),
    nrm(rest),
]))
'

rec=""
if ! rec="$(printf '%s' "$payload" | jq -r "$JQ_REC" 2>/dev/null)"; then rec=""; fi
[ -n "$rec" ] || rec="$(printf '%s' "$payload" | python3 -c "$PY_REC" 2>/dev/null || true)"
[ -n "$rec" ] || quiet

tool_name=""; is_int=""; sess=""; cmd=""; err_head=""; err_line=""
{
  IFS= read -r tool_name
  IFS= read -r is_int
  IFS= read -r sess
  IFS= read -r cmd
  IFS= read -r err_head
  IFS= read -r err_line
} <<EOF
$rec
EOF

[ "$tool_name" = "Bash" ] || quiet
[ "$is_int" = "true" ] && quiet
[ -n "$cmd" ] || quiet
[ -n "$sess" ] || quiet
case "$err_head" in
  'Exit code '[0-9]*) ;;
  *) quiet ;;                       # not a command that ran and exited non-zero
esac

# ── signature ───────────────────────────────────────────────────────────────
# shasum is on every macOS and every Linux with perl; cksum is the POSIX floor.
hash=""
if command -v shasum >/dev/null 2>&1; then
  hash="$(printf '%s' "$cmd" | shasum -a 1 2>/dev/null | cut -d' ' -f1)"
fi
[ -n "$hash" ] || hash="$(printf '%s' "$cmd" | cksum 2>/dev/null | cut -d' ' -f1)"
[ -n "$hash" ] || quiet

tail_line="$(printf '%s' "$err_line" | sed 's/[0-9][0-9]*/#/g' 2>/dev/null)"
tail_line="${tail_line:0:$SIGCUT}"
sig="$hash"
[ -n "$tail_line" ] && sig="$hash $tail_line"

# ── state ───────────────────────────────────────────────────────────────────
STATE_DIR="${KEEL_LOOP_STATE_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$STATE_DIR" 2>/dev/null || quiet
safe_sess="${sess//[^A-Za-z0-9._-]/_}"          # a session id is a file name here
STATE="$STATE_DIR/keel-loop-guard-$safe_sess"

prev_line=""; prev_sig=""; prev_count=0
if [ -f "$STATE" ]; then
  IFS= read -r prev_line < "$STATE" 2>/dev/null || prev_line=""
  # The signature carries spaces, so the count is the LAST field, not the second.
  case "$prev_line" in
    *' '*) prev_count="${prev_line##* }"; prev_sig="${prev_line% *}" ;;
  esac
  case "$prev_count" in ''|*[!0-9]*) prev_count=0; prev_sig="" ;; esac
fi

if [ "$sig" = "$prev_sig" ]; then count=$((prev_count + 1)); else count=1; fi

if [ "$count" -ge "$LIMIT" ]; then
  printf '%s 0\n' "$sig" > "$STATE" 2>/dev/null || true
  printf '%s %s fired\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" "$sig" \
    >> "$STATE_DIR/keel-loop-guard-tally" 2>/dev/null || true
  esc="$(json_escape "${cmd:0:$CMDCUT}")"
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"keel loop-guard: this command has now failed %s times with the same first error line — `%s`. The contract'\''s two-attempts rule applies: stop, file the symptom in BACKLOG.md, change the approach or continue from a fresh context."}}\n' \
    "$LIMIT" "$esc"
  exit 0
fi

printf '%s %s\n' "$sig" "$count" > "$STATE" 2>/dev/null || true
echo '{}'
exit 0
