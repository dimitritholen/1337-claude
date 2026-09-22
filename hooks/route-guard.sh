#!/usr/bin/env bash
# PreToolUse hook for Agent|Task, active only in tiered mode (plugin option
# `tiered`, or CLAUDE_1337_TIERED=1). Enforces that every 1337:builder
# dispatch spends a model tier the router actually assigned, instead of a
# hand-picked one.
#
# Scope: only a call with subagent_type "1337:builder" is judged; every
# other agent type, and any payload without a subagent_type, passes. A
# dispatch made by a subagent rather than the main session (payload carries
# agent_id) always passes too: the main session routes, or falls back,
# before it ever calls one — mirrors hooks/orchestrator-guard.sh:97-98 and
# the subagent carve-out in hooks/read-cap.sh.
#
# Evidence: the session transcript (JSONL, at .transcript_path) is scanned
# for the LAST line matching the marker `1337-tier-route: `, printed by
# skills/tier/route.py on stdout (so it lands inside a tool_result of a Bash
# call). What follows the prefix is JSON: {"model":..., "floor":...,
# "steps":[{"id":..,"tier":"sonnet","confidence":..,"escalated":bool}, ...]}.
# Each transcript line is one JSONL entry, so a `grep -n` line number IS
# that entry's position: only the tail after the last marker line is ever
# parsed with jq (task #674 — a 22MB transcript slurped whole into one jq -s
# array cost 0.56s/147MB; grep -n streams the search instead).
#
# No marker anywhere in the transcript means the router never ran this
# session: refused. Otherwise the routed tiers (one per step) form a
# multiset; every 1337:builder dispatch found AFTER that last marker line
# spends one entry, in dispatch order, with owed (still-unspent) tiers
# always spent first regardless of which model is dispatched next. Once a
# tier's slot is spent this way it earns exactly ONE retry dispatch at the
# next tier up (haiku -> sonnet -> opus; an opus-routed step has no further
# tier, so no retry — task #676). A dispatch matching neither a remaining
# owed tier nor an unused retry is refused. A later marker resets the
# budget: only dispatches after the LAST marker count. A marker line whose
# JSON fails to parse is treated the same as no marker at all (refused) — a
# corrupt or forged marker must not buy a dispatch.
#
# Deadlock guard (task #674): skills/tier/route.py exits 3 with no key and 4
# when the API call itself failed; hooks/tiered.md already tells the session
# to size those steps by hand instead of retrying. route.py's fail() also
# prints a failure marker (`1337-tier-failed: {"exit":N}`, same
# tool_result-only extraction as the success marker) as the last thing it
# does before exiting, so this hook reads the exit code instead of
# inferring it from absence:
#   - a failure marker with exit 3 or 4, newer than the last success
#     marker, means routing was unavailable (no key, or the call failed):
#     1337:builder dispatches are let through with a one-line stderr
#     notice instead of refused forever.
#   - a failure marker with exit 2, newer than the last success marker,
#     means route.py rejected its own input (bad steps file) — fixable by
#     the session that wrote it, so this REFUSES, naming the fix.
#   - a failure marker older than the last success marker is stale
#     (a later, successful re-route supersedes it) and means nothing.
#   - a route.py invocation with neither marker after it (an old route.py
#     from before this hook could recognise a failure marker, for
#     instance) falls back to today's behaviour: allow with the notice, so
#     it can never deadlock a session.
# `CLAUDE_1337_ROUTE_GUARD=off` disables the whole hook, same `off`
# convention as CLAUDE_1337_READ_CAP/GREP_CAP in hooks/read-cap.sh.
#
# Mirrors the mode gate of hooks/tiered-rules.sh and hooks/dispatch-nudge.sh
# (same four env switches), and the transcript-parsing/refusal shape of
# hooks/dispatch-nudge.sh and hooks/orchestrator-guard.sh.
#
# This step does not fail open on: no jq, a payload that fails to parse, or
# a payload with no `model` at all (that dispatch is simply refused: with no
# model to compare, it can never be "one of the remaining tiers"). A
# missing/unreadable transcript_path stays silent (this step cannot tell
# "router never ran" from "cannot see the transcript"); an existing, readable
# but empty transcript is NOT the same thing — no marker can be in it, so it
# is refused like any other transcript with no marker.
#
# Exit 2 + stderr refuses; exit 0 allows.
set -u

[ "${CLAUDE_PLUGIN_OPTION_TIERED:-false}" = "true" ] || [ "${CLAUDE_1337_TIERED:-0}" = "1" ] || [ "${EVAL_CLAUDE_1337_TIERED:-0}" = "1" ] || exit 0

