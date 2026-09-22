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

# A Bash tool_use invoking the tier router (what the deadlock guard greps for).
route_call_line() {
  jq -c -n '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:"python3 \"${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py\" /tmp/steps.json"}}]}}'
}

# A Bash tool_result carrying arbitrary text (route.py's fail() output, etc.).
text_result_line() { # text
  jq -c -n --arg body "$1" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",content:$body}]}}'
}

# A Bash tool_result carrying route.py's failure marker, embedded the way
# it really lands in a transcript (fail() prints it on stderr, which the
# Bash tool still surfaces inside its tool_result).
fail_marker_line() { # exit-code
  jq -c -n --argjson code "$1" \
    '"1337-tier-failed: " + ({exit:$code} | tostring)' \
  | jq -c -n --argjson body "$(cat)" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",content:$body}]}}'
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
check_grep 2 'still owes this step (none)' "budget spent: fourth dispatch (same tier, no retry path) refused" \
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

# --- case 9: router failed with a recognisable stderr line, no marker after
# it -> allowed (deadlock guard), one-line notice ---
sid9="rg-9"; tr9="$TMPDIR/tr9.jsonl"
t_tool "$(route_call_line)" "$tr9"
t_tool "$(text_result_line "tier-route: no key: export OPENROUTER_API_KEY")" "$tr9"
check_grep 0 'sizing steps by hand' "router failed (key): allowed, notice on stderr" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr9" "$sid9")"

# --- case 10: router invoked, nothing recognisable follows it (no marker,
# no failure text) -> still treated as a failed attempt, allowed ---
sid10="rg-10"; tr10="$TMPDIR/tr10.jsonl"
t_tool "$(route_call_line)" "$tr10"
check_grep 0 'sizing steps by hand' "router call with no marker and no failure text: allowed" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr10" "$sid10")"

# --- case 11: router invoked and DID produce a marker after it -> normal
# routed flow applies, not the deadlock guard ---
sid11="rg-11"; tr11="$TMPDIR/tr11.jsonl"
t_tool "$(route_call_line)" "$tr11"
t_tool "$(marker_line "$STEPS3")" "$tr11"
check 0 "router call followed by a real marker: normal routed flow, allowed" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr11" "$sid11")"
check_grep 2 'haiku, sonnet, opus' "same transcript: a tier the router never assigned is still refused" \
  "$MODE_TIERED" "$(payload 1337:builder gpt5 "$tr11" "$sid11")"

# --- case 12: a marker line whose JSON fails to parse is refused, not
# allowed (hooks/route-guard.sh's comment says so; the code always has) ---
sid12="rg-12"; tr12="$TMPDIR/tr12.jsonl"
t_tool "$(text_result_line "1337-tier-route: {not valid json")" "$tr12"
check_grep 2 'no tier routing this session' "corrupt marker JSON: refused, not fail-open" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr12" "$sid12")"

# --- case 13: dispatch payload with no model at all -> refused (nothing to
# match against the remaining tiers) ---
sid13="rg-13"; tr13="$TMPDIR/tr13.jsonl"
t_tool "$(marker_line "$STEPS3")" "$tr13"
nomarker_payload=$(jq -c -n --arg tr "$tr13" --arg sid "$sid13" \
  '{tool_name:"Agent",tool_input:{subagent_type:"1337:builder"},transcript_path:$tr,session_id:$sid}')
check_grep 2 'dispatched at model <none>' "no model field: refused" \
  "$MODE_TIERED" "$nomarker_payload"

# --- case 14: a nested dispatch from a subagent (payload carries agent_id)
# always passes, regardless of transcript state ---
sid14="rg-14"
sub_payload=$(jq -c -n --arg tr "$TMPDIR/does-not-exist.jsonl" --arg sid "$sid14" \
  '{agent_id:"abc",tool_name:"Agent",tool_input:{subagent_type:"1337:builder",model:"opus"},transcript_path:$tr,session_id:$sid}')
check 0 "subagent-issued dispatch (agent_id set): always allowed" \
  "$MODE_TIERED" "$sub_payload"

# --- case 15: transcript_path missing from the payload entirely -> allowed,
# silent (same as an unreadable one) ---
sid15="rg-15"
no_transcript_payload=$(jq -c -n --arg sid "$sid15" \
  '{tool_name:"Agent",tool_input:{subagent_type:"1337:builder",model:"haiku"},session_id:$sid}')
check 0 "transcript_path absent from payload: allowed, silent" \
  "$MODE_TIERED" "$no_transcript_payload"

# --- case 16: transcript exists, is readable, but is empty -> refused like
# any other transcript with no marker (not the same as unreadable) ---
sid16="rg-16"; tr16="$TMPDIR/tr16.jsonl"
: > "$tr16"
check_grep 2 'no tier routing this session' "empty (but readable) transcript: refused" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr16" "$sid16")"

# --- case 17: transcript exists but is unreadable -> allowed, silent ---
sid17="rg-17"; tr17="$TMPDIR/tr17.jsonl"
t_tool "$(agent_line Agent 1337:scout haiku)" "$tr17"
chmod 000 "$tr17"
unreadable_ok=0
if [ "$(id -u)" -ne 0 ]; then
  check 0 "unreadable transcript: allowed, silent" \
    "$MODE_TIERED" "$(payload 1337:builder haiku "$tr17" "$sid17")"
else
  printf 'skip unreadable transcript: allowed, silent (running as root, chmod 000 has no effect)\n'
fi
chmod 644 "$tr17"

# --- case 18: route.py failed with exit 3 (no key), failure marker newer
# than the last success marker -> allowed, sizing-by-hand notice ---
sid18="rg-18"; tr18="$TMPDIR/tr18.jsonl"
t_tool "$(route_call_line)" "$tr18"
t_tool "$(fail_marker_line 3)" "$tr18"
check_grep 0 'sizing steps by hand' "failure marker exit 3: allowed, notice" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr18" "$sid18")"

# --- case 19: route.py failed with exit 4 (API call failed), same ---
sid19="rg-19"; tr19="$TMPDIR/tr19.jsonl"
t_tool "$(route_call_line)" "$tr19"
t_tool "$(fail_marker_line 4)" "$tr19"
check_grep 0 'sizing steps by hand' "failure marker exit 4: allowed, notice" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr19" "$sid19")"

# --- case 20: route.py failed with exit 2 (bad input), failure marker
# newer than the last success marker -> REFUSED, names the fix ---
sid20="rg-20"; tr20="$TMPDIR/tr20.jsonl"
t_tool "$(route_call_line)" "$tr20"
t_tool "$(fail_marker_line 2)" "$tr20"
check_grep 2 'rejected its steps file' "failure marker exit 2: refused, names the fix" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr20" "$sid20")"

# --- case 21: a failure marker OLDER than the last success marker is
# stale and means nothing: the normal routed flow applies ---
sid21="rg-21"; tr21="$TMPDIR/tr21.jsonl"
t_tool "$(fail_marker_line 2)" "$tr21"
t_tool "$(marker_line "$STEPS3")" "$tr21"
check 0 "stale exit-2 failure marker (older than success): normal routed flow, allowed" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr21" "$sid21")"

# --- case 22: a builder dispatch another PreToolUse hook refused never ran,
# so it spends no routed tier: the next dispatch at that tier is allowed ---
STEPS1_HAIKU='[{"id":1,"tier":"haiku","confidence":0.9,"escalated":false}]'
builder_use_line() { # id model
  jq -c -n --arg id "$1" --arg m "$2" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:"1337:builder",model:$m}}]}}'
}
sid22="rg-22"; tr22="$TMPDIR/tr22.jsonl"
t_tool "$(marker_line "$STEPS1_HAIKU")" "$tr22"
t_tool "$(builder_use_line toolu_refused haiku)" "$tr22"
t_tool "$(jq -c -n '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_refused",is_error:true,content:"PreToolUse:Agent hook error: [\"/x/hooks/review-gate.sh\"]: blocked (1337 orchestrator mode): review first"}]}}')" "$tr22"
check 0 "hook-refused earlier dispatch spends nothing: next haiku dispatch allowed" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr22" "$sid22")"

