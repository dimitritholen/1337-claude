#!/usr/bin/env bash
# Tests for hooks/dispatch-nudge.sh: feeds crafted Stop payloads with fixture
# JSONL transcripts and asserts the exit code. Exit 2 = nudge (stderr message,
# flag file written), exit 0 = silent.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/dispatch-nudge.sh"
fail=0

TMPDIR="$(mktemp -d)"
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

# Guard against the developer's own environment leaking the nudge switches.
unset CLAUDE_1337_DISPATCH_NUDGE CLAUDE_1337_DISPATCH_NUDGE_WRITES

# Mode: all six on/off knobs set explicitly every time, per the contract.
MODE_ORCH="CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=false CLAUDE_1337_ORCHESTRATOR=1 EVAL_CLAUDE_1337_ORCHESTRATOR=0 CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=0 EVAL_CLAUDE_1337_TIERED=0"
MODE_TIERED="CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=false CLAUDE_1337_ORCHESTRATOR=0 EVAL_CLAUDE_1337_ORCHESTRATOR=0 CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=1 EVAL_CLAUDE_1337_TIERED=0"
MODE_OFF="CLAUDE_PLUGIN_OPTION_ORCHESTRATOR=false CLAUDE_1337_ORCHESTRATOR=0 EVAL_CLAUDE_1337_ORCHESTRATOR=0 CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=0 EVAL_CLAUDE_1337_TIERED=0"

check() { # expected-exit description extra-env payload
  local got out
  out=$(printf '%s' "$4" | env $3 "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ]; then
    printf 'ok   %s\n' "$2"
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$2" "$got" "$1" "$out"; fail=1
  fi
}

check_grep() { # expected-exit want-in-stderr description extra-env payload
  local got out
  out=$(printf '%s' "$5" | env $4 "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ] && printf '%s' "$out" | grep -q "$2"; then
    printf 'ok   %s\n' "$3"
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$3" "$got" "$1" "$out"; fail=1
  fi
}

check_grep_not() { # expected-exit want-in-stderr avoid-in-stderr description extra-env payload
  local got out
  out=$(printf '%s' "$6" | env $5 "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$1" ] && printf '%s' "$out" | grep -q "$2" && ! printf '%s' "$out" | grep -q "$3"; then
    printf 'ok   %s\n' "$4"
  else
    printf 'FAIL %s (exit %s, want %s; stderr: %s)\n' "$4" "$got" "$1" "$out"; fail=1
  fi
}

# Transcript builders: everything appends, in order.
bash_line() { # command
  jq -c -n --arg cmd "$1" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:$cmd}}]}}'
}
write_line() { # file_path content
  jq -c -n --arg p "$1" --arg c "$2" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Write",input:{file_path:$p,content:$c}}]}}'
}
edit_line() { # file_path new_string
  jq -c -n --arg p "$1" --arg n "$2" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Edit",input:{file_path:$p,new_string:$n}}]}}'
}
agent_line() { # subagent_type
  jq -c -n --arg s "$1" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Agent",input:{subagent_type:$s}}]}}'
}
read_line() {
  jq -c -n '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Read",input:{file_path:"/repo/a.py"}}]}}'
}
t_tool() { printf '%s\n' "$1" >> "$2"; }

payload() { # session_id transcript_path stop_hook_active
  printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s}' "$1" "$2" "${3:-false}"
}

heredoc_write() { # target_file body
  printf '%s\n%s\n%s' "cat > $1 <<'EOF'" "$2" "EOF"
}

content_large=""
for i in $(seq 1 60); do content_large="${content_large}x = $i"$'\n'; done
new_string_small=$'x = 1\ny = 2'

# --- case 1: three Bash heredoc writes into .py files, no Agent, orchestrator on ---
sid1="dn-1"; tr1="$TMPDIR/tr1.jsonl"
t_tool "$(bash_line "$(heredoc_write /tmp/work/app1.py 'print(1)')")" "$tr1"
t_tool "$(bash_line "$(heredoc_write /tmp/work/app2.py 'print(2)')")" "$tr1"
t_tool "$(bash_line "$(heredoc_write /tmp/work/app3.py 'print(3)')")" "$tr1"
check_grep_not 2 '3 code steps ran in the main session, none through 1337:builder' 'tiered routing' \
  "orchestrator only: nudges with plain message, no tiered mention" "$MODE_ORCH" "$(payload "$sid1" "$tr1")"

# --- case 2: same transcript, tiered on and orchestrator off ---
sid2="dn-2"
check_grep 2 'tiered routing never ran' \
  "tiered on: mentions tiered routing never ran" "$MODE_TIERED" "$(payload "$sid2" "$tr1")"

# --- case 3: same three writes plus a 1337:builder dispatch ---
sid3="dn-3"; tr3="$TMPDIR/tr3.jsonl"
cat "$tr1" > "$tr3"
t_tool "$(agent_line "1337:builder")" "$tr3"
check 0 "dispatch present: silent" "$MODE_ORCH" "$(payload "$sid3" "$tr3")"

# --- case 4: two writes only ---
sid4="dn-4"; tr4="$TMPDIR/tr4.jsonl"
t_tool "$(bash_line "$(heredoc_write /tmp/work/b1.py 'print(1)')")" "$tr4"
t_tool "$(bash_line "$(heredoc_write /tmp/work/b2.py 'print(2)')")" "$tr4"
check 0 "two writes: under threshold, silent" "$MODE_ORCH" "$(payload "$sid4" "$tr4")"

