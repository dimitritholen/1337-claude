#!/usr/bin/env bash
# Tests for hooks/read-cap.sh: feeds crafted PreToolUse payloads and asserts
# the exit code. Exit 2 = refused, exit 0 = allowed.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/read-cap.sh"
fail=0

STATEDIR="$(mktemp -d)"
export TMPDIR="$STATEDIR"
trap 'rm -rf "$STATEDIR"' EXIT

sid="test-$$"

check() { # expected-exit description payload
  local got out
  out=$(printf '%s' "$3" | "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'ok   %s\n' "$2"; else printf 'FAIL %s (exit %s, want %s)\n' "$2" "$got" "$1"; fail=1; fi
  printf '%s' "$out"
}

check_grep() { # expected-exit want-in-stderr description payload
  local out
  out=$(printf '%s' "$4" | "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ] && printf '%s' "$out" | grep -q "$2"; then
    printf 'ok   %s\n' "$3"
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$3" "$got" "$1" "$out"; fail=1
  fi
}

readcall() { # session prompt_id extra
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"Read","tool_input":{"file_path":"/repo/a.py"}%s}' "$1" "$2" "${3:-}"
}
grepcall() { # session prompt_id tool extra
  printf '{"session_id":"%s","prompt_id":"%s","tool_name":"%s","tool_input":{"pattern":"x"}%s}' "$1" "$2" "$3" "${4:-}"
}

# a. mode off: Read passes.
unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR CLAUDE_1337_ORCHESTRATOR CLAUDE_1337_READ_CAP CLAUDE_1337_GREP_CAP
check 0 "mode off: read allowed" "$(readcall "$sid" p1)"

export CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=true

# b/c. first and second Read in prompt p1.
check 0 "mode on: first read in p1" "$(readcall "$sid" p1)"
check_grep 2 'Read #2' "mode on: second read in p1 refused" "$(readcall "$sid" p1)"

# d. Read in prompt p2: new turn.
check 0 "new prompt p2: read allowed" "$(readcall "$sid" p2)"

# e. Grep, Glob in p2 pass; third (Grep) refused.
check 0 "p2: first grep allowed" "$(grepcall "$sid" p2 Grep)"
check 0 "p2: first glob allowed (second grep-kind call)" "$(grepcall "$sid" p2 Glob)"
check_grep 2 'Grep/Glob #3' "p2: third grep-kind call refused" "$(grepcall "$sid" p2 Grep)"

# f. Read in p2 with agent_id after cap reached: always allowed.
check 0 "p2: subagent read bypasses cap" "$(readcall "$sid" p2 ',"agent_id":"abc"')"

# g. CLAUDE_1337_READ_CAP=0 disables entirely: third read in p1 passes.
CLAUDE_1337_READ_CAP=0 check 0 "READ_CAP=0: third read in p1 allowed" "$(readcall "$sid" p1)"

# g-grep. CLAUDE_1337_GREP_CAP=0 disables Grep/Glob cap: three grep-kind calls in fresh prompt p4 all pass.
CLAUDE_1337_GREP_CAP=0 check 0 "GREP_CAP=0: first grep in p4 allowed" "$(grepcall "$sid" p4 Grep)"
CLAUDE_1337_GREP_CAP=0 check 0 "GREP_CAP=0: second grep in p4 allowed" "$(grepcall "$sid" p4 Grep)"
CLAUDE_1337_GREP_CAP=0 check 0 "GREP_CAP=0: third grep in p4 allowed" "$(grepcall "$sid" p4 Grep)"

# h. CLAUDE_1337_READ_CAP=3: reads 2 and 3 in fresh prompt p3 pass, fourth refused.
CLAUDE_1337_READ_CAP=3 check 0 "READ_CAP=3: read 1 in p3" "$(readcall "$sid" p3)"
CLAUDE_1337_READ_CAP=3 check 0 "READ_CAP=3: read 2 in p3" "$(readcall "$sid" p3)"
CLAUDE_1337_READ_CAP=3 check 0 "READ_CAP=3: read 3 in p3" "$(readcall "$sid" p3)"
CLAUDE_1337_READ_CAP=3 check_grep 2 'Read #4' "READ_CAP=3: read 4 in p3 refused" "$(readcall "$sid" p3)"

# i. no prompt_id, fallback to transcript's last user message.
transcript="$STATEDIR/transcript-$sid.jsonl"
printf '{"type":"user","message":{"content":"hello there"}}\n' > "$transcript"
sid_t="$sid-transcript"
read_noprompt=$(printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"/repo/a.py"},"transcript_path":"%s"}' "$sid_t" "$transcript")
check 0 "no prompt_id: first read via transcript fallback" "$read_noprompt"
check_grep 2 'Read #2' "no prompt_id: second read via transcript fallback refused" "$read_noprompt"

# j. six parallel Reads in a fresh prompt with cap 1: exactly one allowed.
exits="$STATEDIR/exits-p5"
: > "$exits"
for _ in 1 2 3 4 5 6; do
  (
    printf '%s' "$(readcall "$sid" p5)" | CLAUDE_1337_READ_CAP=1 "$HOOK" >/dev/null 2>&1
    printf 'exit=%s\n' "$?" >> "$exits"
  ) &
done
wait
allowed=$(grep -c -F -x 'exit=0' "$exits")
refused=$(grep -c -F -x 'exit=2' "$exits")
if [ "$allowed" -eq 1 ] && [ "$refused" -eq 5 ]; then
  printf 'ok   parallel: one read allowed, five refused\n'
else
  printf 'FAIL parallel: %s allowed, %s refused (want 1 and 5; exits: %s)\n' "$allowed" "$refused" "$(tr '\n' ' ' < "$exits")"; fail=1
fi

# k. a stale lock left behind does not block the next Read.
sid_lock="$sid-stalelock"
stale_lock="$STATEDIR/claude-1337-read-cap-$sid_lock.lock"
mkdir "$stale_lock"
touch -d '-10 seconds' "$stale_lock"
check 0 "stale lock: first read in fresh prompt allowed" "$(readcall "$sid_lock" p1)"

# l. Edit tool_name passes through untouched.
edit_payload=$(printf '{"session_id":"%s","prompt_id":"p1","tool_name":"Edit","tool_input":{"file_path":"/repo/a.py"}}' "$sid")
check 0 "Edit tool_name not counted" "$edit_payload"

unset CLAUDE_1337_READ_CAP CLAUDE_1337_GREP_CAP
unset CLAUDE_PLUGIN_OPTION_ORCHESTRATOR

exit $fail