# --- case 23: control for case 22: the earlier dispatch ran, so the one
# routed step is spent and the next dispatch is refused ---
sid23="rg-23"; tr23="$TMPDIR/tr23.jsonl"
t_tool "$(marker_line "$STEPS1_HAIKU")" "$tr23"
t_tool "$(builder_use_line toolu_ran haiku)" "$tr23"
t_tool "$(jq -c -n '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_ran",content:[{type:"text",text:"Async agent launched successfully."}]}]}}')" "$tr23"
check_grep 2 'still owes this step (none)' "earlier dispatch ran: next haiku dispatch (no retry path) refused" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr23" "$sid23")"

# --- case 24: haiku step's slot is spent -> the one retry at sonnet
# (routed+1) is allowed (task #676) ---
STEPS1_HAIKU='[{"id":1,"tier":"haiku","confidence":0.9,"escalated":false}]'
sid24="rg-24"; tr24="$TMPDIR/tr24.jsonl"
t_tool "$(marker_line "$STEPS1_HAIKU")" "$tr24"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr24"
check 0 "haiku step spent: sonnet retry allowed" \
  "$MODE_TIERED" "$(payload 1337:builder sonnet "$tr24" "$sid24")"

# --- case 25: same spent haiku step, opus (routed+2) refused: the retry
# only reaches one tier up, never a jump ---
sid25="rg-25"; tr25="$TMPDIR/tr25.jsonl"
t_tool "$(marker_line "$STEPS1_HAIKU")" "$tr25"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr25"
check_grep 2 'still owes this step (none)' "haiku step spent: opus refused (+2 jump)" \
  "$MODE_TIERED" "$(payload 1337:builder opus "$tr25" "$sid25")"