# --- case 5: three writes but CLAUDE_1337_DISPATCH_NUDGE=0 ---
sid5="dn-5"
check 0 "CLAUDE_1337_DISPATCH_NUDGE=0: silent" "$MODE_ORCH CLAUDE_1337_DISPATCH_NUDGE=0" "$(payload "$sid5" "$tr1")"

# --- case 6: three writes, all six mode vars off ---
sid6="dn-6"
check 0 "all modes off: silent" "$MODE_OFF" "$(payload "$sid6" "$tr1")"

# --- case 7: three writes, stop_hook_active true ---
sid7="dn-7"
check 0 "stop_hook_active true: silent" "$MODE_ORCH" "$(payload "$sid7" "$tr1" true)"

# --- case 8: same session_id as case 1 fed again ---
check 0 "flag file present: second run same session silent" "$MODE_ORCH" "$(payload "$sid1" "$tr1")"
flag_file="$TMPDIR/claude-1337-dispatch-nudge-$sid1"
if [ -e "$flag_file" ]; then
  printf 'ok   flag file exists after nudge\n'
else
  printf 'FAIL flag file missing: %s\n' "$flag_file"; fail=1
fi

# --- case 9: three writes plus a 1337:scout dispatch only ---
sid9="dn-9"; tr9="$TMPDIR/tr9.jsonl"
cat "$tr1" > "$tr9"
t_tool "$(agent_line "1337:scout")" "$tr9"
check_grep 2 '3 code steps' "scout dispatch does not count: still nudges" "$MODE_ORCH" "$(payload "$sid9" "$tr9")"

# --- case 10: mixed large Write, python heredoc, sed -i ---
sid10="dn-10"; tr10="$TMPDIR/tr10.jsonl"
t_tool "$(write_line /tmp/work/a.py "$content_large")" "$tr10"
python_cmd=$(printf '%s\n%s\n%s' "python3 - <<'EOF'" "print(1)" "EOF")
t_tool "$(bash_line "$python_cmd")" "$tr10"
t_tool "$(bash_line "sed -i 's/a/b/' lib/x.sh")" "$tr10"
check_grep 2 '3 code steps' "mixed Write/heredoc/sed-i: nudges" "$MODE_ORCH" "$(payload "$sid10" "$tr10")"

# --- case 11: non-counting noise plus two real writes ---
sid11="dn-11"; tr11="$TMPDIR/tr11.jsonl"
t_tool "$(edit_line /tmp/work/a.py "$new_string_small")" "$tr11"
t_tool "$(bash_line "ls -la")" "$tr11"
notes_cmd=$(printf '%s\n%s\n%s' "cat > /tmp/notes.txt <<'EOF'" "hello" "EOF")
t_tool "$(bash_line "$notes_cmd")" "$tr11"
t_tool "$(read_line)" "$tr11"
t_tool "$(bash_line "$(heredoc_write /tmp/work/c1.py 'print(1)')")" "$tr11"
t_tool "$(bash_line "$(heredoc_write /tmp/work/c2.py 'print(2)')")" "$tr11"
check 0 "noise ignored, only 2 real writes: silent" "$MODE_ORCH" "$(payload "$sid11" "$tr11")"

# --- case 12: CLAUDE_1337_DISPATCH_NUDGE_WRITES=2 with two writes ---
sid12="dn-12"; tr12="$TMPDIR/tr12.jsonl"
t_tool "$(bash_line "$(heredoc_write /tmp/work/d1.py 'print(1)')")" "$tr12"
t_tool "$(bash_line "$(heredoc_write /tmp/work/d2.py 'print(2)')")" "$tr12"
check 2 "CLAUDE_1337_DISPATCH_NUDGE_WRITES=2: nudges at two writes" "$MODE_ORCH CLAUDE_1337_DISPATCH_NUDGE_WRITES=2" "$(payload "$sid12" "$tr12")"

# --- case 13: transcript_path pointing at a missing file ---
sid13="dn-13"
check 0 "missing transcript file: silent" "$MODE_ORCH" "$(payload "$sid13" "$TMPDIR/does-not-exist.jsonl")"

# --- case 14: a malformed line among the three writes ---
sid14="dn-14"; tr14="$TMPDIR/tr14.jsonl"
t_tool "$(bash_line "$(heredoc_write /tmp/work/e1.py 'print(1)')")" "$tr14"
t_tool "not json {{{" "$tr14"
t_tool "$(bash_line "$(heredoc_write /tmp/work/e2.py 'print(2)')")" "$tr14"
t_tool "$(bash_line "$(heredoc_write /tmp/work/e3.py 'print(3)')")" "$tr14"
check_grep 2 '3 code steps' "malformed line skipped, still nudges" "$MODE_ORCH" "$(payload "$sid14" "$tr14")"

# --- case 15: drift check on the shared code_ext value ---
guard_ext=$(grep -m1 '^ *code_ext=' /home/dimitri/dev/1337-claude/hooks/orchestrator-guard.sh | sed 's/^[[:space:]]*//')
nudge_ext=$(grep -m1 '^ *code_ext=' /home/dimitri/dev/1337-claude/hooks/dispatch-nudge.sh 2>/dev/null | sed 's/^[[:space:]]*//')
if [ -n "$guard_ext" ] && [ "$guard_ext" = "$nudge_ext" ]; then
  printf 'ok   code_ext matches orchestrator-guard.sh\n'
else
  printf 'FAIL code_ext drift: guard=%s nudge=%s\n' "$guard_ext" "$nudge_ext"; fail=1
fi

exit $fail