# `off` (any case) disables this hook entirely.
guard_lc=$(printf '%s' "${CLAUDE_1337_ROUTE_GUARD:-}" | tr '[:upper:]' '[:lower:]')
[ "$guard_lc" != "off" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"

# A nested dispatch made by a subagent, not the main session, always passes.
agent_id=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
case "$tool" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

subagent_type=$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
[ "$subagent_type" = "1337:builder" ] || exit 0

model=$(printf '%s' "$payload" | jq -r '.tool_input.model // empty' 2>/dev/null) || exit 0

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
# A missing/unreadable transcript is one of the #674 fail-open cases: this
# step cannot tell "router never ran" from "cannot see the transcript", so
# it stays silent rather than guessing.
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -r "$transcript" ] || exit 0

MARKER_PREFIX='1337-tier-route: '
FAIL_PREFIX='1337-tier-failed: '

# Last file line that could hold a marker, last file line that could hold a
# failure marker, and last file line that could be a route.py invocation.
# `grep -n -F` streams the file; it does not load it.
marker_ln=$(grep -n -F -- "$MARKER_PREFIX" "$transcript" 2>/dev/null | tail -1 | cut -d: -f1)
fail_ln=$(grep -n -F -- "$FAIL_PREFIX" "$transcript" 2>/dev/null | tail -1 | cut -d: -f1)
route_ln=$(grep -n -F -- 'skills/tier/route.py' "$transcript" 2>/dev/null | tail -1 | cut -d: -f1)