# --- case 26: same spent haiku step, haiku again refused: a same-tier
# extra dispatch is not the retry ---
sid26="rg-26"; tr26="$TMPDIR/tr26.jsonl"
t_tool "$(marker_line "$STEPS1_HAIKU")" "$tr26"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr26"
check_grep 2 'still owes this step (none)' "haiku step spent: haiku again refused (same-tier extra)" \
  "$MODE_TIERED" "$(payload 1337:builder haiku "$tr26" "$sid26")"

# --- case 27: the one sonnet retry already used -> a second sonnet retry
# is refused (retries are consumed, not a standing allowance) ---
sid27="rg-27"; tr27="$TMPDIR/tr27.jsonl"
t_tool "$(marker_line "$STEPS1_HAIKU")" "$tr27"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr27"
t_tool "$(agent_line Agent 1337:builder sonnet)" "$tr27"
check_grep 2 'still owes this step (none)' "sonnet retry already spent: second sonnet retry refused" \
  "$MODE_TIERED" "$(payload 1337:builder sonnet "$tr27" "$sid27")"

# --- case 28: an opus-routed step's slot is spent -> no retry exists past
# opus, any further dispatch for it is refused ---
STEPS1_OPUS='[{"id":1,"tier":"opus","confidence":0.9,"escalated":false}]'
sid28="rg-28"; tr28="$TMPDIR/tr28.jsonl"
t_tool "$(marker_line "$STEPS1_OPUS")" "$tr28"
t_tool "$(agent_line Agent 1337:builder opus)" "$tr28"
check_grep 2 'still owes this step (none)' "opus-routed step spent: no retry exists, refused" \
  "$MODE_TIERED" "$(payload 1337:builder opus "$tr28" "$sid28")"

# --- case 29: two routed steps (haiku, sonnet), both spent -> the sonnet
# retry (for haiku) and the opus retry (for sonnet) are each allowed once,
# independently ---
STEPS2_HS='[{"id":1,"tier":"haiku","confidence":0.9,"escalated":false},{"id":2,"tier":"sonnet","confidence":0.8,"escalated":false}]'
sid29="rg-29"; tr29="$TMPDIR/tr29.jsonl"
t_tool "$(marker_line "$STEPS2_HS")" "$tr29"
t_tool "$(agent_line Agent 1337:builder haiku)" "$tr29"
t_tool "$(agent_line Agent 1337:builder sonnet)" "$tr29"
check 0 "two steps both spent: sonnet retry (for haiku) allowed" \
  "$MODE_TIERED" "$(payload 1337:builder sonnet "$tr29" "$sid29")"
check 0 "two steps both spent: opus retry (for sonnet) allowed" \
  "$MODE_TIERED" "$(payload 1337:builder opus "$tr29" "$sid29")"

exit $fail
