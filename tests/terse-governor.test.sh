#!/usr/bin/env bash
# Tests for hooks/terse-governor.sh: feeds crafted Stop payloads with fixture
# JSONL transcripts and asserts the exit code. Exit 2 = blocked (too chatty),
# exit 0 = allowed.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/terse-governor.sh"
fail=0
work="$(mktemp -d)"
mode_file="$work/mode"
trap 'rm -rf "$work"' EXIT

check() { # expected-exit description transcript
  local got
  printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":false}' "$3" | \
    CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'ok   %s\n' "$2"; else printf 'FAIL %s (exit %s, want %s)\n' "$2" "$got" "$1"; fail=1; fi
}

unset CLAUDE_1337_TERSE

# Transcript builders: everything appends, in order.
t_user()  { printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":%s}]}}\n' "$(jq -Rs . <<<"$1")" >> "$2"; }
t_reply() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(jq -Rs . <<<"$1")" >> "$2"; }
t_tool()  { printf '%s\n' "$1" >> "$2"; }
tool_call='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}'
tool_result='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"file1\nfile2"}]}}'

verbose="I took a look at the login bug and it turned out that the session cookie was never actually being renewed on page reload, so I went ahead and fixed the renewal logic and everything should be working great now, let me know if anything else comes up"
substantive="The auth module had a bug where sessions never renewed. I rewrote the renewal check, ran the suite, and all 12 tests pass now."

# on (default) mode.
printf 'on\n' > "$mode_file"

tr="$work/tr1"; t_user "fix the login bug" "$tr"; t_tool "$tool_call" "$tr"; t_tool "$tool_result" "$tr"; t_reply "$verbose" "$tr"
check 2 "verbose reply after a command: blocked" "$tr"

tr="$work/tr2"; t_user "fix the login bug" "$tr"; t_reply "Fixed; tests pass." "$tr"
check 0 "short reply: allowed" "$tr"

tr="$work/tr3"; t_user "why is login failing?" "$tr"; t_reply "$verbose" "$tr"
check 0 "user asked why: exempt" "$tr"

tr="$work/tr4"; t_user "fix the login bug" "$tr"; t_reply "$substantive" "$tr"
check 0 "substance under budget: allowed" "$tr"

tr="$work/tr5"; t_user "fix the login bug" "$tr"; t_reply '```bash
rm -rf build/
```
fences do not count' "$tr"
check 0 "code fences excluded from count" "$tr"

# Mode file controls.
printf 'off\n' > "$mode_file"
tr="$work/tr6"; t_user "fix the login bug" "$tr"; t_reply "$verbose" "$tr"
check 0 "mode off: allowed" "$tr"

printf 'hard\n' > "$mode_file"
tr="$work/tr7"; t_user "fix the login bug" "$tr"; t_reply "$substantive" "$tr"
check 2 "hard mode blocks 27-word reply" "$tr"
check 0 "missing transcript: allowed" "$work/does-not-exist"

# Env overrides the mode file.
printf 'off\n' > "$mode_file"
tr="$work/tr8"; t_user "fix the login bug" "$tr"; t_reply "$verbose" "$tr"
printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":false}' "$tr" | \
  CLAUDE_1337_TERSE=hard CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null
[ $? -eq 2 ] && printf 'ok   env hard overrides file off\n' || { printf 'FAIL env override\n'; fail=1; }

printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":false}' "$tr" | \
  CLAUDE_1337_TERSE=0 CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null
[ $? -eq 0 ] && printf 'ok   env 0 disables\n' || { printf 'FAIL env disable\n'; fail=1; }

# Loop guard beats everything.
printf '{"session_id":"t","transcript_path":"%s","stop_hook_active":true}' "$tr" | \
  CLAUDE_1337_TERSE=hard CLAUDE_1337_TERSE_FILE="$mode_file" "$HOOK" 2>/dev/null
[ $? -eq 0 ] && printf 'ok   stop_hook_active: allowed\n' || { printf 'FAIL loop guard\n'; fail=1; }

exit $fail
