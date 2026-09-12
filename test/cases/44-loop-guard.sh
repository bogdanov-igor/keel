# Keel self-tests — 44-loop-guard. Sourced from test/run.sh; REPO/SK/HK/TMP and
# the helpers ok/bad/has/hasnt/section come from there.

# ── loop-guard: the third identical failure quotes the two-attempts rule ─────
# The fixture below is a real PostToolUseFailure payload, captured from Claude
# Code 2.1.87 on 2026-09-12 (only transcript_path was trimmed). It pins the
# shape the hook depends on: a Bash failure fires PostToolUseFailure, not
# PostToolUse; `error` is "Exit code N" followed by the interleaved output;
# is_interrupt rides along. A hand-written payload would let the hook drift away
# from the harness without a single test turning red.
section "loop-guard — three identical Bash failures pull the rule back"
LOOPD="$TMP/loop"; mkdir -p "$LOOPD"

loop_pay="$(cat <<'PAYLOAD'
{"session_id":"94a7207b-8f22-427b-9730-bd5fd810e485","cwd":"/private/tmp/claude-501/-Users-bogdanov-i-a--Documents-keel/978d8ee4-cd81-41e3-a82f-1f8ec02c6ac4/scratchpad/exp-fail","permission_mode":"bypassPermissions","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"bash -c 'echo boom on port 3000 >&2; exit 3'","description":"First command - exits with code 3"},"tool_use_id":"toolu_01Ue2U3bjEeZ2AeGjoLLYC3B","error":"Exit code 3\nboom on port 3000","is_interrupt":false}
PAYLOAD
)"

# Variants are derived from the captured payload instead of re-typed, so every
# case still carries the real field set. Keys: session / command / error /
# is_interrupt; "\n" in an error value becomes a real newline.
loop_var() {
  printf '%s' "$loop_pay" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for a in sys.argv[1:]:
    k, v = a.split("=", 1)
    if k == "session":
        d["session_id"] = v
    elif k == "command":
        d["tool_input"]["command"] = v
    elif k == "error":
        d["error"] = v.replace("\\n", "\n")
    elif k == "is_interrupt":
        d["is_interrupt"] = (v == "true")
    else:
        d[k] = v
sys.stdout.write(json.dumps(d))
' "$@"
}
loop_run()   { printf '%s' "$1" | KEEL_LOOP_STATE_DIR="$LOOPD" bash "$HK/loop-guard.sh" 2>&1; }
loop_quiet() { loop_out="$(loop_run "$1")"; [ "$loop_out" = "{}" ] && ok || bad "$2 (got: $loop_out)"; }

loop_quiet "$loop_pay" "the first failure is not a loop"
loop_quiet "$loop_pay" "the second failure is still inside the two-attempts rule"
loop_out="$(loop_run "$loop_pay")"
has 'failed 3 times' "$loop_out" "the third identical failure fires"
has 'BACKLOG.md' "$loop_out" "the advisory names where the symptom goes"
has 'echo boom on port 3000' "$loop_out" "the advisory quotes the command"
printf '%s' "$loop_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["hookSpecificOutput"]["hookEventName"]=="PostToolUseFailure" and "failed 3 times" in d["hookSpecificOutput"]["additionalContext"] else 1)' \
  && ok || bad "the advisory is valid PostToolUseFailure JSON (got: $loop_out)"
loop_quiet "$loop_pay" "the counter resets after firing, so the fourth is quiet"

# A different first error line is a different failure: the counter starts over,
# and the attempt that would have been the third stays quiet.
loop_quiet "$(loop_var session=s-reset)"                                        "reset: first failure"
loop_quiet "$(loop_var session=s-reset)"                                        "reset: second failure"
loop_quiet "$(loop_var session=s-reset 'error=Exit code 1\nfile not found')"    "reset: a different error line is a different failure"
loop_quiet "$(loop_var session=s-reset)"                                        "reset: the original failure is back at one"

# Digits are noise: a port, a pid or a duration in the error line must not make
# three of the same failure look like three different ones.
loop_quiet "$(loop_var session=s-digits 'error=Exit code 3\nboom on port 3001')" "digits: first"
loop_quiet "$(loop_var session=s-digits 'error=Exit code 3\nboom on port 4002')" "digits: second"
loop_out="$(loop_run "$(loop_var session=s-digits 'error=Exit code 3\nboom on port 5999')")"
has 'failed 3 times' "$loop_out" "a changing port number does not defeat the match"

# Sessions are independent: two parallel sessions each keep their own count.
loop_quiet "$(loop_var session=s-other)" "another session starts at one"
loop_quiet "$(loop_var session=s-other)" "another session is still at two"
[ -f "$LOOPD/keel-loop-guard-94a7207b-8f22-427b-9730-bd5fd810e485" ] && ok || bad "the captured session has its own state file"
[ -f "$LOOPD/keel-loop-guard-s-other" ] && ok || bad "a second session has a separate state file"

