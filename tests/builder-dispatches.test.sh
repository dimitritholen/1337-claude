#!/usr/bin/env bash
# Tests for hooks/lib/builder-dispatches.jq: feeds fixture transcript
# slices through the filter (its documented calling convention: `jq -R -s
# --argjson offset N -f`) and asserts which 1337:builder dispatches survive.
set -u

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
FILTER="$REPO_ROOT/hooks/lib/builder-dispatches.jq"
fail=0

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Transcript line builders: everything appends, in order, one JSONL line
# per call.
use_line() { # tool-name id model subagent_type
  jq -c -n --arg tool "$1" --arg id "$2" --arg m "$3" --arg s "$4" \
    '{type:"assistant",message:{role:"assistant",content:[
      {type:"tool_use",id:$id,name:$tool,input:{subagent_type:$s,model:$m}}]}}'
}

# A tool_result that ran normally (the shape a launched agent really comes
# back with: content is an array of {type:text}, no is_error).
ok_result_line() { # tool_use_id
  jq -c -n --arg id "$1" \
    '{type:"user",message:{role:"user",content:[
      {type:"tool_result",tool_use_id:$id,
       content:[{type:"text",text:"Async agent launched successfully. (This too...)"}]}]}}'
}

# A tool_result the agent itself returned as an error (NOT a hook refusal:
# content is still an array of {type:text}, is_error true).
own_error_result_line() { # tool_use_id
  jq -c -n --arg id "$1" \
    '{type:"user",message:{role:"user",content:[
      {type:"tool_result",tool_use_id:$id,is_error:true,
       content:[{type:"text",text:"builder crashed: out of disk"}]}]}}'
}

# A tool_result shaped exactly like a PreToolUse hook refusal (content a
# plain string, is_error true) — the shape pinned from a real transcript.
refusal_result_line() { # tool_use_id tool-name
  jq -c -n --arg id "$1" --arg tool "$2" \
    '{type:"user",message:{role:"user",content:[
      {type:"tool_result",tool_use_id:$id,is_error:true,
       content:("PreToolUse:" + $tool + " hook error: [\"/path/hook.sh\"]: blocked (reason)")}]}}'
}

run_filter() { # transcript-text offset
  printf '%s' "$1" | jq -R -s --argjson offset "${2:-0}" -f "$FILTER"
}

check_ids() { # description transcript-text expected-ids-json(array) [offset]
  local desc="$1" text="$2" want="$3" offset="${4:-0}" got_ids got
  got=$(run_filter "$text" "$offset") || { printf 'FAIL %s (jq error)\n' "$desc"; fail=1; return; }
  got_ids=$(printf '%s' "$got" | jq -c '[.[].id]' 2>/dev/null)
  if [ "$got_ids" = "$want" ]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s (got ids %s, want %s; full: %s)\n' "$desc" "$got_ids" "$want" "$got"
    fail=1
  fi
}

# --- one ran dispatch, kept ------------------------------------------------
t=$(printf '%s\n%s\n' "$(use_line Agent id1 haiku 1337:builder)" "$(ok_result_line id1)")
check_ids "ran dispatch kept" "$t" '["id1"]'

# --- one hook-refused dispatch, dropped ------------------------------------
t=$(printf '%s\n%s\n' "$(use_line Agent id1 haiku 1337:builder)" "$(refusal_result_line id1 Agent)")
check_ids "hook-refused dispatch dropped" "$t" '[]'

# --- pending (no tool_result yet), kept ------------------------------------
t=$(printf '%s\n' "$(use_line Agent id1 haiku 1337:builder)")
check_ids "pending dispatch (no result yet) kept" "$t" '["id1"]'

# --- ran then errored on its own (not a hook refusal), kept ----------------
t=$(printf '%s\n%s\n' "$(use_line Agent id1 opus 1337:builder)" "$(own_error_result_line id1)")
check_ids "ran-then-self-errored dispatch kept" "$t" '["id1"]'

# --- non-builder Agent call ignored ----------------------------------------
t=$(printf '%s\n%s\n' "$(use_line Agent id1 haiku 1337:scout)" "$(ok_result_line id1)")
check_ids "non-builder subagent_type ignored" "$t" '[]'

# --- Task tool name handled the same as Agent ------------------------------
t=$(printf '%s\n%s\n' "$(use_line Task id1 sonnet 1337:builder)" "$(ok_result_line id1)")
check_ids "Task-named dispatch kept when it ran" "$t" '["id1"]'

t=$(printf '%s\n%s\n' "$(use_line Task id1 sonnet 1337:builder)" "$(refusal_result_line id1 Task)")
check_ids "Task-named hook-refused dispatch dropped" "$t" '[]'

# --- refused, then a later successful dispatch: only the later one kept ---
t=$(printf '%s\n%s\n%s\n%s\n' \
  "$(use_line Agent id1 haiku 1337:builder)" \
  "$(refusal_result_line id1 Agent)" \
  "$(use_line Agent id2 sonnet 1337:builder)" \
  "$(ok_result_line id2)")
check_ids "refused then later successful dispatch: only later kept" "$t" '["id2"]'

# --- offset is added back into the reported line number --------------------
t="$(use_line Agent id1 haiku 1337:builder)"
got_line=$(run_filter "$t" 41 | jq -r '.[0].line')
if [ "$got_line" = "42" ]; then
  printf 'ok   %s\n' "offset added back into line number"
else
  printf 'FAIL %s (got line %s, want 42)\n' "offset added back into line number" "$got_line"
  fail=1
fi

# --- pending flag and message_id emitted (#781) ----------------------------
# Two tool_uses of one assistant message (same message.id, one per line);
# the first came back, the second is still pending.
msg_use_line() { # message-id tool-use-id
  jq -c -n --arg mid "$1" --arg id "$2" \
    '{type:"assistant",message:{id:$mid,role:"assistant",content:[
      {type:"tool_use",id:$id,name:"Agent",input:{subagent_type:"1337:builder",model:"sonnet"}}]}}'
}
t=$(printf '%s\n%s\n%s\n' "$(msg_use_line m1 id1)" "$(ok_result_line id1)" "$(msg_use_line m1 id2)")
got=$(run_filter "$t" 0 | jq -c '[.[] | {id, pending, message_id}]')
want='[{"id":"id1","pending":false,"message_id":"m1"},{"id":"id2","pending":true,"message_id":"m1"}]'
if [ "$got" = "$want" ]; then
  printf 'ok   %s\n' "pending flag and message_id emitted"
else
  printf 'FAIL %s (got %s, want %s)\n' "pending flag and message_id emitted" "$got" "$want"
  fail=1
fi

# A line with no message.id gives message_id null, not a crash.
got=$(run_filter "$(use_line Agent id1 haiku 1337:builder)" 0 | jq -c '[.[] | {pending, message_id}]')
if [ "$got" = '[{"pending":true,"message_id":null}]' ]; then
  printf 'ok   %s\n' "missing message.id gives message_id null"
else
  printf 'FAIL %s (got %s)\n' "missing message.id gives message_id null" "$got"
  fail=1
fi

exit $fail