# The evidence: if the last failure marker is newer than the last success
# marker, read its exit code from the tool_result that carries it — same
# extraction the success marker gets a few lines down, so prose that merely
# quotes the marker text (not inside a tool_result) grants nothing.
fail_exit=""
if [ -n "$fail_ln" ] && { [ -z "$marker_ln" ] || [ "$fail_ln" -gt "$marker_ln" ]; }; then
  fail_json=$(sed -n "${fail_ln}p" "$transcript" | jq -r --arg mp "$FAIL_PREFIX" '
    def texts_of(entry):
      (entry.message.content? // [])
      | if type == "array" then
          [.[] | select(.type == "tool_result")
            | (.content
                | if type == "string" then .
                  elif type == "array" then ([.[]? | select(.type == "text") | .text] | join("\n"))
                  else empty end)]
        else [] end;
    ([texts_of(.)[]? | split("\n")[] | select(startswith($mp))] | last // empty)
  ' 2>/dev/null)
  fail_json="${fail_json#"$FAIL_PREFIX"}"
  if [ -n "$fail_json" ]; then
    fail_exit=$(printf '%s' "$fail_json" | jq -r 'if type == "object" and (.exit | type) == "number" then (.exit | tostring) else empty end' 2>/dev/null)
  fi
fi

case "$fail_exit" in
  3|4)
    printf '1337 tiered mode: the last tier-router attempt this session did not route (no key, or the call failed) — sizing steps by hand per hooks/tiered.md; 1337:builder dispatch allowed without a routed tier this once.\n' >&2
    exit 0
    ;;
  2)
    printf 'blocked (1337 tiered mode): the last tier-router attempt this session rejected its steps file (bad input). Fix the steps file and run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` again before dispatching.\n' >&2
    exit 2
    ;;
esac

# The deadlock guard: the most recent route.py invocation (if any) produced
# no marker after it at all — an old route.py from before this hook could
# recognise a failure marker, for instance. Must not deadlock the session.
if [ -n "$route_ln" ] && { [ -z "$marker_ln" ] || [ "$route_ln" -gt "$marker_ln" ]; }; then
  printf '1337 tiered mode: the last tier-router attempt this session did not route (no key, or the call failed) — sizing steps by hand per hooks/tiered.md; 1337:builder dispatch allowed without a routed tier this once.\n' >&2
  exit 0
fi

if [ -z "$marker_ln" ]; then
  printf 'blocked (1337 tiered mode): 1337:builder dispatched with no tier routing this session. Write the steps to a JSON file and run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` once for all of them, then dispatch at the tier it assigns.\n' >&2
  exit 2
fi

# Extract the marker's JSON payload from just that one line: same
# tool_result/text-splitting shape as before, applied to a single entry.
marker_json=$(sed -n "${marker_ln}p" "$transcript" | jq -r --arg mp "$MARKER_PREFIX" '
  def texts_of(entry):
    (entry.message.content? // [])
    | if type == "array" then
        [.[] | select(.type == "tool_result")
          | (.content
              | if type == "string" then .
                elif type == "array" then ([.[]? | select(.type == "text") | .text] | join("\n"))
                else empty end)]
      else [] end;
  ([texts_of(.)[]? | split("\n")[] | select(startswith($mp))] | last // empty)
' 2>/dev/null)
marker_json="${marker_json#"$MARKER_PREFIX"}"

if [ -z "$marker_json" ] || ! printf '%s' "$marker_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  printf 'blocked (1337 tiered mode): 1337:builder dispatched with no tier routing this session. Write the steps to a JSON file and run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` once for all of them, then dispatch at the tier it assigns.\n' >&2
  exit 2
fi

# Only the tail after the marker line matters: dispatches spend the budget
# in file order. hooks/lib/builder-dispatches.jq drops a dispatch another
# PreToolUse hook refused (it never ran, so it spent nothing) and keeps
# pending and self-failed ones.
dispatches_jq="$(dirname "$0")/lib/builder-dispatches.jq"
dispatched=$(tail -n "+$((marker_ln + 1))" "$transcript" \
  | jq -R -s --argjson offset "$marker_ln" -f "$dispatches_jq" 2>/dev/null \
  | jq -c '[.[] | (.model // "")]' 2>/dev/null) || exit 0
[ -n "$dispatched" ] || exit 0

# Replay the dispatches since the last marker to get the current budget: an
# owed (still-unspent) routed tier is always spent first, in dispatch
# order; only once a tier's slot is spent this way does it earn ONE retry
# at the next tier up (task #676 — a failed check sends the builder back
# one tier above the routed one, per hooks/tiered.md, and that retry must
# not also cost the budget refusal a hand-picked model would). `remaining`
# is the routed multiset minus spent owed slots (same one-for-one removal
# as before); `retries` lists, for message purposes, every tier still
# reachable through an unused retry.
guard=$(jq -n --argjson marker "$marker_json" --argjson dispatched "$dispatched" --arg model "$model" '
  def next_tier(t): if t == "haiku" then "sonnet" elif t == "sonnet" then "opus" else null end;
  def prev_tier(t): if t == "sonnet" then "haiku" elif t == "opus" then "sonnet" else null end;
  def remove_one(arr; x):
    (arr | index(x)) as $i
    | if $i == null then arr else (arr[0:$i] + arr[$i+1:]) end;
  def count_of(arr; x): [arr[] | select(. == x)] | length;
  # Unused retries earned by tier t: how many of its slots are spent
  # (routed count minus what is still in `remaining`), minus how many of
  # those spent slots already cashed in their one retry.
  def avail(routed; state; t): (count_of(routed; t) - count_of(state.remaining; t)) - count_of(state.retried; t);

  ([$marker.steps[].tier]) as $routed
  | (reduce $dispatched[] as $m ({remaining: $routed, retried: []};
       if (.remaining | index($m)) != null then
         .remaining |= remove_one(.; $m)
       else
         (prev_tier($m)) as $t
         | if $t != null and avail($routed; .; $t) > 0
           then .retried += [$t]
           else . end
       end
     )) as $state
  | ($state.remaining | index($model)) as $owed_i
  | (prev_tier($model)) as $mprev
  | (($mprev != null) and (avail($routed; $state; $mprev) > 0)) as $retry_ok
  | ([("haiku", "sonnet") | select(avail($routed; $state; .) > 0) | next_tier(.)]) as $retries
  | {allowed: (($owed_i != null) or $retry_ok), remaining: $state.remaining, retries: $retries}
' 2>/dev/null) || exit 0
[ -n "$guard" ] || exit 0

allowed=$(printf '%s' "$guard" | jq -r '.allowed' 2>/dev/null) || exit 0
[ "$allowed" = "true" ] && exit 0

remaining_list=$(printf '%s' "$guard" | jq -r '.remaining | join(", ")' 2>/dev/null) || exit 0
[ -n "$remaining_list" ] || remaining_list="none"
retries_list=$(printf '%s' "$guard" | jq -r '.retries | join(", ")' 2>/dev/null) || exit 0

if [ -n "$retries_list" ]; then
  printf 'blocked (1337 tiered mode): 1337:builder dispatched at model %s, not one of the tiers routing still owes this step (%s), nor the one retry it still owes (%s). Dispatch at one of those, or run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` again to re-route.\n' \
    "${model:-<none>}" "$remaining_list" "$retries_list" >&2
else
  printf 'blocked (1337 tiered mode): 1337:builder dispatched at model %s, not one of the tiers routing still owes this step (%s). Dispatch at one of the remaining tiers, or run `python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <file>` again to re-route.\n' \
    "${model:-<none>}" "$remaining_list" >&2
fi
exit 2
