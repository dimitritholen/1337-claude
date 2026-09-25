#!/usr/bin/env bash
# Tests for hooks/terse-governor.sh: feeds crafted Stop payloads with fixture
# JSONL transcripts and asserts the exit code, plus the overrun marker it
# writes for an over-budget reply, and the --nudge (UserPromptSubmit) mode
# that surfaces and clears that marker. The Stop hook never blocks any more
# (exit 2 was removed: the reply's tokens are already spent, a resend only
# adds more); every case here expects exit 0.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/terse-governor.sh"
fail=0
work="$(mktemp -d)"
export TMPDIR="$work"
MARKER="$work/claude-1337-terse-overrun-t"
trap 'rm -rf "$work"' EXIT

check() { # expected-exit description transcript
  local got
  printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":false}' "$3" | \
    "$HOOK" 2>/dev/null
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'ok   %s\n' "$2"; else printf 'FAIL %s (exit %s, want %s)\n' "$2" "$got" "$1"; fail=1; fi
}

assert_marker_written() { # description
  if [ -f "$MARKER" ] && grep -qE '^[0-9]+ [0-9]+$' "$MARKER"; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s (marker missing or malformed)\n' "$1"; fail=1
  fi
  rm -f "$MARKER"
}

assert_no_marker() { # description
  if [ -e "$MARKER" ]; then
    printf 'FAIL %s (marker written, should not be)\n' "$1"; fail=1
    rm -f "$MARKER"
  else
    printf 'ok   %s\n' "$1"
  fi
}

unset CLAUDE_1337_TERSE CLAUDE_PLUGIN_OPTION_TERSE