# jq is not a dependency: with jq broken, python3 must produce the same
# signature — otherwise the fallback silently resets the count on every hop.
mkdir -p "$LOOPD/bin"; printf '#!/bin/sh\nexit 1\n' > "$LOOPD/bin/jq"; chmod +x "$LOOPD/bin/jq"
loop_quiet "$(loop_var session=s-nojq)" "no-jq: first failure through jq"
loop_quiet "$(loop_var session=s-nojq)" "no-jq: second failure through jq"
loop_out="$(printf '%s' "$(loop_var session=s-nojq)" | PATH="$LOOPD/bin:$PATH" KEEL_LOOP_STATE_DIR="$LOOPD" bash "$HK/loop-guard.sh" 2>&1)"
has 'failed 3 times' "$loop_out" "the python3 fallback computes the same signature as jq"

# An interrupt is the owner stopping the work, not a failed attempt.
loop_quiet "$(loop_var session=s-int is_interrupt=true)" "an interrupt is not an attempt (1)"
loop_quiet "$(loop_var session=s-int is_interrupt=true)" "an interrupt is not an attempt (2)"
loop_quiet "$(loop_var session=s-int is_interrupt=true)" "an interrupt never reaches the third strike"
[ -f "$LOOPD/keel-loop-guard-s-int" ] && bad "an interrupt leaves no state behind" || ok

# An error that is not "Exit code N" is not a command that ran and failed.
loop_quiet "$(loop_var session=s-noexit 'error=Command timed out after 2m')" "a non-exit-code error is ignored (1)"
loop_quiet "$(loop_var session=s-noexit 'error=Command timed out after 2m')" "a non-exit-code error is ignored (2)"
loop_quiet "$(loop_var session=s-noexit 'error=Command timed out after 2m')" "a non-exit-code error never fires"
[ -f "$LOOPD/keel-loop-guard-s-noexit" ] && bad "a non-exit-code error leaves no state behind" || ok

# Another tool's failure is not this hook's business, even under a Bash matcher.
loop_quiet '{"session_id":"s-tool","tool_name":"Read","tool_input":{"file_path":"x"},"error":"Exit code 1\nnope"}' "a non-Bash failure is ignored"

loop_out="$(printf 'not json at all' | KEEL_LOOP_STATE_DIR="$LOOPD" bash "$HK/loop-guard.sh" 2>&1)"; loop_code=$?
[ "$loop_out" = "{}" ] && ok || bad "garbage on stdin answers {} (got: $loop_out)"
[ "$loop_code" -eq 0 ] && ok || bad "garbage on stdin still exits 0 (got: $loop_code)"

# The tally is the only way to learn whether this hook fires at all: one line
# per fire, and three have fired above.
loop_tally="$(wc -l < "$LOOPD/keel-loop-guard-tally" 2>/dev/null | tr -d ' ')"
[ "$loop_tally" = "3" ] && ok || bad "the tally file gets one line per fire (want 3, got: $loop_tally)"
has 'fired' "$(cat "$LOOPD/keel-loop-guard-tally" 2>/dev/null)" "each tally line is marked fired"

# ── the answer stays valid JSON whatever the command carries ─────────────────
# A command is quotes and backslashes more often than not; an unparsable
# answer is a hook that silently said nothing. And a session id is a file
# name here — one with slashes must not become a path.
section "loop-guard — quoting survives the echo, a session id cannot be a path"
LOOPQ="$TMP/loopq"; mkdir -p "$LOOPQ"
loopq_run() { printf '%s' "$1" | KEEL_LOOP_STATE_DIR="$LOOPQ" bash "$HK/loop-guard.sh" 2>/dev/null; }
loopq_pay="$(loop_var 'session=quote-sess' 'command=printf "%s\\n" "a \"quoted\" \\ backslash" | grep -q zzz')"
loopq_run "$loopq_pay" >/dev/null; loopq_run "$loopq_pay" >/dev/null
loopq_out="$(loopq_run "$loopq_pay")"
has 'failed 3 times' "$loopq_out" "the third failure of a quoted command fires"
printf '%s' "$loopq_out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if "additionalContext" in d["hookSpecificOutput"] else 1)' \
  && ok || bad "the answer for a command with quotes and backslashes is valid JSON (got: $loopq_out)"
loops_pay="$(loop_var 'session=../../etc/evil' )"
loops_out="$(loopq_run "$loops_pay")"
[ "$loops_out" = "{}" ] && ok || bad "a slashed session id still counts quietly (got: $loops_out)"
[ -f "$LOOPQ/keel-loop-guard-.._.._etc_evil" ] && ok || bad "a session id with slashes is sanitised into one file name"
[ ! -e "$LOOPQ/../etc/evil" ] && ok || bad "no path escapes the state directory"
