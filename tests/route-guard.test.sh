#!/usr/bin/env bash
# Tests for hooks/route-guard.sh: feeds crafted PreToolUse payloads with
# fixture JSONL transcripts and asserts the exit code (and stderr, where the
# message content matters). Exit 2 = refused, exit 0 = allowed.
set -u

HOOK="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)/hooks/route-guard.sh"
fail=0

TMPDIR="$(mktemp -d)"
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

MODE_TIERED="CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=1 EVAL_CLAUDE_1337_TIERED=0"
MODE_OFF="CLAUDE_PLUGIN_OPTION_TIERED=false CLAUDE_1337_TIERED=0 EVAL_CLAUDE_1337_TIERED=0"

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

# Transcript builders: everything appends, in order.
t_tool() { printf '%s\n' "$1" >> "$2"; }

# A Bash tool_result carrying route.py's marker line, embedded in its
# stdout, the way it really lands in a transcript.
marker_line() { # steps-json (compact array)
  jq -c -n --arg steps "$1" \
    '{model:"jev-1.12", floor:0.5} + {steps:($steps|fromjson)}
     | "1337-tier-route: " + (tostring)' \
  | jq -c -n --argjson body "$(cat)" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",content:$body}]}}'
}

# An Agent (or Task) dispatch to 1337:builder at a given model.
agent_line() { # tool-name subagent_type model
  jq -c -n --arg tool "$1" --arg s "$2" --arg m "$3" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:$tool,input:{subagent_type:$s,model:$m}}]}}'
}

payload() { # subagent_type model transcript_path session_id
  jq -c -n --arg s "$1" --arg m "$2" --arg tr "$3" --arg sid "$4" \
    '{tool_name:"Agent",tool_input:{subagent_type:$s,model:$m},transcript_path:$tr,session_id:$sid}'
}

STEPS3='[{"id":1,"tier":"haiku","confidence":0.8,"escalated":false},{"id":2,"tier":"sonnet","confidence":0.7,"escalated":false},{"id":3,"tier":"opus","confidence":0.6,"escalated":false}]'

# --- case 1: no marker anywhere -> refused ---
sid1="rg-1"; tr1="$TMPDIR/tr1.jsonl"
t_tool "$(agent_line Agent 1337:scout haiku)" "$tr1"
check_grep 2 'no tier routing this session' "no marker: refused, names the router fix" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr1" "$sid1")"

# --- case 2: marker with three steps, zero dispatches after it -> allowed at a routed tier ---
sid2="rg-2"; tr2="$TMPDIR/tr2.jsonl"
t_tool "$(marker_line "$STEPS3")" "$tr2"
check 0 "marker present, no dispatches yet: allowed at a routed tier" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr2" "$sid2")"

# --- case 3: three routed steps, three dispatches after the marker -> a fourth refused ---
sid3="rg-3"; tr3="$TMPDIR/tr3.jsonl"
t_tool "$(marker_line "$STEPS3")" "$tr3"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr3"
t_tool "$(agent_line Agent 1337:builder sonnet)" "$tr3"
t_tool "$(agent_line Agent 1337:builder opus)" "$tr3"
check_grep 2 'already has a 1337:builder dispatch' "budget spent: fourth dispatch refused" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr3" "$sid3")"

# --- case 4: a dispatch whose model is not among the remaining tiers -> refused, names remaining ---
sid4="rg-4"; tr4="$TMPDIR/tr4.jsonl"
t_tool "$(marker_line "$STEPS3")" "$tr4"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr4"
check_grep 2 'sonnet, opus' "wrong tier: refused, message names remaining tiers" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr4" "$sid4")"
check 0 "wrong-tier case: a routed remaining tier (sonnet) is allowed" \
  "$MODE_TIERED" "$(payload 1337:builder sonnet "$tr4" "$sid4")"

# --- case 5: a second marker later in the transcript resets the budget ---
sid5="rg-5"; tr5="$TMPDIR/tr5.jsonl"
t_tool "$(marker_line "$STEPS3")" "$tr5"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr5"
t_tool "$(agent_line Agent 1337:builder sonnet)" "$tr5"
t_tool "$(agent_line Agent 1337:builder opus)" "$tr5"
t_tool "$(marker_line '[{"id":1,"tier":"haiku","confidence":0.9,"escalated":false}]')" "$tr5"
check 0 "second marker resets the budget: fresh dispatch at its tier allowed" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr5" "$sid5")"
check_grep 2 'still owes this step (haiku)' "second marker: the old (spent) route no longer applies" \
  "$MODE_TIERED" "$(payload 1337:builder sonnet "$tr5" "$sid5")"

# --- case 6: non-builder agent type -> allowed regardless of transcript state ---
sid6="rg-6"
check 0 "non-builder subagent_type: allowed" \
  "$MODE_TIERED" "$(payload 1337:scout haiku "$TMPDIR/does-not-exist.jsonl" "$sid6")"

# --- case 7: tiered mode off -> allowed ---
sid7="rg-7"
check 0 "tiered mode off: allowed even with no marker" \
  "$MODE_OFF" "$(payload 1337:builder haiku "$tr1" "$sid7")"

# --- case 8: Task tool name matches too ---
sid8="rg-8"; tr8="$TMPDIR/tr8.jsonl"
t_tool "$(marker_line "$STEPS3")" "$tr8"
out=$(printf '%s' "$(jq -c -n --arg s 1337:builder --arg m haiku --arg tr "$tr8" --arg sid "$sid8" '{tool_name:"Task",tool_input:{subagent_type:$s,model:$m},transcript_path:$tr,session_id:$sid}')" \
  | env $MODE_TIERED "$HOOK" 2>&1 >/dev/null)
got=$?
if [ "$got" -eq 0 ]; then
  printf 'ok   %s\n' "Task tool name recognized: allowed at a routed tier"
else
  printf 'FAIL %s (exit %s; stderr: %s)\n' "Task tool name recognized" "$got" "$out"; fail=1
fi

exit $fail