# Transcript builders: everything appends, in order.
t_user()  { printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":%s}]}}\n' "$(jq -Rs . <<<"$1")" >> "$2"; }
t_reply() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(jq -Rs . <<<"$1")" >> "$2"; }
t_tool()  { printf '%s\n' "$1" >> "$2"; }
tool_call='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}'
tool_result='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"file1\nfile2"}]}}'

verbose="I took a look at the login bug and it turned out that the session cookie was never actually being renewed on page reload, so I went ahead and fixed the renewal logic and everything should be working great now, let me know if anything else comes up"
substantive="The auth module had a bug where sessions never renewed. I rewrote the renewal check, ran the suite, and all 12 tests pass now."
steps="First, back up the database.
1. Stop the service.
2. Apply the migration.
3. Restart the service."
security_note="I patched the endpoint: it was missing an auth check and any signed-in user could read another user's data, a real security hole now closed."

# on (default) mode.
export CLAUDE_PLUGIN_OPTION_TERSE=on

tr="$work/tr1"; t_user "fix the login bug" "$tr"; t_tool "$tool_call" "$tr"; t_tool "$tool_result" "$tr"; t_reply "$verbose" "$tr"
check 0 "verbose reply after a command: allowed" "$tr"
assert_marker_written "verbose reply after a command: marker written"

tr="$work/tr2"; t_user "fix the login bug" "$tr"; t_reply "Fixed; tests pass." "$tr"
check 0 "short reply: allowed" "$tr"
assert_no_marker "short reply: no marker"

tr="$work/tr3"; t_user "why is login failing?" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked why: exempt" "$tr"
assert_no_marker "user asked why: no marker"

tr="$work/tr4"; t_user "fix the login bug" "$tr"; t_reply "$substantive" "$tr"
check 0 "substance under budget: allowed" "$tr"

tr="$work/tr5"; t_user "fix the login bug" "$tr"; t_reply '```bash
rm -rf build/
```
fences do not count' "$tr"
check 0 "code fences excluded from count" "$tr"

# Newly waived words/phrases.
tr="$work/tr11"; t_user "review this" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked for review: exempt" "$tr"

tr="$work/tr12"; t_user "give me recommendations" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked for recommendations: exempt" "$tr"

tr="$work/tr13"; t_user "recommend changes" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked for recommend: exempt" "$tr"

tr="$work/tr14"; t_user "list the items" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked for list: exempt" "$tr"

tr="$work/tr15"; t_user "summarize this" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked for summarize: exempt" "$tr"

tr="$work/tr16"; t_user "summarise this" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked for summarise: exempt" "$tr"

tr="$work/tr17"; t_user "can you compare options" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked for comparison: exempt" "$tr"

tr="$work/tr18"; t_user "what should I do" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked what should: exempt" "$tr"

tr="$work/tr19"; t_user "listen to this" "$tr"; t_reply "$verbose" "$tr"
check 0 "listen (not a waived word): allowed" "$tr"
assert_marker_written "listen (not a waived word): marker written"

tr="$work/tr20"; t_user "from my playlist" "$tr"; t_reply "$verbose" "$tr"
check 0 "playlist (not a waived word): allowed" "$tr"
assert_marker_written "playlist (not a waived word): marker written"

# Reply-side exemptions: an ordered list of steps, or security/irreversible
# wording, is never marked even over budget.
tr="$work/tr21"; t_user "clean this up" "$tr"; t_reply "$steps" "$tr"
check 0 "ordered list of steps: allowed" "$tr"
assert_no_marker "ordered list of steps: exempt from marking"

tr="$work/tr22"; t_user "fix the endpoint" "$tr"; t_reply "$security_note" "$tr"
check 0 "security wording: allowed" "$tr"
assert_no_marker "security wording: exempt from marking"

# The /config option controls the mode.
export CLAUDE_PLUGIN_OPTION_TERSE=off
tr="$work/tr6"; t_user "fix the login bug" "$tr"; t_reply "$verbose" "$tr"
check 0 "mode off: allowed" "$tr"
assert_no_marker "mode off: never marks"

export CLAUDE_PLUGIN_OPTION_TERSE=hard
tr="$work/tr7"; t_user "fix the login bug" "$tr"; t_reply "$substantive" "$tr"
check 0 "hard mode: 27-word reply allowed" "$tr"
assert_marker_written "hard mode: marker written at the 12-word budget"
check 0 "missing transcript: allowed" "$work/does-not-exist"
assert_no_marker "missing transcript: no marker"

# An unset, empty or unknown option means the default, never a silent off.
tr="$work/tr10"; t_user "fix the login bug" "$tr"; t_reply "$verbose" "$tr"
unset CLAUDE_PLUGIN_OPTION_TERSE
check 0 "option unset: defaults to on, allowed" "$tr"
assert_marker_written "option unset: marker written"
export CLAUDE_PLUGIN_OPTION_TERSE=
check 0 "empty option: defaults to on, allowed" "$tr"
assert_marker_written "empty option: marker written"
export CLAUDE_PLUGIN_OPTION_TERSE=bogus
check 0 "unknown option: defaults to on, allowed" "$tr"
assert_marker_written "unknown option: marker written"
export CLAUDE_PLUGIN_OPTION_TERSE=OFF
check 0 "option OFF (uppercase): allowed" "$tr"
assert_no_marker "option OFF (uppercase): lowercased to off"

# Env overrides the option.
export CLAUDE_PLUGIN_OPTION_TERSE=off
tr="$work/tr8"; t_user "fix the login bug" "$tr"; t_reply "$verbose" "$tr"
printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":false}' "$tr" | \
  CLAUDE_1337_TERSE=hard "$HOOK" 2>/dev/null
[ $? -eq 0 ] && printf 'ok   env hard overrides option off\n' || { printf 'FAIL env override\n'; fail=1; }
assert_marker_written "env hard overrides option off: marker written"

printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":false}' "$tr" | \
  CLAUDE_1337_TERSE=0 "$HOOK" 2>/dev/null
[ $? -eq 0 ] && printf 'ok   env 0 disables\n' || { printf 'FAIL env disable\n'; fail=1; }
assert_no_marker "env 0 disables: no marker"

# Loop guard: stop_hook_active never measures (so never marks).
printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":true}' "$tr" | \
  CLAUDE_1337_TERSE=hard "$HOOK" 2>/dev/null
[ $? -eq 0 ] && printf 'ok   stop_hook_active: allowed\n' || { printf 'FAIL loop guard\n'; fail=1; }
assert_no_marker "stop_hook_active: no marker"

# --nudge (UserPromptSubmit): surfaces and clears a marker exactly once.
export CLAUDE_PLUGIN_OPTION_TERSE=on
printf '27 12\n' > "$MARKER"
out=$(printf '{"session_id":"t","prompt":"go on"}' | "$HOOK" --nudge)
case "$out" in
  "Terse: your last reply was 27 words (budget 12). Keep this one within budget.")
    printf 'ok   nudge: prints the marker once\n' ;;
  *) printf 'FAIL nudge: unexpected output %s\n' "$out"; fail=1 ;;
esac
assert_no_marker "nudge: clears the marker after printing"

out=$(printf '{"session_id":"t","prompt":"go on"}' | "$HOOK" --nudge)
[ -z "$out" ] && printf 'ok   nudge: silent with no marker\n' || { printf 'FAIL nudge should be silent, got: %s\n' "$out"; fail=1; }

# --nudge with mode off: silent, and clears a stale marker.
export CLAUDE_PLUGIN_OPTION_TERSE=off
printf '27 12\n' > "$MARKER"
out=$(printf '{"session_id":"t","prompt":"go on"}' | "$HOOK" --nudge)
[ -z "$out" ] && printf 'ok   nudge: silent when mode off\n' || { printf 'FAIL nudge mode off should be silent, got: %s\n' "$out"; fail=1; }
assert_no_marker "nudge: mode off also clears a stale marker"

# Path traversal: sanitize session_id so path traversal chars do not escape $TMPDIR
export CLAUDE_PLUGIN_OPTION_TERSE=on
tr="$work/tr23"; t_user "fix the login bug" "$tr"; t_reply "$verbose" "$tr"
printf '{"session_id":"../..","transcript_path":"%s","stop_hook_active":false}' "$tr" | \
  "$HOOK" 2>/dev/null
# Marker should land at the sanitized session_id (all non-alphanumeric removed, becomes "default")
[ -f "$work/claude-1337-terse-overrun-default" ] && printf 'ok   path traversal: session_id sanitized to default\n' || { printf 'FAIL path traversal: marker not found\n'; fail=1; }
rm -f "$work/claude-1337-terse-overrun-default"

exit $fail
